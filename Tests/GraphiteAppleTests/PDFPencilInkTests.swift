#if canImport(UIKit)
import XCTest
import PencilKit
import PDFKit
import GraphiteCore
@testable import GraphiteApple

/// Pencil strokes on PDF pages: incremental conversion, re-editing after reopening, and
/// the variable-width appearance other readers show.
final class PDFPencilInkTests: XCTestCase {
    private let pageSize = CGSize(width: 595.28, height: 841.89)

    /// A stroke whose width grows from `startWidth` to `endWidth`, as Pencil pressure does.
    private func stroke(from start: CGPoint, to end: CGPoint, startWidth: CGFloat = 4, endWidth: CGFloat = 4, seconds: TimeInterval = 1) -> PKStroke {
        let controlPoints = (0...30).map { step in
            let fraction = CGFloat(step) / 30
            let width = startWidth + (endWidth - startWidth) * fraction
            return PKStrokePoint(location: CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction),
                                 timeOffset: TimeInterval(fraction), size: CGSize(width: width, height: width), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: controlPoints, creationDate: Date(timeIntervalSince1970: seconds)))
    }

    private func blankDocument() throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank))))
    }

    /// Overlay coordinates equal page points here, so drawings and pages share a scale.
    private func coordinates() throws -> PageCoordinates {
        try PageCoordinates(cropBox: CGRect(origin: .zero, size: pageSize), overlaySize: pageSize)
    }

    private func inkNames(on page: PDFPage) -> [String] {
        page.annotations.filter { annotation in annotation.type == "Ink" }.compactMap(\.persistentName)
    }

    func testOnlyChangedStrokesAreConvertedAndReopenedDrawingsStayIncremental() throws {
        let document = try blankDocument()
        let page = try XCTUnwrap(document.page(at: 0))
        var tracker = PDFPageInkTracker(group: PDFInkGroups.newGroup(on: page))
        let first = stroke(from: CGPoint(x: 50, y: 100), to: CGPoint(x: 300, y: 100), seconds: 1)
        let second = stroke(from: CGPoint(x: 50, y: 200), to: CGPoint(x: 300, y: 200), seconds: 2)

        let initialUpdate = tracker.update(for: PKDrawing(strokes: [first]), pageIndex: 0, coordinates: try coordinates())
        XCTAssertEqual(initialUpdate.addedStrokes.count, 1)
        try PDFPageManager.apply(.updateInk(initialUpdate), to: document)
        let firstName = try XCTUnwrap(inkNames(on: page).first)

        let addition = tracker.update(for: PKDrawing(strokes: [first, second]), pageIndex: 0, coordinates: try coordinates())
        XCTAssertEqual(addition.addedStrokes.count, 1, "An existing stroke is not converted again.")
        XCTAssertEqual(addition.removal, .strokes([]))
        try PDFPageManager.apply(.updateInk(addition), to: document)
        XCTAssertEqual(inkNames(on: page).first, firstName)
        XCTAssertEqual(inkNames(on: page).count, 2)

        let removal = tracker.update(for: PKDrawing(strokes: [second]), pageIndex: 0, coordinates: try coordinates())
        XCTAssertTrue(removal.addedStrokes.isEmpty)
        XCTAssertEqual(removal.removal, .strokes([firstName]))
        try PDFPageManager.apply(.updateInk(removal), to: document)
        XCTAssertEqual(inkNames(on: page).count, 1)

        // Reopen the file: the drawing and its stroke names come back, so the next change
        // is incremental again and nothing is converted twice.
        let reopenedPage = try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation()))?.page(at: 0))
        let editableGroup = try XCTUnwrap(PDFInkGroups.editableGroup(on: reopenedPage))
        var (restoredTracker, restoredDrawing) = try XCTUnwrap(PDFPageInkTracker.restoring(editableGroup))
        XCTAssertEqual(restoredDrawing.strokes.count, 1)
        let unchanged = restoredTracker.update(for: restoredDrawing, pageIndex: 0, coordinates: try coordinates())
        XCTAssertTrue(unchanged.addedStrokes.isEmpty)
        XCTAssertEqual(unchanged.removal, .strokes([]))
        restoredDrawing.strokes.append(stroke(from: CGPoint(x: 50, y: 300), to: CGPoint(x: 300, y: 300), seconds: 3))
        let appended = restoredTracker.update(for: restoredDrawing, pageIndex: 0, coordinates: try coordinates())
        XCTAssertEqual(appended.addedStrokes.count, 1)
    }

    func testMovedStrokeIsReplacedAndErasedStrokeIsRemoved() throws {
        let document = try blankDocument()
        let page = try XCTUnwrap(document.page(at: 0))
        var tracker = PDFPageInkTracker(group: PDFInkGroups.defaultGroup)
        let original = stroke(from: CGPoint(x: 50, y: 100), to: CGPoint(x: 300, y: 100))
        try PDFPageManager.apply(.updateInk(tracker.update(for: PKDrawing(strokes: [original]), pageIndex: 0, coordinates: try coordinates())), to: document)
        let originalName = try XCTUnwrap(inkNames(on: page).first)

        // The lasso moves a stroke by changing its transform.
        var moved = original
        moved.transform = CGAffineTransform(translationX: 0, y: 200)
        let moveUpdate = tracker.update(for: PKDrawing(strokes: [moved]), pageIndex: 0, coordinates: try coordinates())
        XCTAssertEqual(moveUpdate.removal, .strokes([originalName]))
        XCTAssertEqual(moveUpdate.addedStrokes.count, 1)
        try PDFPageManager.apply(.updateInk(moveUpdate), to: document)
        let movedAnnotation = try XCTUnwrap(page.annotations.first { annotation in annotation.type == "Ink" })
        // Overlay y 300 is page y 841.89 − 300.
        XCTAssertEqual(movedAnnotation.bounds.midY, pageSize.height - 300, accuracy: 6)

        let clearUpdate = tracker.update(for: PKDrawing(), pageIndex: 0, coordinates: try coordinates())
        try PDFPageManager.apply(.updateInk(clearUpdate), to: document)
        XCTAssertTrue(inkNames(on: page).isEmpty)
        XCTAssertNil(clearUpdate.editableRecord, "An empty page keeps no stroke data.")
    }

    func testDrawingsWithoutStrokeNamesAreReplacedOnceThenTrackedIncrementally() throws {
        let document = try blankDocument()
        let page = try XCTUnwrap(document.page(at: 0))
        let original = stroke(from: CGPoint(x: 50, y: 100), to: CGPoint(x: 300, y: 100))
        let drawing = PKDrawing(strokes: [original])
        // A file written before stroke names were stored.
        let legacyStroke = PortableInkStroke(name: nil, segments: [[CGPoint(x: 50, y: 741), CGPoint(x: 300, y: 741)]], width: 4, red: 0, green: 0, blue: 0, alpha: 1, outline: nil)
        try PDFAnnotationTests.writeInkWithoutStrokeNames(legacyStroke, drawingData: drawing.dataRepresentation(), on: page)
        let editableGroup = try XCTUnwrap(PDFInkGroups.editableGroup(on: page))
        var (tracker, restoredDrawing) = try XCTUnwrap(PDFPageInkTracker.restoring(editableGroup))
        let firstUpdate = tracker.update(for: restoredDrawing, pageIndex: 0, coordinates: try coordinates())
        XCTAssertEqual(firstUpdate.removal, .entireGroup)
        XCTAssertEqual(firstUpdate.addedStrokes.count, 1)
        try PDFPageManager.apply(.updateInk(firstUpdate), to: document)
        XCTAssertEqual(inkNames(on: page).count, 1, "The unnamed annotation was replaced, not duplicated.")
        restoredDrawing.strokes.append(stroke(from: CGPoint(x: 50, y: 400), to: CGPoint(x: 300, y: 400), seconds: 5))
        let secondUpdate = tracker.update(for: restoredDrawing, pageIndex: 0, coordinates: try coordinates())
        XCTAssertEqual(secondUpdate.removal, .strokes([]))
        XCTAssertEqual(secondUpdate.addedStrokes.count, 1)
    }

    /// A stroke drawn after the others is converted alone; the page's other strokes and
    /// annotations stay as they were, and the next full update still knows every name.
    func testAStrokeAddedAfterTheOthersIsConvertedAloneAndLaterUpdatesKnowItsName() throws {
        let document = try blankDocument()
        let page = try XCTUnwrap(document.page(at: 0))
        var tracker = PDFPageInkTracker(group: PDFInkGroups.newGroup(on: page))
        let strokes = (1...3).map { number in
            stroke(from: CGPoint(x: 50, y: CGFloat(number) * 100), to: CGPoint(x: 300, y: CGFloat(number) * 100), seconds: TimeInterval(number))
        }
        let firstTwo = PKDrawing(strokes: Array(strokes.prefix(2)))
        try PDFPageManager.apply(.updateInk(tracker.update(for: firstTwo, pageIndex: 0, coordinates: try coordinates())), to: document)
        let namesBefore = inkNames(on: page)
        XCTAssertNil(tracker.updateAppending(strokes[2], at: 3, pageIndex: 0, coordinates: try coordinates()),
                     "A stroke not right after the strokes the tracker saw takes the full update.")

        let appending = try XCTUnwrap(tracker.updateAppending(strokes[2], at: 2, pageIndex: 0, coordinates: try coordinates()))
        XCTAssertEqual(appending.removal, .strokes([]))
        XCTAssertEqual(appending.addedStrokes.count, 1)
        XCTAssertTrue(appending.defersEditableRecord)
        try PDFPageManager.apply(.updateInk(appending), to: document)
        XCTAssertEqual(inkNames(on: page), namesBefore + appending.addedStrokes.compactMap(\.name), "Only the new stroke's annotation is added.")
        XCTAssertNotNil(page.annotations.first?.value(forAnnotationKey: PDFPageManager.drawingKey), "The group's first annotation keeps its record.")

        // Erasing the middle stroke compares every stroke and finds the right annotation.
        let erased = PKDrawing(strokes: [strokes[0], strokes[2]])
        let erasing = tracker.update(for: erased, pageIndex: 0, coordinates: try coordinates(), defersEditableRecord: true)
        XCTAssertEqual(erasing.removal, .strokes([namesBefore[1]]))
        XCTAssertTrue(erasing.addedStrokes.isEmpty)
        try PDFPageManager.apply(.updateInk(erasing), to: document)
        let record = try XCTUnwrap(tracker.deferredEditableRecordUpdate(for: erased, pageIndex: 0))
        try PDFPageManager.apply(.updateInk(record), to: document)
        let reopenedPage = try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation()))?.page(at: 0))
        let restored = try XCTUnwrap(PDFPageInkTracker.restoring(XCTUnwrap(PDFInkGroups.editableGroup(on: reopenedPage))))
        XCTAssertEqual(restored.drawing.strokes.map(\.path.creationDate), erased.strokes.map(\.path.creationDate))
        XCTAssertEqual(Set(inkNames(on: reopenedPage)), Set([namesBefore[0]] + appending.addedStrokes.compactMap(\.name)))
    }

    /// A page's ink read back from its file can take a stroke drawn after it at once, without
    /// a first full update.
    func testARestoredPageTakesAStrokeAddedAfterItsOthersAlone() throws {
        let document = try blankDocument()
        let page = try XCTUnwrap(document.page(at: 0))
        var tracker = PDFPageInkTracker(group: PDFInkGroups.newGroup(on: page))
        let written = PKDrawing(strokes: [stroke(from: CGPoint(x: 50, y: 100), to: CGPoint(x: 300, y: 100), seconds: 1)])
        try PDFPageManager.apply(.updateInk(tracker.update(for: written, pageIndex: 0, coordinates: try coordinates())), to: document)
        var (restoredTracker, restoredDrawing) = try XCTUnwrap(PDFPageInkTracker.restoring(XCTUnwrap(PDFInkGroups.editableGroup(on: page))))
        let added = stroke(from: CGPoint(x: 50, y: 200), to: CGPoint(x: 300, y: 200), seconds: 2)
        let appending = try XCTUnwrap(restoredTracker.updateAppending(added, at: restoredDrawing.strokes.count, pageIndex: 0, coordinates: try coordinates()))
        try PDFPageManager.apply(.updateInk(appending), to: document)
        restoredDrawing.strokes.append(added)
        let record = try XCTUnwrap(restoredTracker.deferredEditableRecordUpdate(for: restoredDrawing, pageIndex: 0))
        XCTAssertEqual(record.editableRecord?.strokeNames, inkNames(on: page), "The record names every annotation, in drawing order.")
    }

    /// Other readers draw the saved appearance: a stroke that widens with pressure must be
    /// wide at its heavy end and thin at its light end, not one average width.
    func testSavedInkKeepsPencilWidthVariation() throws {
        let document = try blankDocument()
        var tracker = PDFPageInkTracker(group: PDFInkGroups.defaultGroup)
        let pressureStroke = stroke(from: CGPoint(x: 100, y: 400), to: CGPoint(x: 500, y: 400), startWidth: 1, endWidth: 24)
        let update = tracker.update(for: PKDrawing(strokes: [pressureStroke]), pageIndex: 0, coordinates: try coordinates())
        try PDFPageManager.apply(.updateInk(update), to: document, drawsInkOutlines: true)
        let page = try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation()))?.page(at: 0))
        let image = page.thumbnail(of: pageSize, for: .cropBox)
        let centerLineY = pageSize.height - 400
        // 9 points from the center line: inside the heavy end's ink, outside the light end's.
        XCTAssertTrue(try InteroperabilityTests.hasDarkPixel(in: image, pdfPoint: CGPoint(x: 480, y: centerLineY + 9), pageHeight: pageSize.height))
        XCTAssertFalse(try InteroperabilityTests.hasDarkPixel(in: image, pdfPoint: CGPoint(x: 130, y: centerLineY + 9), pageHeight: pageSize.height))
        XCTAssertTrue(try InteroperabilityTests.hasDarkPixel(in: image, pdfPoint: CGPoint(x: 130, y: centerLineY), pageHeight: pageSize.height))
    }
}
#endif
