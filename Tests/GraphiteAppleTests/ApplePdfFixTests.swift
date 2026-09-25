import XCTest
import PDFKit
import CoreGraphics
import CoreText
#if canImport(UIKit)
import UIKit
import PencilKit
#else
import AppKit
#endif
import GraphiteCore
@testable import GraphiteApple

/// Regression tests for PDF saving: ink on offset pages, outline and link destinations
/// through page changes, other applications' markup, and document structure checks.
final class ApplePdfFixTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ApplePdfFix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Fixtures

    /// A PDF written object by object with a correct cross-reference table.
    static func handWrittenPDF(objects: [String]) -> Data {
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

    /// A three-page PDF as another application writes it: a table of contents whose first
    /// entry uses `/Dest` and second a GoTo action, a link on page 1 to page 3, and a named
    /// orange highlight on page 2 with a note, an author and a popup.
    static func foreignPDF() -> Data {
        handWrittenPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R /Outlines 6 0 R >>",
            "<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Annots [9 0 R] >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Annots [10 0 R 11 0 R] >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] >>",
            "<< /Type /Outlines /First 7 0 R /Last 8 0 R /Count 2 >>",
            "<< /Title (Chapter 1) /Parent 6 0 R /Next 8 0 R /Dest [3 0 R /XYZ 0 300 0] >>",
            "<< /Title (Chapter 2) /Parent 6 0 R /Prev 7 0 R /A << /S /GoTo /D [4 0 R /Fit] >> >>",
            "<< /Type /Annot /Subtype /Link /Rect [10 10 100 40] /Border [0 0 0] /Dest [5 0 R /XYZ 0 300 0] >>",
            "<< /Type /Annot /Subtype /Highlight /Rect [50 100 150 120] /NM (foreign-1) /Contents (my note) /T (Alice) /C [1 0.5 0] "
                + "/QuadPoints [50 120 150 120 50 100 150 100] /Popup 11 0 R >>",
            "<< /Type /Annot /Subtype /Popup /Rect [150 100 250 200] /Parent 10 0 R >>",
        ])
    }

    /// One page whose MediaBox (and so its CropBox) starts at `mediaBoxOrigin`.
    static func offsetPagePDF(mediaBoxOrigin: CGPoint) -> Data {
        let mediaBox = "[\(mediaBoxOrigin.x) \(mediaBoxOrigin.y) \(mediaBoxOrigin.x + 595) \(mediaBoxOrigin.y + 842)]"
        return handWrittenPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox \(mediaBox) >>",
        ])
    }

    private func write(_ fileData: Data, named name: String) throws -> URL {
        let location = directory.appendingPathComponent(name)
        try fileData.write(to: location)
        return location
    }

    /// Saves `edits` the way the PDF session does: replayed on the current baseline, with
    /// the written file becoming the next baseline.
    private func save(_ edits: [PDFEdit], to location: URL, baseline: inout URL) async throws {
        let nextBaseline = directory.appendingPathComponent("baseline-\(UUID().uuidString).pdf")
        _ = try await PDFFileService().save(url: location, revision: FileRevision.read(location), edits: edits,
                                            baselineURL: baseline, savedSnapshotDestination: nextBaseline)
        baseline = nextBaseline
    }

    private func outlineSummary(_ document: PDFDocument) -> [String] {
        guard let root = document.outlineRoot else { return [] }
        return (0..<root.numberOfChildren).compactMap { childIndex in
            guard let child = root.child(at: childIndex) else { return nil }
            let pageIndex = child.destination?.page.map(document.index(for:)) ?? -1
            return "\(child.label ?? "")->\(pageIndex)"
        }
    }

    /// Each link as "page of the link->page it opens", -1 when it opens nothing.
    private func linkSummary(_ document: PDFDocument) -> [String] {
        (0..<document.pageCount).flatMap { pageIndex in
            (document.page(at: pageIndex)?.annotations ?? []).filter { annotation in annotation.type == "Link" }.map { link in
                let destination = link.destination ?? (link.action as? PDFActionGoTo)?.destination
                return "\(pageIndex)->\(destination?.page.map(document.index(for:)) ?? -1)"
            }
        }
    }

    private func stroke(from start: CGPoint, to end: CGPoint, name: String = UUID().uuidString) -> PortableInkStroke {
        let outline = [[CGPoint(x: start.x, y: start.y - 10), CGPoint(x: end.x, y: end.y - 10),
                        CGPoint(x: end.x, y: end.y + 10), CGPoint(x: start.x, y: start.y + 10)]]
        return PortableInkStroke(name: name, segments: [[start, end]], width: 1, red: 0, green: 0, blue: 0, alpha: 1, outline: outline)
    }

    // MARK: Ink on pages whose MediaBox is offset

    func testSavedInkIsVisibleOnPagesWhoseMediaBoxDoesNotStartAtZero() async throws {
        for mediaBoxOrigin in [CGPoint.zero, CGPoint(x: 50, y: 60), CGPoint(x: -297, y: -421)] {
            let location = try write(Self.offsetPagePDF(mediaBoxOrigin: mediaBoxOrigin), named: "offset-\(UUID().uuidString).pdf")
            var baseline = try write(Data(contentsOf: location), named: "offset-baseline-\(UUID().uuidString).pdf")
            // Page space includes the origin, as the Pencil canvas converts it.
            let start = CGPoint(x: mediaBoxOrigin.x + 100, y: mediaBoxOrigin.y + 400), end = CGPoint(x: mediaBoxOrigin.x + 400, y: mediaBoxOrigin.y + 400)
            let update = PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes([]), addedStrokes: [stroke(from: start, to: end)], editableRecord: nil)
            try await save([.updateInk(update)], to: location, baseline: &baseline)

            let page = try XCTUnwrap(PDFDocument(url: location)?.page(at: 0))
            let image = page.thumbnail(of: CGSize(width: 595, height: 842), for: .cropBox)
            // The outline is 10 points taller than the 1-point center line on each side.
            XCTAssertTrue(try InteroperabilityTests.hasDarkPixel(in: image, pdfPoint: CGPoint(x: 250, y: 407), pageHeight: 842),
                          "The saved appearance shows the ink for MediaBox origin \(mediaBoxOrigin).")
            XCTAssertFalse(try InteroperabilityTests.hasDarkPixel(in: image, pdfPoint: CGPoint(x: 250, y: 430), pageHeight: 842))
        }
    }

    // MARK: Outline and link destinations through page changes

    func testMovingABookmarkedPageKeepsItsBookmarksOnThatPage() async throws {
        let location = try write(PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 3), named: "Notebook.pdf")
        var baseline = try write(Data(contentsOf: location), named: "baseline.pdf")
        try await save([.bookmark(page: 0, label: "A"), .bookmark(page: 2, label: "C")], to: location, baseline: &baseline)
        // The next save starts from a fresh baseline whose outline nothing has read.
        try await save([.move(from: 0, to: 2)], to: location, baseline: &baseline)
        XCTAssertEqual(outlineSummary(try XCTUnwrap(PDFDocument(url: location))), ["A->2", "C->1"])
    }

    func testMovingAPageKeepsAnotherApplicationsTableOfContentsAndLinks() async throws {
        let location = try write(Self.foreignPDF(), named: "Textbook.pdf")
        var baseline = try write(Self.foreignPDF(), named: "baseline.pdf")
        try await save([.move(from: 0, to: 2)], to: location, baseline: &baseline)
        let saved = try XCTUnwrap(PDFDocument(url: location))
        XCTAssertEqual(outlineSummary(saved), ["Chapter 1->2", "Chapter 2->0"])
        XCTAssertEqual(linkSummary(saved), ["2->1"], "The link moved with its page and still opens the old page 3.")

        // The displayed document, where the edit applies directly, agrees with the file.
        let displayed = try XCTUnwrap(PDFDocument(data: Self.foreignPDF()))
        try PDFPageManager.apply(.move(from: 0, to: 2), to: displayed)
        XCTAssertEqual(outlineSummary(displayed), ["Chapter 1->2", "Chapter 2->0"])
    }

    func testDeletingABookmarkedPageRemovesItsBookmark() async throws {
        let location = try write(PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 3), named: "Notebook.pdf")
        var baseline = try write(Data(contentsOf: location), named: "baseline.pdf")
        try await save([.bookmark(page: 0, label: "A"), .bookmark(page: 2, label: "C")], to: location, baseline: &baseline)
        let displayed = try XCTUnwrap(PDFDocument(url: baseline))
        try await save([.delete(pages: [0])], to: location, baseline: &baseline)
        XCTAssertEqual(outlineSummary(try XCTUnwrap(PDFDocument(url: location))), ["C->1"])
        // The displayed document keeps the same outline, so outline paths still agree.
        try PDFPageManager.apply(.delete(pages: [0]), to: displayed)
        XCTAssertEqual(outlineSummary(displayed), ["C->1"])
    }

    func testDeletingAPageKeepsOutlineChildrenAndClearsLinksToIt() async throws {
        let nestedOutlinePDF = Self.handWrittenPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R /Outlines 6 0 R >>",
            "<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Annots [9 0 R] >>",
            "<< /Type /Outlines /First 7 0 R /Last 7 0 R /Count 2 >>",
            "<< /Title (Part) /Parent 6 0 R /First 8 0 R /Last 8 0 R /Count 1 /Dest [3 0 R /Fit] >>",
            "<< /Title (Section) /Parent 7 0 R /Dest [4 0 R /Fit] >>",
            "<< /Type /Annot /Subtype /Link /Rect [10 10 100 40] /Border [0 0 0] /Dest [3 0 R /Fit] >>",
        ])
        let location = try write(nestedOutlinePDF, named: "Nested.pdf")
        var baseline = try write(nestedOutlinePDF, named: "baseline.pdf")
        try await save([.delete(pages: [0])], to: location, baseline: &baseline)
        let saved = try XCTUnwrap(PDFDocument(url: location))
        let part = try XCTUnwrap(saved.outlineRoot?.child(at: 0))
        XCTAssertEqual(part.label, "Part")
        XCTAssertNil(part.destination?.page, "The entry of the deleted page no longer opens another page.")
        XCTAssertEqual(part.child(at: 0)?.destination?.page.map(saved.index(for:)), 0, "Its child keeps its own page.")
        XCTAssertEqual(linkSummary(saved), ["1->-1"], "A link to the deleted page opens nothing rather than page 1.")
    }

    func testSavedOutlineMatchesTheDisplayedOutlineAfterDeletingAPageAndRemovingEntries() async throws {
        let nestedOutlinePDF = Self.handWrittenPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R /Outlines 6 0 R >>",
            "<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] >>",
            "<< /Type /Outlines /First 7 0 R /Last 9 0 R /Count 3 >>",
            "<< /Title (Part) /Parent 6 0 R /Next 9 0 R /First 8 0 R /Last 8 0 R /Count 1 /Dest [3 0 R /Fit] >>",
            "<< /Title (Section) /Parent 7 0 R /Dest [4 0 R /Fit] >>",
            "<< /Title (Other) /Parent 6 0 R /Prev 7 0 R /Dest [5 0 R /Fit] >>",
        ])
        let location = try write(nestedOutlinePDF, named: "Nested.pdf")
        var baseline = try write(nestedOutlinePDF, named: "baseline.pdf")
        let displayed = try XCTUnwrap(PDFDocument(data: nestedOutlinePDF))
        // The part's page goes first, then its only section, in one save.
        let edits: [PDFEdit] = [.delete(pages: [0]), .removeOutlineItem(path: [0, 0])]
        for edit in edits { try PDFPageManager.apply(edit, to: displayed) }
        try await save(edits, to: location, baseline: &baseline)
        XCTAssertEqual(outlineSummary(displayed), ["Part->-1", "Other->1"])
        XCTAssertEqual(outlineSummary(try XCTUnwrap(PDFDocument(url: location))), outlineSummary(displayed),
                       "Outline paths recorded against the displayed outline name the same entries in the file.")

        // A later removal by path therefore removes the same entry in both.
        try PDFPageManager.apply(.removeOutlineItem(path: [1]), to: displayed)
        try await save([.removeOutlineItem(path: [1])], to: location, baseline: &baseline)
        XCTAssertEqual(outlineSummary(try XCTUnwrap(PDFDocument(url: location))), ["Part->-1"])
        XCTAssertEqual(outlineSummary(displayed), ["Part->-1"])
    }

    func testExportedPagesKeepOnlyOutlineEntriesAndLinksForExportedPages() throws {
        let document = try XCTUnwrap(PDFDocument(data: Self.foreignPDF()))
        let exported = try XCTUnwrap(PDFDocument(data: PDFPageManager.export(pages: [0, 1], from: document)))
        XCTAssertEqual(exported.pageCount, 2)
        XCTAssertEqual(outlineSummary(exported), ["Chapter 1->0", "Chapter 2->1"])
        XCTAssertEqual(linkSummary(exported), ["0->-1"], "The link to the page left out opens nothing.")

        let lastPageOnly = try XCTUnwrap(PDFDocument(data: PDFPageManager.export(pages: [2], from: XCTUnwrap(PDFDocument(data: Self.foreignPDF())))))
        XCTAssertEqual(outlineSummary(lastPageOnly), [], "Chapters on pages left out are not listed.")
    }

    // MARK: Another application's markup

    func testRemovingNamedForeignMarkupAfterAPageTreeSaveStillSaves() async throws {
        for firstEdit in [PDFEdit.bookmark(page: 0, label: "Page 1"), .move(from: 2, to: 0)] {
            let location = try write(Self.foreignPDF(), named: "Foreign-\(UUID().uuidString).pdf")
            var baseline = try write(Self.foreignPDF(), named: "baseline-\(UUID().uuidString).pdf")
            let displayed = try XCTUnwrap(PDFDocument(url: baseline))
            try PDFPageManager.apply(firstEdit, to: displayed)
            try await save([firstEdit], to: location, baseline: &baseline)
            let rewritten = try XCTUnwrap(PDFDocument(url: baseline))
            let rewrittenNames = (0..<rewritten.pageCount).flatMap { pageIndex in
                rewritten.page(at: pageIndex)?.annotations.filter { annotation in annotation.type == "Highlight" }.map(\.persistentName) ?? []
            }
            XCTAssertEqual(rewrittenNames, ["foreign-1"], "The rewritten file keeps the highlight's name.")

            let highlightPageIndex = try XCTUnwrap((0..<displayed.pageCount).first { pageIndex in
                displayed.page(at: pageIndex)?.annotations.contains { annotation in annotation.type == "Highlight" } == true
            })
            let highlight = try XCTUnwrap(displayed.page(at: highlightPageIndex)?.annotations.first { annotation in annotation.type == "Highlight" })
            let reference = PDFAnnotationReference(annotation: highlight, pageIndex: highlightPageIndex)
            XCTAssertEqual(reference.name, "foreign-1")
            let edits: [PDFEdit] = [.recolorMarkup(reference, color: .green), .removeAnnotation(reference), .bookmark(page: 0, label: "Later")]
            _ = try await PDFFileService().saveCopy(baselineURL: baseline, edits: edits, destination: directory.appendingPathComponent("Copy-\(UUID().uuidString).pdf"))
            try await save(edits, to: location, baseline: &baseline)
            let saved = try XCTUnwrap(PDFDocument(url: location))
            let remainingTypes = (0..<saved.pageCount).flatMap { pageIndex in saved.page(at: pageIndex)?.annotations.compactMap(\.type) ?? [] }
            XCTAssertFalse(remainingTypes.contains("Highlight"))
        }
    }

    func testNamedReferenceFindsMarkupWhoseNameAnEarlierBuildLost() throws {
        // A file an earlier build wrote while changing pages: the highlight has no name.
        let document = try XCTUnwrap(PDFDocument(data: Self.foreignPDF()))
        let page = try XCTUnwrap(document.page(at: 1))
        let highlight = try XCTUnwrap(page.annotations.first { annotation in annotation.type == "Highlight" })
        let reference = PDFAnnotationReference(annotation: highlight, pageIndex: 1)
        highlight.removeValue(forAnnotationKey: .name)
        XCTAssertNil(highlight.persistentName)
        try PDFPageManager.apply(.removeAnnotation(reference), to: document)
        XCTAssertFalse(page.annotations.contains { annotation in annotation.type == "Highlight" })
        // A named annotation with another name is never taken for it.
        let other = PDFMarkup(name: "other", kind: .highlight, color: .yellow, lineBounds: [CGRect(x: 50, y: 100, width: 100, height: 20)])
        try PDFPageManager.apply(.addMarkup(page: 1, markup: other), to: document)
        XCTAssertThrowsError(try PDFPageManager.apply(.removeAnnotation(reference), to: document))
    }

    func testRemovedMarkupPopupIsNotWrittenWithoutItsParent() throws {
        let document = try XCTUnwrap(PDFDocument(data: Self.foreignPDF()))
        let highlight = try XCTUnwrap(document.page(at: 1)?.annotations.first { annotation in annotation.type == "Highlight" })
        try PDFPageManager.apply(.removeAnnotation(PDFAnnotationReference(annotation: highlight, pageIndex: 1)), to: document)
        let written = try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation())))
        XCTAssertEqual(written.page(at: 1)?.annotations.map(\.type), [])
    }

    func testRestoredForeignMarkupKeepsItsNoteAuthorAndExactColor() throws {
        let document = try XCTUnwrap(PDFDocument(data: Self.foreignPDF()))
        let page = try XCTUnwrap(document.page(at: 1))
        let highlight = try XCTUnwrap(page.annotations.first { annotation in annotation.type == "Highlight" })
        let reference = PDFAnnotationReference(annotation: highlight, pageIndex: 1)
        let snapshot = try XCTUnwrap(PDFMarkup(annotation: highlight))
        XCTAssertEqual(snapshot.originalDetails, PDFMarkupDetails(red: 1, green: 0.5, blue: 0, alpha: 1, note: "my note", author: "Alice"))

        // Remove, then undo by adding the snapshot back.
        try PDFPageManager.apply(.removeAnnotation(reference), to: document)
        try PDFPageManager.apply(.addMarkup(page: 1, markup: snapshot), to: document)
        let written = try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation())))
        let restored = try XCTUnwrap(written.page(at: 1)?.annotations.first { annotation in annotation.type == "Highlight" })
        XCTAssertEqual(restored.contents, "my note")
        XCTAssertEqual(restored.userName, "Alice")
        XCTAssertEqual(PDFMarkup(annotation: restored)?.originalDetails, snapshot.originalDetails)
        XCTAssertEqual(restored.persistentName, "foreign-1")

        // Recolor, then undo by restoring the snapshot's color.
        let restoredReference = PDFAnnotationReference(annotation: restored, pageIndex: 1)
        try PDFPageManager.apply(.recolorMarkup(restoredReference, color: .blue), to: written)
        try PDFPageManager.apply(.restoreMarkupColor(restoredReference, from: snapshot), to: written)
        let recolored = try XCTUnwrap(PDFDocument(data: XCTUnwrap(written.dataRepresentation()))?.page(at: 1)?.annotations.first { annotation in annotation.type == "Highlight" })
        XCTAssertEqual(PDFMarkup(annotation: recolored)?.originalDetails?.green ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(PDFMarkup(annotation: recolored)?.originalDetails?.blue ?? 1, 0, accuracy: 0.001)

        // Markup Graphite creates keeps its palette color.
        let created = PDFMarkup(name: "new", kind: .underline, color: .red, lineBounds: [CGRect(x: 10, y: 10, width: 50, height: 10)])
        XCTAssertNil(created.originalDetails)
    }

    func testTapOnUnmarkedTextInsideAMultiLineHighlightFindsNothing() throws {
        let document = try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank))))
        let page = try XCTUnwrap(document.page(at: 0))
        let markup = PDFMarkup(kind: .highlight, color: .yellow, lineBounds: [CGRect(x: 400, y: 700, width: 100, height: 20), CGRect(x: 60, y: 670, width: 60, height: 20)])
        try PDFPageManager.apply(.addMarkup(page: 0, markup: markup), to: document)
        XCTAssertNil(page.markupAnnotation(at: CGPoint(x: 450, y: 680)), "Unmarked text between the two lines.")
        XCTAssertNotNil(page.markupAnnotation(at: CGPoint(x: 450, y: 710)))
        XCTAssertNotNil(page.markupAnnotation(at: CGPoint(x: 90, y: 680)))
        XCTAssertNotNil(page.markupAnnotation(at: CGPoint(x: 121, y: 680)), "The edge tolerance still applies.")
    }

    /// One page with "Rotated lecture text" drawn turned by `angle` around (300, 400).
    private func rotatedTextDocument(angle: CGFloat) throws -> PDFDocument {
        let output = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        let consumer = try XCTUnwrap(CGDataConsumer(data: output))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        let attributedText = NSAttributedString(string: "Rotated lecture text", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        context.translateBy(x: 300, y: 400)
        context.rotate(by: angle)
        context.textPosition = .zero
        CTLineDraw(CTLineCreateWithAttributedString(attributedText), context)
        context.endPDFPage()
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: output as Data))
    }

    func testUnderlineOnTurnedTextRunsAlongTheText() throws {
        // Angle, expected direction, a point on the side the underline must be drawn on,
        // and a point where an underline drawn across the text would be.
        let cases: [(angle: CGFloat, direction: PDFMarkupLineDirection, underlinedSide: (CGRect) -> CGPoint, wrongSide: (CGRect) -> CGPoint)] = [
            (0, .leftToRight, { rectangle in CGPoint(x: rectangle.midX, y: rectangle.minY) }, { rectangle in CGPoint(x: rectangle.midX, y: rectangle.maxY) }),
            (.pi / 2, .bottomToTop, { rectangle in CGPoint(x: rectangle.maxX, y: rectangle.midY) }, { rectangle in CGPoint(x: rectangle.midX, y: rectangle.minY) }),
            (-.pi / 2, .topToBottom, { rectangle in CGPoint(x: rectangle.minX, y: rectangle.midY) }, { rectangle in CGPoint(x: rectangle.midX, y: rectangle.minY) }),
        ]
        // Anti-aliasing blends the thin red line with the white page.
        let isReddish: (UInt8, UInt8, UInt8) -> Bool = { red, green, _ in Int(red) > Int(green) + 40 }
        for testCase in cases {
            let document = try rotatedTextDocument(angle: testCase.angle)
            let page = try XCTUnwrap(document.page(at: 0))
            let lineRectangle = try XCTUnwrap(document.findString("lecture", withOptions: []).first?.markupLinesByPage(in: document).first?.lineBounds.first)
            XCTAssertEqual(page.markupLineDirection(of: lineRectangle), testCase.direction)
            let markup = PDFMarkup(name: "underline", kind: .underline, color: .red, lineBounds: [lineRectangle])
            try PDFPageManager.apply(.addMarkup(page: 0, markup: markup), to: document)
            let writtenPage = try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation()))?.page(at: 0))
            let image = writtenPage.thumbnail(of: CGSize(width: 595, height: 842), for: .cropBox)
            XCTAssertTrue(try PDFAnnotationTests.hasPixel(in: image, pdfPoint: testCase.underlinedSide(lineRectangle), pageHeight: 842, matching: isReddish),
                          "The underline runs along the text turned by \(testCase.angle).")
            XCTAssertFalse(try PDFAnnotationTests.hasPixel(in: image, pdfPoint: testCase.wrongSide(lineRectangle), pageHeight: 842, matching: isReddish),
                           "No underline across the text turned by \(testCase.angle).")
            // The line rectangle read back is the same, so an undo writes the same markup.
            let restoredLine = try XCTUnwrap(writtenPage.annotations.first.flatMap(PDFMarkup.init(annotation:))?.lineBounds.first)
            XCTAssertEqual(restoredLine.width, lineRectangle.width, accuracy: 0.5)
            XCTAssertEqual(restoredLine.height, lineRectangle.height, accuracy: 0.5)
        }
    }

    // MARK: Document structure

    func testSignedPDFIsDetectedAndReportedBeforePageChanges() throws {
        let signature = "<< /Type /Sig /Filter /Adobe.PPKLite /SubFilter /adbe.pkcs7.detached /ByteRange [0 10 20 30] /Contents <00> >>"
        let signedFields = Self.handWrittenPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [4 0 R] >> >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>",
            "<< /T (Parent) /Kids [5 0 R] >>",
            "<< /FT /Sig /T (Signature1) /Parent 4 0 R /V \(signature) >>",
        ])
        let signedLocation = try write(signedFields, named: "signed.pdf")
        XCTAssertNotNil(PDFDocument(url: signedLocation), "The hand-written PDF is valid.")
        XCTAssertTrue(PDFStructureInspection.hasDigitalSignature(in: signedLocation))
        XCTAssertEqual(PDFStructureInspection.entriesLostByPageChanges(in: signedLocation), ["digital signatures", "form fields"])

        let flaggedLocation = try write(PDFAnnotationTests.minimalPDF(catalogExtras: "/AcroForm << /Fields [] /SigFlags 3 >>"), named: "flagged.pdf")
        XCTAssertTrue(PDFStructureInspection.hasDigitalSignature(in: flaggedLocation))

        let unsignedField = try write(PDFAnnotationTests.minimalPDF(catalogExtras: "/AcroForm << /Fields [<< /FT /Sig /T (Empty) >>] >>"), named: "unsigned.pdf")
        XCTAssertFalse(PDFStructureInspection.hasDigitalSignature(in: unsignedField), "An empty signature field is not a signature.")
        let plainLocation = try write(PDFTemplateGenerator.documentData(paper: PaperSpecification(), pageCount: 1), named: "plain.pdf")
        XCTAssertFalse(PDFStructureInspection.hasDigitalSignature(in: plainLocation))
    }

    func testDeclaredVersionIsReportedAsLostByPageChanges() throws {
        let location = try write(PDFAnnotationTests.minimalPDF(catalogExtras: "/Version /1.7"), named: "versioned.pdf")
        XCTAssertEqual(PDFStructureInspection.entriesLostByPageChanges(in: location), ["the declared PDF version"])
    }

    // MARK: Deferred re-editing records

    private func inkRecord(on page: PDFPage, group: String) -> (drawing: String?, strokeNames: String?, carrierName: String?) {
        let groupAnnotations = page.annotations.filter { annotation in annotation.value(forAnnotationKey: PDFPageManager.groupKey) as? String == group }
        let carriers = groupAnnotations.filter { annotation in annotation.value(forAnnotationKey: PDFPageManager.drawingKey) != nil }
        XCTAssertLessThanOrEqual(carriers.count, 1, "At most one annotation carries the record.")
        return (carriers.first?.value(forAnnotationKey: PDFPageManager.drawingKey) as? String,
                carriers.first?.value(forAnnotationKey: PDFPageManager.strokeNamesKey) as? String, carriers.first?.persistentName)
    }

    func testDeferredRecordStaysWithTheGroupAndMergesLikeSequentialUpdates() throws {
        let group = PDFInkGroups.defaultGroup
        let first = PDFInkUpdate(pageIndex: 0, group: group, removal: .strokes([]),
                                 addedStrokes: [stroke(from: CGPoint(x: 50, y: 100), to: CGPoint(x: 150, y: 100), name: "A"),
                                                stroke(from: CGPoint(x: 50, y: 200), to: CGPoint(x: 150, y: 200), name: "B")],
                                 editableRecord: PDFEditableInkRecord(drawingData: Data([1]), strokeNames: ["A", "B"]))
        // Erasing the carrier while deferring the record moves the old record to "B".
        let deferredRemoval = PDFInkUpdate(pageIndex: 0, group: group, removal: .strokes(["A"]),
                                           addedStrokes: [stroke(from: CGPoint(x: 50, y: 300), to: CGPoint(x: 150, y: 300), name: "C")],
                                           editableRecord: nil, defersEditableRecord: true)
        let writtenRecord = PDFInkUpdate(pageIndex: 0, group: group, removal: .strokes([]), addedStrokes: [],
                                         editableRecord: PDFEditableInkRecord(drawingData: Data([2]), strokeNames: ["B", "C"]))

        let sequential = try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank))))
        let sequentialPage = try XCTUnwrap(sequential.page(at: 0))
        try PDFPageManager.apply(.updateInk(first), to: sequential)
        try PDFPageManager.apply(.updateInk(deferredRemoval), to: sequential)
        let keptRecord = inkRecord(on: sequentialPage, group: group)
        XCTAssertEqual(keptRecord.carrierName, "B")
        XCTAssertEqual(keptRecord.drawing, Data([1]).base64EncodedString(), "The earlier record is kept, not removed.")
        XCTAssertNil(PDFInkGroups.editableGroup(on: sequentialPage), "Until the record is written, its names do not match the ink.")
        try PDFPageManager.apply(.updateInk(writtenRecord), to: sequential)
        XCTAssertEqual(PDFInkGroups.editableGroup(on: sequentialPage)?.record, PDFEditableInkRecord(drawingData: Data([2]), strokeNames: ["B", "C"]))

        let merged = try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank))))
        let mergedUpdate = try XCTUnwrap(first.merged(with: deferredRemoval)?.merged(with: writtenRecord))
        XCTAssertFalse(mergedUpdate.defersEditableRecord)
        try PDFPageManager.apply(.updateInk(mergedUpdate), to: merged)
        XCTAssertEqual(PDFInkGroups.editableGroup(on: try XCTUnwrap(merged.page(at: 0))), PDFInkGroups.editableGroup(on: sequentialPage))

        // A deferred update after a written record keeps that record through a merge.
        let keptThroughMerge = try XCTUnwrap(first.merged(with: deferredRemoval))
        XCTAssertEqual(keptThroughMerge.editableRecord, first.editableRecord)
        XCTAssertFalse(keptThroughMerge.defersEditableRecord)
        let replacedGroup = PDFInkUpdate(pageIndex: 0, group: group, removal: .entireGroup, addedStrokes: [], editableRecord: nil, defersEditableRecord: true)
        XCTAssertEqual(first.merged(with: replacedGroup)?.editableRecord, first.editableRecord)
    }

    #if canImport(UIKit)
    // MARK: Pencil strokes (iOS)

    private func pencilStroke(mask: UIBezierPath?) -> PKStroke {
        let controlPoints = (0...30).map { step in
            PKStrokePoint(location: CGPoint(x: 50 + CGFloat(step) * 10, y: 100), timeOffset: TimeInterval(step) / 30, size: CGSize(width: 4, height: 4),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: controlPoints, creationDate: Date(timeIntervalSince1970: 1))
        return PKStroke(ink: PKInk(.pen, color: .black), path: path, transform: .identity, mask: mask)
    }

    /// The visible parts of the line, which spans x 48...352: the mask keeps these gaps out.
    private func mask(keepingOutGaps gaps: [ClosedRange<CGFloat>]) -> UIBezierPath {
        var visibleStart: CGFloat = 40
        let mask = UIBezierPath()
        for gap in gaps {
            mask.append(UIBezierPath(rect: CGRect(x: visibleStart, y: 90, width: gap.lowerBound - visibleStart, height: 20)))
            visibleStart = gap.upperBound
        }
        mask.append(UIBezierPath(rect: CGRect(x: visibleStart, y: 90, width: 360 - visibleStart, height: 20)))
        return mask
    }

    func testSecondEraserCutInsideAStrokeIsConvertedAgain() throws {
        let oneCut = pencilStroke(mask: mask(keepingOutGaps: [180...200]))
        let twoCuts = pencilStroke(mask: mask(keepingOutGaps: [120...140, 180...200]))
        XCTAssertEqual(oneCut.mask?.bounds, twoCuts.mask?.bounds, "The mask bounds alone cannot tell the cuts apart.")
        XCTAssertNotEqual(PDFStrokeFingerprint(stroke: oneCut), PDFStrokeFingerprint(stroke: twoCuts))

        let pageSize = CGSize(width: 595.28, height: 841.89)
        let coordinates = try PageCoordinates(cropBox: CGRect(origin: .zero, size: pageSize), overlaySize: pageSize)
        var tracker = PDFPageInkTracker(group: PDFInkGroups.defaultGroup)
        let firstUpdate = tracker.update(for: PKDrawing(strokes: [oneCut]), pageIndex: 0, coordinates: coordinates)
        let secondUpdate = tracker.update(for: PKDrawing(strokes: [twoCuts]), pageIndex: 0, coordinates: coordinates)
        XCTAssertEqual(secondUpdate.addedStrokes.count, 1, "The stroke with the second cut is converted again.")
        XCTAssertEqual(secondUpdate.removal, .strokes(Set(firstUpdate.addedStrokes.compactMap(\.name))))
    }

    func testDeferredRecordIsWrittenOnceByTheTracker() throws {
        let pageSize = CGSize(width: 595.28, height: 841.89)
        let coordinates = try PageCoordinates(cropBox: CGRect(origin: .zero, size: pageSize), overlaySize: pageSize)
        let document = try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank))))
        let page = try XCTUnwrap(document.page(at: 0))
        var tracker = PDFPageInkTracker(group: PDFInkGroups.defaultGroup)
        let drawing = PKDrawing(strokes: [pencilStroke(mask: nil)])
        let deferredUpdate = tracker.update(for: drawing, pageIndex: 0, coordinates: coordinates, defersEditableRecord: true)
        XCTAssertTrue(deferredUpdate.defersEditableRecord)
        XCTAssertNil(deferredUpdate.editableRecord)
        try PDFPageManager.apply(.updateInk(deferredUpdate), to: document)
        let recordUpdate = try XCTUnwrap(tracker.deferredEditableRecordUpdate(for: drawing, pageIndex: 0))
        XCTAssertNil(tracker.deferredEditableRecordUpdate(for: drawing, pageIndex: 0), "The record is written once.")
        try PDFPageManager.apply(.updateInk(recordUpdate), to: document)
        let editableGroup = try XCTUnwrap(PDFInkGroups.editableGroup(on: page))
        XCTAssertEqual(editableGroup.record.strokeNames, deferredUpdate.addedStrokes.compactMap(\.name))
        XCTAssertNotNil(PDFPageInkTracker.restoring(editableGroup))
    }
    #endif
}
