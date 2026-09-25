import XCTest
import PDFKit
import CoreGraphics
import CoreText
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import GraphiteCore
@testable import GraphiteApple

/// PDF annotation editing: incremental ink, text markup, bookmarks, and the save path.
final class PDFAnnotationTests: XCTestCase {
    private let pageText = "Graphite keeps lecture notes in ordinary files"

    private func blankDocument(pageCount: Int = 1) throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: pageCount)))
    }

    /// A one-page PDF with one line of real text, so PDFKit can select it.
    private func textDocumentData() throws -> Data {
        let output = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        let consumer = try XCTUnwrap(CGDataConsumer(data: output))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        let attributedText = NSAttributedString(string: pageText, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributedText)
        context.textPosition = CGPoint(x: 60, y: 700)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

    private func stroke(named name: String, from start: CGPoint, to end: CGPoint, outlineHalfHeight: Double = 10) -> PortableInkStroke {
        // A thin center line with a much taller outline: only the saved appearance
        // stream can make the tall part visible.
        let outline = [[CGPoint(x: start.x, y: start.y - outlineHalfHeight), CGPoint(x: end.x, y: end.y - outlineHalfHeight),
                        CGPoint(x: end.x, y: end.y + outlineHalfHeight), CGPoint(x: start.x, y: start.y + outlineHalfHeight)]]
        return PortableInkStroke(name: name, segments: [[start, end]], width: 1, red: 0, green: 0, blue: 0, alpha: 1, outline: outline)
    }

    private func reopened(_ document: PDFDocument) throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation())))
    }

    private func inkNames(on page: PDFPage) -> [String] {
        page.annotations.filter { annotation in annotation.type == "Ink" }.compactMap(\.persistentName)
    }

    // MARK: Pencil ink

    func testOutlinedInkIsSavedAsAppearanceStreamWithStandardInkList() throws {
        let document = try blankDocument()
        let update = PDFInkUpdate(pageIndex: 0, group: "ink", removal: .strokes([]),
                                  addedStrokes: [stroke(named: "stroke-1", from: CGPoint(x: 100, y: 400), to: CGPoint(x: 400, y: 400))],
                                  editableRecord: PDFEditableInkRecord(drawingData: Data([1, 2, 3]), strokeNames: ["stroke-1"]))
        try PDFPageManager.apply(.updateInk(update), to: document, drawsInkOutlines: true)
        let fileData = try XCTUnwrap(document.dataRepresentation())

        // PDFKit reopens a standard ink annotation with its center line and name.
        let page = try XCTUnwrap(PDFDocument(data: fileData)?.page(at: 0))
        let annotation = try XCTUnwrap(page.annotations.first)
        XCTAssertEqual(annotation.type, "Ink")
        XCTAssertEqual(annotation.paths?.count, 1)
        XCTAssertEqual(annotation.value(forAnnotationKey: .name) as? String, "stroke-1", "The standard /NM name is written.")
        XCTAssertLessThan(annotation.bounds.width, 330, "The annotation rectangle fits the stroke, not the page.")
        // The tall outline is visible 8 points above the 1-point center line.
        let image = page.thumbnail(of: CGSize(width: 595, height: 842), for: .cropBox)
        XCTAssertTrue(try InteroperabilityTests.hasDarkPixel(in: image, pdfPoint: CGPoint(x: 250, y: 408), pageHeight: 842))
        XCTAssertFalse(try InteroperabilityTests.hasDarkPixel(in: image, pdfPoint: CGPoint(x: 250, y: 425), pageHeight: 842))

        // CoreGraphics, an independent parser, finds /InkList and a filled appearance stream.
        try Self.withFirstAnnotationDictionary(in: fileData) { annotationDictionary in
            var inkList: CGPDFArrayRef?
            XCTAssertTrue(CGPDFDictionaryGetArray(annotationDictionary, "InkList", &inkList))
            XCTAssertEqual(inkList.map(CGPDFArrayGetCount), 1)
            let appearance = try XCTUnwrap(Self.normalAppearanceContent(of: annotationDictionary))
            XCTAssertTrue(appearance.contains(" f") || appearance.contains("f\n"), "The appearance fills the outline: \(appearance.prefix(200))")
        }
    }

    /// PDFKit rewrites annotations differently when a save also changes the page tree;
    /// names, ink appearance and markup quadrilaterals must survive that path too.
    func testAnnotationsSurviveSavesThatAlsoChangePages() throws {
        let document = try XCTUnwrap(PDFDocument(data: textDocumentData()))
        let lineBounds = try XCTUnwrap(document.findString("Graphite", withOptions: []).first?.markupLinesByPage(in: document).first?.lineBounds)
        let edits: [PDFEdit] = [
            .updateInk(PDFInkUpdate(pageIndex: 0, group: "ink", removal: .strokes([]),
                                    addedStrokes: [stroke(named: "A", from: CGPoint(x: 100, y: 400), to: CGPoint(x: 400, y: 400))],
                                    editableRecord: PDFEditableInkRecord(drawingData: Data([1]), strokeNames: ["A"]))),
            .addMarkup(page: 0, markup: PDFMarkup(name: "H", kind: .highlight, color: .blue, lineBounds: lineBounds)),
            .insert(data: try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .grid)), at: 0),
            .duplicate(page: 1),
        ]
        for edit in edits { try PDFPageManager.apply(edit, to: document, drawsInkOutlines: true) }
        let reopenedDocument = try reopened(document)
        XCTAssertEqual(reopenedDocument.pageCount, 3)
        for pageIndex in [1, 2] {
            let page = try XCTUnwrap(reopenedDocument.page(at: pageIndex))
            XCTAssertEqual(inkNames(on: page), ["A"])
            XCTAssertEqual(page.annotations.first { annotation in annotation.type == "Highlight" }?.persistentName, "H")
            XCTAssertEqual(page.annotations.first { annotation in annotation.type == "Highlight" }?.quadrilateralPoints?.count, 4)
            XCTAssertEqual(PDFInkGroups.editableGroup(on: page)?.record.strokeNames, ["A"])
            let image = page.thumbnail(of: CGSize(width: 595, height: 842), for: .cropBox)
            XCTAssertTrue(try InteroperabilityTests.hasDarkPixel(in: image, pdfPoint: CGPoint(x: 250, y: 408), pageHeight: 842))
        }
    }

    func testInkUpdatesChangeOnlyTheNamedStrokesAndKeepOneEditableRecord() throws {
        let document = try blankDocument()
        let first = PDFInkUpdate(pageIndex: 0, group: "ink", removal: .strokes([]),
                                 addedStrokes: [stroke(named: "A", from: CGPoint(x: 50, y: 100), to: CGPoint(x: 150, y: 100)),
                                                stroke(named: "B", from: CGPoint(x: 50, y: 200), to: CGPoint(x: 150, y: 200))],
                                 editableRecord: PDFEditableInkRecord(drawingData: Data([1]), strokeNames: ["A", "B"]))
        try PDFPageManager.apply(.updateInk(first), to: document)
        let page = try XCTUnwrap(document.page(at: 0))
        let annotationB = try XCTUnwrap(page.annotations.first { annotation in annotation.value(forAnnotationKey: .name) as? String == "B" })
        let second = PDFInkUpdate(pageIndex: 0, group: "ink", removal: .strokes(["A"]),
                                  addedStrokes: [stroke(named: "C", from: CGPoint(x: 50, y: 300), to: CGPoint(x: 150, y: 300))],
                                  editableRecord: PDFEditableInkRecord(drawingData: Data([2]), strokeNames: ["B", "", "C"]))
        try PDFPageManager.apply(.updateInk(second), to: document)
        XCTAssertEqual(inkNames(on: page), ["B", "C"])
        XCTAssertTrue(page.annotations.contains { annotation in annotation === annotationB }, "Unchanged strokes keep their annotation.")

        let reopenedPage = try XCTUnwrap(reopened(document).page(at: 0))
        let editableGroup = try XCTUnwrap(PDFInkGroups.editableGroup(on: reopenedPage))
        XCTAssertEqual(editableGroup.group, "ink")
        XCTAssertEqual(editableGroup.record, PDFEditableInkRecord(drawingData: Data([2]), strokeNames: ["B", "", "C"]))
        XCTAssertEqual(reopenedPage.annotations.filter { annotation in annotation.value(forAnnotationKey: PDFPageManager.drawingKey) != nil }.count, 1)
    }

    func testMergedInkUpdatesEqualSequentialUpdates() throws {
        let updates = [
            PDFInkUpdate(pageIndex: 0, group: "ink", removal: .strokes([]),
                         addedStrokes: [stroke(named: "A", from: CGPoint(x: 50, y: 100), to: CGPoint(x: 150, y: 100)),
                                        stroke(named: "B", from: CGPoint(x: 50, y: 200), to: CGPoint(x: 150, y: 200))],
                         editableRecord: PDFEditableInkRecord(drawingData: Data([1]), strokeNames: ["A", "B"])),
            PDFInkUpdate(pageIndex: 0, group: "ink", removal: .strokes(["A"]),
                         addedStrokes: [stroke(named: "C", from: CGPoint(x: 50, y: 300), to: CGPoint(x: 150, y: 300))],
                         editableRecord: PDFEditableInkRecord(drawingData: Data([2]), strokeNames: ["B", "C"])),
            PDFInkUpdate(pageIndex: 0, group: "ink", removal: .strokes(["B", "old"]),
                         addedStrokes: [stroke(named: "D", from: CGPoint(x: 50, y: 400), to: CGPoint(x: 150, y: 400))],
                         editableRecord: PDFEditableInkRecord(drawingData: Data([3]), strokeNames: ["C", "D"])),
        ]
        let existingStroke = stroke(named: "old", from: CGPoint(x: 300, y: 500), to: CGPoint(x: 400, y: 500))
        let sequentialDocument = try blankDocument(), mergedDocument = try blankDocument()
        for document in [sequentialDocument, mergedDocument] {
            try PDFPageManager.apply(.updateInk(PDFInkUpdate(pageIndex: 0, group: "ink", removal: .strokes([]), addedStrokes: [existingStroke], editableRecord: nil)), to: document)
        }
        for update in updates { try PDFPageManager.apply(.updateInk(update), to: sequentialDocument) }
        let merged = try XCTUnwrap(updates.dropFirst().reduce(updates[0]) { mergedSoFar, update in try XCTUnwrap(mergedSoFar.merged(with: update)) })
        try PDFPageManager.apply(.updateInk(merged), to: mergedDocument)
        let sequentialPage = try XCTUnwrap(sequentialDocument.page(at: 0)), mergedPage = try XCTUnwrap(mergedDocument.page(at: 0))
        XCTAssertEqual(inkNames(on: sequentialPage), ["C", "D"])
        XCTAssertEqual(inkNames(on: mergedPage), inkNames(on: sequentialPage))
        XCTAssertEqual(PDFInkGroups.editableGroup(on: mergedPage), PDFInkGroups.editableGroup(on: sequentialPage))
        XCTAssertNil(updates[0].merged(with: PDFInkUpdate(pageIndex: 1, group: "ink", removal: .strokes([]), addedStrokes: [], editableRecord: nil)))
    }

    func testInkRemovedByAnotherApplicationMakesTheGroupReadOnly() throws {
        let document = try blankDocument()
        let update = PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes([]),
                                  addedStrokes: [stroke(named: "A", from: CGPoint(x: 50, y: 100), to: CGPoint(x: 150, y: 100)),
                                                 stroke(named: "B", from: CGPoint(x: 50, y: 200), to: CGPoint(x: 150, y: 200))],
                                  editableRecord: PDFEditableInkRecord(drawingData: Data([1]), strokeNames: ["A", "B"]))
        try PDFPageManager.apply(.updateInk(update), to: document)
        let edited = try reopened(document)
        let page = try XCTUnwrap(edited.page(at: 0))
        XCTAssertNotNil(PDFInkGroups.editableGroup(on: page))
        // Another application deletes stroke B.
        let annotationB = try XCTUnwrap(page.annotations.first { annotation in annotation.value(forAnnotationKey: .name) as? String == "B" })
        page.removeAnnotation(annotationB)
        let externallyEditedPage = try XCTUnwrap(reopened(edited).page(at: 0))
        XCTAssertNil(PDFInkGroups.editableGroup(on: externallyEditedPage), "Stroke data no longer matches the visible ink.")
        let newGroup = PDFInkGroups.newGroup(on: externallyEditedPage)
        XCTAssertNotEqual(newGroup, PDFInkGroups.defaultGroup, "New ink must never replace the remaining visible ink.")
        XCTAssertEqual(inkNames(on: externallyEditedPage), ["A"])
    }

    func testDrawingsWithoutStrokeNamesStayEditable() throws {
        let document = try blankDocument()
        let legacyStroke = PortableInkStroke(name: nil, segments: [[CGPoint(x: 20, y: 30), CGPoint(x: 100, y: 140)]], width: 3, red: 0, green: 0, blue: 0, alpha: 1, outline: nil)
        try Self.writeInkWithoutStrokeNames(legacyStroke, drawingData: Data([7]), on: XCTUnwrap(document.page(at: 0)))
        let editableGroup = try XCTUnwrap(PDFInkGroups.editableGroup(on: XCTUnwrap(reopened(document).page(at: 0))))
        XCTAssertFalse(editableGroup.hasStrokeNames)
        XCTAssertEqual(editableGroup.record.drawingData, Data([7]))
    }

    func testStrokeNamesEncodingKeepsEmptyNames() {
        for names in [["A"], ["", "B", ""], [""], ["A", "B"]] {
            XCTAssertEqual(PDFInkGroups.decodeStrokeNames(PDFInkGroups.encodeStrokeNames(names)), names)
        }
        XCTAssertEqual(PDFInkGroups.decodeStrokeNames("3:A,B"), [], "A wrong count is rejected.")
        XCTAssertEqual(PDFInkGroups.decodeStrokeNames("garbage"), [])
    }

    // MARK: Text markup

    func testSelectedTextBecomesStandardMarkupThatOtherReadersSee() throws {
        let document = try XCTUnwrap(PDFDocument(data: textDocumentData()))
        let selection = try XCTUnwrap(document.findString("lecture notes", withOptions: []).first)
        let lines = selection.markupLinesByPage(in: document)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.pageIndex, 0)
        let markup = PDFMarkup(name: "highlight-1", kind: .highlight, color: .yellow, lineBounds: try XCTUnwrap(lines.first?.lineBounds))
        try PDFPageManager.apply(.addMarkup(page: 0, markup: markup), to: document)
        try PDFPageManager.apply(.addMarkup(page: 0, markup: PDFMarkup(name: "underline-1", kind: .underline, color: .red, lineBounds: markup.lineBounds)), to: document)
        try PDFPageManager.apply(.addMarkup(page: 0, markup: PDFMarkup(name: "strike-1", kind: .strikeOut, color: .red, lineBounds: markup.lineBounds)), to: document)
        let fileData = try XCTUnwrap(document.dataRepresentation())

        let page = try XCTUnwrap(PDFDocument(data: fileData)?.page(at: 0))
        XCTAssertEqual(page.annotations.map(\.type), ["Highlight", "Underline", "StrikeOut"])
        let highlight = try XCTUnwrap(page.annotations.first)
        XCTAssertEqual(highlight.quadrilateralPoints?.count, 4)
        XCTAssertEqual(PDFMarkup(annotation: highlight)?.color, .yellow)
        XCTAssertEqual(PDFMarkup(annotation: highlight)?.name, "highlight-1")
        let restoredLine = try XCTUnwrap(PDFMarkup(annotation: highlight)?.lineBounds.first)
        XCTAssertEqual(restoredLine.minX, markup.lineBounds[0].minX, accuracy: 0.5)
        XCTAssertEqual(restoredLine.maxY, markup.lineBounds[0].maxY, accuracy: 0.5)

        // CoreGraphics reads the standard subtype and one quadrilateral (8 numbers).
        try Self.withFirstAnnotationDictionary(in: fileData) { annotationDictionary in
            var subtype: UnsafePointer<Int8>?
            XCTAssertTrue(CGPDFDictionaryGetName(annotationDictionary, "Subtype", &subtype))
            XCTAssertEqual(subtype.map { name in String(cString: name) }, "Highlight")
            var quadPoints: CGPDFArrayRef?
            XCTAssertTrue(CGPDFDictionaryGetArray(annotationDictionary, "QuadPoints", &quadPoints))
            XCTAssertEqual(quadPoints.map(CGPDFArrayGetCount), 8)
        }
        // Highlighted text stays readable: the glyphs are still dark after rendering.
        let image = page.thumbnail(of: CGSize(width: 595, height: 842), for: .cropBox)
        let glyphPoint = CGPoint(x: restoredLine.minX + 4, y: restoredLine.midY)
        XCTAssertTrue(try Self.hasPixel(in: image, pdfPoint: glyphPoint, pageHeight: 842) { red, green, blue in red < 120 && green < 120 && blue < 120 })
        XCTAssertTrue(try Self.hasPixel(in: image, pdfPoint: glyphPoint, pageHeight: 842) { red, green, blue in red > 200 && green > 180 && blue < 150 },
                      "The highlight tint surrounds the glyphs.")
    }

    func testMarkupCanBeRecoloredAndRemovedAfterReopening() throws {
        let document = try XCTUnwrap(PDFDocument(data: textDocumentData()))
        let selection = try XCTUnwrap(document.findString("Graphite", withOptions: []).first)
        let lineBounds = try XCTUnwrap(selection.markupLinesByPage(in: document).first?.lineBounds)
        let markup = PDFMarkup(kind: .highlight, color: .yellow, lineBounds: lineBounds)
        try PDFPageManager.apply(.addMarkup(page: 0, markup: markup), to: document)
        let reopenedDocument = try reopened(document)
        let page = try XCTUnwrap(reopenedDocument.page(at: 0))
        let highlight = try XCTUnwrap(page.markupAnnotation(at: CGPoint(x: markup.bounds.midX, y: markup.bounds.midY)))
        let reference = PDFAnnotationReference(annotation: highlight, pageIndex: 0)
        try PDFPageManager.apply(.recolorMarkup(reference, color: .green), to: reopenedDocument)
        XCTAssertEqual(PDFMarkup(annotation: try XCTUnwrap(reopened(reopenedDocument).page(at: 0)?.annotations.first))?.color, .green)
        try PDFPageManager.apply(.removeAnnotation(reference), to: reopenedDocument)
        XCTAssertTrue(try XCTUnwrap(reopened(reopenedDocument).page(at: 0)).annotations.isEmpty)
    }

    func testMarkupFromAnotherApplicationWithoutNameIsFoundByItsRectangle() throws {
        let document = try blankDocument()
        let page = try XCTUnwrap(document.page(at: 0))
        let foreignHighlight = PDFAnnotation(bounds: CGRect(x: 100, y: 500, width: 200, height: 20), forType: .highlight, withProperties: nil)
        page.addAnnotation(foreignHighlight)
        let secondHighlight = PDFAnnotation(bounds: CGRect(x: 100, y: 300, width: 200, height: 20), forType: .highlight, withProperties: nil)
        page.addAnnotation(secondHighlight)
        let reopenedDocument = try reopened(document)
        let reopenedPage = try XCTUnwrap(reopenedDocument.page(at: 0))
        let target = try XCTUnwrap(reopenedPage.markupAnnotation(at: CGPoint(x: 150, y: 310)))
        let reference = PDFAnnotationReference(annotation: target, pageIndex: 0)
        XCTAssertNil(reference.name)
        try PDFPageManager.apply(.removeAnnotation(reference), to: reopenedDocument)
        XCTAssertEqual(reopenedPage.annotations.count, 1)
        XCTAssertEqual(reopenedPage.annotations.first?.bounds.minY ?? 0, 500, accuracy: 0.01)
        XCTAssertThrowsError(try PDFPageManager.apply(.removeAnnotation(reference), to: reopenedDocument), "Removing twice reports a missing annotation.")
    }

    // MARK: Bookmarks

    func testBookmarksAreOutlineEntriesThatCanBeRemoved() throws {
        let document = try blankDocument(pageCount: 3)
        try PDFPageManager.replay([.bookmark(page: 2, label: "Page 3"), .bookmark(page: 0, label: "Page 1")], on: document)
        let reopenedDocument = try reopened(document)
        let root = try XCTUnwrap(reopenedDocument.outlineRoot)
        XCTAssertEqual(root.numberOfChildren, 2)
        XCTAssertEqual(root.child(at: 0)?.label, "Page 3")
        XCTAssertEqual(root.child(at: 0)?.destination?.page.map(reopenedDocument.index(for:)), 2)
        try PDFPageManager.replay([.removeOutlineItem(path: [0])], on: reopenedDocument)
        let afterRemoval = try XCTUnwrap(reopened(reopenedDocument).outlineRoot)
        XCTAssertEqual(afterRemoval.numberOfChildren, 1)
        XCTAssertEqual(afterRemoval.child(at: 0)?.label, "Page 1")
        XCTAssertThrowsError(try PDFPageManager.apply(.removeOutlineItem(path: [5]), to: reopenedDocument))
    }

    func testStructureEntriesLostByPageChangesAreReported() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GraphitePDFStructure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let plainLocation = directory.appendingPathComponent("plain.pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(), pageCount: 2).write(to: plainLocation)
        XCTAssertEqual(PDFStructureInspection.entriesLostByPageChanges(in: plainLocation), [])
        // A catalog with page labels and a page layout, written by hand.
        let labelledLocation = directory.appendingPathComponent("labelled.pdf")
        try Self.minimalPDF(catalogExtras: "/PageLabels << /Nums [0 << /S /r >>] >> /PageLayout /TwoColumnLeft").write(to: labelledLocation)
        XCTAssertNotNil(PDFDocument(url: labelledLocation), "The hand-written PDF is valid.")
        XCTAssertEqual(PDFStructureInspection.entriesLostByPageChanges(in: labelledLocation), ["page numbering labels", "viewer settings"])
    }

    /// A one-page PDF with extra catalog entries and a correct cross-reference table.
    static func minimalPDF(catalogExtras: String) -> Data {
        let objects = ["<< /Type /Catalog /Pages 2 0 R \(catalogExtras) >>",
                       "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                       "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>"]
        var text = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (objectIndex, object) in objects.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(objectIndex + 1) 0 obj\n\(object)\nendobj\n"
        }
        let crossReferenceOffset = text.utf8.count
        text += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { text += String(format: "%010d 00000 n \n", offset) }
        text += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(crossReferenceOffset)\n%%EOF\n"
        return Data(text.utf8)
    }

    // MARK: Saving

    func testSaveCopiesTheWrittenBytesForTheNextBaselineAndDetectsConflicts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GraphitePDFSave-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appendingPathComponent("Notebook.pdf")
        let service = PDFFileService()
        let createdRevision = try await service.create(paper: PaperSpecification(template: .ruled), pageCount: 2, at: location)
        let baseline = directory.appendingPathComponent("baseline.pdf")
        try FileManager.default.copyItem(at: location, to: baseline)

        let nextBaseline = directory.appendingPathComponent("next-baseline.pdf")
        let firstEdits: [PDFEdit] = [.updateInk(PDFInkUpdate(pageIndex: 1, group: "ink", removal: .strokes([]),
                                                             addedStrokes: [stroke(named: "A", from: CGPoint(x: 50, y: 100), to: CGPoint(x: 150, y: 100))],
                                                             editableRecord: PDFEditableInkRecord(drawingData: Data([1]), strokeNames: ["A"])))]
        let savedRevision = try await service.save(url: location, revision: createdRevision, edits: firstEdits, baselineURL: baseline, savedSnapshotDestination: nextBaseline)
        XCTAssertEqual(try FileRevision.read(nextBaseline), savedRevision)
        XCTAssertEqual(try FileRevision.read(location), savedRevision)

        // Only the newer edit is replayed on the new baseline; the earlier stroke remains.
        let secondEdits: [PDFEdit] = [.rotate(page: 0, clockwise: true)]
        let secondRevision = try await service.save(url: location, revision: savedRevision, edits: secondEdits, baselineURL: nextBaseline)
        let saved = try XCTUnwrap(PDFDocument(url: location))
        XCTAssertEqual(saved.page(at: 0)?.rotation, 90)
        XCTAssertEqual(saved.page(at: 1).map(inkNames(on:)), ["A"])

        // An external change is a conflict: the file is kept and no baseline is left behind.
        try Data("changed elsewhere".utf8).write(to: location)
        let abandonedBaseline = directory.appendingPathComponent("abandoned-baseline.pdf")
        do {
            _ = try await service.save(url: location, revision: secondRevision, edits: secondEdits, baselineURL: nextBaseline, savedSnapshotDestination: abandonedBaseline)
            XCTFail("An externally changed file must not be overwritten.")
        } catch {
            XCTAssertEqual(error as? GraphiteError, .conflict)
        }
        XCTAssertEqual(try Data(contentsOf: location), Data("changed elsewhere".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandonedBaseline.path))
    }

    /// PDFKit drops unknown annotation keys it read from the file when a save also
    /// changes the page tree. Stroke data must survive inserting and deleting pages.
    func testSavingPageChangesKeepsEditableInkFromEarlierSaves() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GraphitePDFPages-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appendingPathComponent("Notebook.pdf")
        let service = PDFFileService()
        var revision = try await service.create(paper: PaperSpecification(template: .dotted), pageCount: 3, at: location)
        let inkEdit = PDFEdit.updateInk(PDFInkUpdate(pageIndex: 1, group: PDFInkGroups.defaultGroup, removal: .strokes([]),
                                                     addedStrokes: [stroke(named: "A", from: CGPoint(x: 100, y: 400), to: CGPoint(x: 400, y: 400))],
                                                     editableRecord: PDFEditableInkRecord(drawingData: Data([1]), strokeNames: ["A"])))
        let markupEdit = PDFEdit.addMarkup(page: 1, markup: PDFMarkup(name: "H", kind: .underline, color: .red, lineBounds: [CGRect(x: 100, y: 600, width: 200, height: 20)]))
        revision = try await service.save(url: location, revision: revision, edits: [inkEdit, markupEdit])
        let pageEdits: [PDFEdit] = [.delete(pages: [0]), .insert(data: try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .grid)), at: 2), .move(from: 0, to: 1)]
        for pageEdit in pageEdits {
            revision = try await service.save(url: location, revision: revision, edits: [pageEdit])
        }
        let saved = try XCTUnwrap(PDFDocument(url: location))
        let inkPage = try XCTUnwrap(saved.page(at: 1))
        XCTAssertEqual(PDFInkGroups.editableGroup(on: inkPage)?.record.strokeNames, ["A"])
        XCTAssertEqual(inkPage.annotations.first { annotation in annotation.type == "Underline" }?.persistentName, "H")
        let image = inkPage.thumbnail(of: CGSize(width: 595.28, height: 841.89), for: .cropBox)
        XCTAssertTrue(try InteroperabilityTests.hasDarkPixel(in: image, pdfPoint: CGPoint(x: 250, y: 408), pageHeight: 841.89), "The outlined appearance survives.")
    }

    func testExportedPagesKeepOutlinedInkAndMarkup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GraphitePDFExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let baseline = directory.appendingPathComponent("baseline.pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 3).write(to: baseline)
        let edits: [PDFEdit] = [
            .updateInk(PDFInkUpdate(pageIndex: 1, group: "ink", removal: .strokes([]),
                                    addedStrokes: [stroke(named: "A", from: CGPoint(x: 100, y: 400), to: CGPoint(x: 400, y: 400))], editableRecord: nil)),
            .duplicate(page: 1),
        ]
        let exportedData = try await PDFFileService().export(baselineURL: baseline, edits: edits, pages: [2])
        let exportedPage = try XCTUnwrap(PDFDocument(data: exportedData)?.page(at: 0))
        XCTAssertEqual(inkNames(on: exportedPage), ["A"])
        let image = exportedPage.thumbnail(of: CGSize(width: 595, height: 842), for: .cropBox)
        XCTAssertTrue(try InteroperabilityTests.hasDarkPixel(in: image, pdfPoint: CGPoint(x: 250, y: 408), pageHeight: 842),
                      "A duplicated and exported page keeps the outlined appearance.")
    }

    // MARK: Embed options

    func testObsidianEmbedFragments() {
        XCTAssertEqual(PDFEmbedOptions(fragment: "page=3"), PDFEmbedOptions(startPageNumber: 3))
        XCTAssertEqual(PDFEmbedOptions(fragment: "height=400"), PDFEmbedOptions(height: 400))
        XCTAssertEqual(PDFEmbedOptions(fragment: "page=2&height=300"), PDFEmbedOptions(startPageNumber: 2, height: 300))
        XCTAssertEqual(PDFEmbedOptions(fragment: ""), PDFEmbedOptions())
        XCTAssertEqual(PDFEmbedOptions(fragment: "page=0&height=-4"), PDFEmbedOptions())
        XCTAssertEqual(PDFEmbedOptions(fragment: "page=x&zoom=2"), PDFEmbedOptions())
        XCTAssertEqual(PDFEmbedOptions(fragment: "height=99999").height, PDFEmbedOptions.maximumHeight)
    }

    // MARK: Helpers

    /// Ink as builds before stroke names wrote it: unnamed annotations, and the drawing
    /// on the group's first annotation without the stroke names key.
    static func writeInkWithoutStrokeNames(_ stroke: PortableInkStroke, drawingData: Data, on page: PDFPage) throws {
        let document = try XCTUnwrap(page.document)
        let update = PDFInkUpdate(pageIndex: document.index(for: page), group: PDFInkGroups.defaultGroup, removal: .entireGroup, addedStrokes: [stroke],
                                  editableRecord: PDFEditableInkRecord(drawingData: drawingData, strokeNames: [""]))
        try PDFPageManager.apply(.updateInk(update), to: document)
        let carrier = try XCTUnwrap(page.annotations.first { annotation in annotation.value(forAnnotationKey: PDFPageManager.groupKey) != nil })
        carrier.removeValue(forAnnotationKey: PDFPageManager.strokeNamesKey)
    }

    /// Dictionary references are owned by their CoreGraphics document, which stays alive
    /// for the duration of `body`.
    static func withFirstAnnotationDictionary(in fileData: Data, body: (CGPDFDictionaryRef) throws -> Void) throws {
        let provider = try XCTUnwrap(CGDataProvider(data: fileData as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        let page = try XCTUnwrap(document.page(at: 1))
        var annotations: CGPDFArrayRef?
        var annotationDictionary: CGPDFDictionaryRef?
        guard let pageDictionary = page.dictionary, CGPDFDictionaryGetArray(pageDictionary, "Annots", &annotations), let annotations,
              CGPDFArrayGetDictionary(annotations, 0, &annotationDictionary), let annotationDictionary else {
            XCTFail("The page has no annotation dictionary.")
            return
        }
        try withExtendedLifetime(document) { try body(annotationDictionary) }
    }

    static func normalAppearanceContent(of annotationDictionary: CGPDFDictionaryRef) -> String? {
        var appearance: CGPDFDictionaryRef?
        var normalAppearance: CGPDFStreamRef?
        guard CGPDFDictionaryGetDictionary(annotationDictionary, "AP", &appearance), let appearance,
              CGPDFDictionaryGetStream(appearance, "N", &normalAppearance), let normalAppearance else { return nil }
        var format = CGPDFDataFormat.raw
        guard let content = CGPDFStreamCopyData(normalAppearance, &format) else { return nil }
        return String(decoding: content as Data, as: UTF8.self)
    }

    #if canImport(UIKit)
    static func hasPixel(in image: UIImage, pdfPoint: CGPoint, pageHeight: CGFloat, matching condition: (UInt8, UInt8, UInt8) -> Bool) throws -> Bool {
        try hasPixel(in: XCTUnwrap(image.cgImage), pdfPoint: pdfPoint, pageHeight: pageHeight, matching: condition)
    }
    #else
    static func hasPixel(in image: NSImage, pdfPoint: CGPoint, pageHeight: CGFloat, matching condition: (UInt8, UInt8, UInt8) -> Bool) throws -> Bool {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        return try hasPixel(in: XCTUnwrap(image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)), pdfPoint: pdfPoint, pageHeight: pageHeight, matching: condition)
    }
    #endif

    /// Looks in a 9×9 neighbourhood for a pixel matching `condition` (red, green, blue).
    static func hasPixel(in image: CGImage, pdfPoint: CGPoint, pageHeight: CGFloat, matching condition: (UInt8, UInt8, UInt8) -> Bool) throws -> Bool {
        let width = image.width, height = image.height
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let scale = CGFloat(height) / pageHeight
        let centerColumn = Int(pdfPoint.x * scale), centerRow = Int((pageHeight - pdfPoint.y) * scale)
        for row in max(0, centerRow - 4)...min(height - 1, centerRow + 4) {
            for column in max(0, centerColumn - 4)...min(width - 1, centerColumn + 4) {
                let offset = row * width * 4 + column * 4
                if condition(pixels[offset], pixels[offset + 1], pixels[offset + 2]) { return true }
            }
        }
        return false
    }
}
