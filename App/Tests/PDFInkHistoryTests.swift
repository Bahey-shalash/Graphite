#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import PDFKit
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

/// Pencil ink in a PDF's own undo history: it survives page canvases being released and
/// the view being rebuilt, and never mixes two PDFs.
@MainActor
final class PDFInkHistoryTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var locations: [URL] = []

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        for location in locations { try? FileManager.default.removeItem(at: location) }
        locations = []
    }

    func testInkUndoAndRedoWorkAfterThePageCanvasWasReleased() async throws {
        let session = try await openNotebook(pageCount: 20)
        let controller = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let firstPage = try XCTUnwrap(session.document.page(at: 0))
        let canvas = try await editingCanvas(for: firstPage, in: session)
        canvas.drawing = PKDrawing(strokes: [stroke(atHeight: 100)])
        try await waitUntil { self.inkCount(on: firstPage) == 1 }
        try await waitUntil { session.undoAvailability.canUndo }

        // Scrolling far enough releases the first page's canvas.
        for pageIndex in 1..<session.pageCount {
            session.go(to: pageIndex)
            try await Task.sleep(for: .milliseconds(60))
        }
        let coordinator = try XCTUnwrap((session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator)
        try await waitUntil { coordinator.editingCanvas(for: firstPage) == nil }

        session.undoAvailability.undo()
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(inkCount(on: firstPage), 0, "Undo reaches a page whose canvas is gone.")
        XCTAssertEqual(session.currentPageIndex, 0, "Undo shows the page it changed.")
        XCTAssertTrue(session.undoAvailability.canRedo)

        session.undoAvailability.redo()
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(inkCount(on: firstPage), 1)
        // A canvas made for the page again restores the redone stroke from the page.
        let restoredCanvas = try await editingCanvas(for: firstPage, in: session)
        XCTAssertEqual(restoredCanvas.drawing.strokes.count, 1)
        attachScreenshot(of: controller, named: "Ink redone on a page whose canvas was released")

        try await session.save()
        let saved = try XCTUnwrap(PDFDocument(url: session.location))
        XCTAssertEqual(saved.page(at: 0)?.annotations.filter { annotation in annotation.type == "Ink" }.count, 1)
    }

    func testInkUndoSurvivesRebuildingThePDFView() async throws {
        let session = try await openNotebook(pageCount: 2)
        let controller = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let firstPage = try XCTUnwrap(session.document.page(at: 0))
        let canvas = try await editingCanvas(for: firstPage, in: session)
        canvas.drawing = PKDrawing(strokes: [stroke(atHeight: 100)])
        try await waitUntil { self.inkCount(on: firstPage) == 1 }
        endEvent(of: session)
        canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes + [stroke(atHeight: 200)])
        try await waitUntil { self.inkCount(on: firstPage) == 2 }
        endEvent(of: session)

        // Another tab replaces the PDF on screen, then the PDF's tab comes back.
        controller.rootView = AnyView(Text("Another tab"))
        try await waitUntil { self.descendants(of: controller.view, matching: PDFPageCanvasView.self).isEmpty }
        controller.rootView = AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        let newCanvas = try await editingCanvas(for: firstPage, in: session)
        XCTAssertFalse(newCanvas === canvas)
        XCTAssertEqual(newCanvas.drawing.strokes.count, 2)

        session.undoAvailability.undo()
        XCTAssertNil(session.errorMessage)
        try await waitUntil { self.inkCount(on: firstPage) == 1 }
        XCTAssertEqual(newCanvas.drawing.strokes.count, 1, "The rebuilt view's canvas shows the undone drawing.")
        session.undoAvailability.undo()
        try await waitUntil { self.inkCount(on: firstPage) == 0 }
        XCTAssertEqual(newCanvas.drawing.strokes.count, 0)
        session.undoAvailability.redo()
        try await waitUntil { self.inkCount(on: firstPage) == 1 }
        XCTAssertEqual(newCanvas.drawing.strokes.count, 1)
    }

    /// Strokes drawn in a color from a hex value, and strokes the lasso moved, read back a
    /// little different from the page's stored drawing. Undo found them changed and refused
    /// ("The ink on this page changed in a way this step does not know") once the view was
    /// rebuilt, as on a tab switch, or the page's canvas was released far from it.
    func testColoredAndMovedStrokesAreUndoneAfterThePageInkIsReadBackFromTheFile() async throws {
        let session = try await openNotebook(pageCount: 20)
        let controller = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let firstPage = try XCTUnwrap(session.document.page(at: 0))
        let canvas = try await editingCanvas(for: firstPage, in: session)
        canvas.drawing = PKDrawing(strokes: [coloredStroke(atHeight: 100.37)])
        try await waitUntil { self.inkCount(on: firstPage) == 1 }
        endEvent(of: session)
        canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes + [movedStroke(atHeight: 200.61)])
        try await waitUntil { self.inkCount(on: firstPage) == 2 }
        endEvent(of: session)

        // Another tab replaces the PDF on screen; the canvas made when it comes back reads
        // the page's ink from its stored drawing.
        controller.rootView = AnyView(Text("Another tab"))
        try await waitUntil { self.descendants(of: controller.view, matching: PDFPageCanvasView.self).isEmpty }
        controller.rootView = AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        let newCanvas = try await editingCanvas(for: firstPage, in: session)
        XCTAssertEqual(newCanvas.drawing.strokes.count, 2)
        session.undoAvailability.undo()
        XCTAssertNil(session.errorMessage, "A moved stroke is undone after the view was rebuilt.")
        try await waitUntil { self.inkCount(on: firstPage) == 1 }
        session.undoAvailability.redo()
        XCTAssertNil(session.errorMessage)
        try await waitUntil { self.inkCount(on: firstPage) == 2 }

        // Scrolling far enough releases the canvas, and undo changes the page's ink itself.
        for pageIndex in 1..<session.pageCount {
            session.go(to: pageIndex)
            try await Task.sleep(for: .milliseconds(60))
        }
        let coordinator = try XCTUnwrap((session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator)
        try await waitUntil { coordinator.editingCanvas(for: firstPage) == nil }
        session.undoAvailability.undo()
        XCTAssertNil(session.errorMessage, "A moved stroke is undone after its page's canvas was released.")
        XCTAssertEqual(inkCount(on: firstPage), 1)
        session.undoAvailability.undo()
        XCTAssertNil(session.errorMessage, "A colored stroke is undone after its page's canvas was released.")
        XCTAssertEqual(inkCount(on: firstPage), 0)
    }

    func testTwoPDFsKeepSeparateHistories() async throws {
        let lectureSession = try await openNotebook(pageCount: 1)
        let slidesSession = try await openNotebook(pageCount: 1)
        _ = try host(AnyView(HStack(spacing: 0) {
            NavigationStack { PDFPane(session: lectureSession, resolveConflict: { _ in }) }
            NavigationStack { PDFPane(session: slidesSession, resolveConflict: { _ in }) }
        }))
        let lecturePage = try XCTUnwrap(lectureSession.document.page(at: 0))
        let slidesPage = try XCTUnwrap(slidesSession.document.page(at: 0))
        let lectureCanvas = try await editingCanvas(for: lecturePage, in: lectureSession)
        let slidesCanvas = try await editingCanvas(for: slidesPage, in: slidesSession)
        lectureCanvas.drawing = PKDrawing(strokes: [stroke(atHeight: 100)])
        try await waitUntil { self.inkCount(on: lecturePage) == 1 }
        slidesCanvas.drawing = PKDrawing(strokes: [stroke(atHeight: 150)])
        try await waitUntil { self.inkCount(on: slidesPage) == 1 }

        let lectureView = try XCTUnwrap(lectureSession.pdfView as? GraphitePDFDisplayView)
        let slidesView = try XCTUnwrap(slidesSession.pdfView as? GraphitePDFDisplayView)
        XCTAssertTrue(lectureView.undoManager === lectureSession.undoManager, "⌘Z in a PDF reaches its own history.")
        XCTAssertTrue(slidesView.undoManager === slidesSession.undoManager)
        XCTAssertFalse(lectureCanvas.undoManager === lectureView.window?.undoManager, "PencilKit's own steps stay out of the window's history.")

        // The latest stroke in the window is the slides', yet undo in the lecture undoes the lecture's.
        lectureView.undoManager?.undo()
        XCTAssertEqual(inkCount(on: lecturePage), 0)
        XCTAssertEqual(inkCount(on: slidesPage), 1)
        XCTAssertFalse(lectureSession.undoAvailability.canUndo)
        XCTAssertTrue(slidesSession.undoAvailability.canUndo)
    }

    // MARK: Drawing changes

    func testAddedStrokeIsStoredAloneAndUndoneExactly() throws {
        let first = stroke(atHeight: 100)
        let second = stroke(atHeight: 200)
        let before = PKDrawing(strokes: [first])
        let after = PKDrawing(strokes: [first, second])
        let change = try XCTUnwrap(PencilDrawingChange(from: before, to: after))
        XCTAssertEqual(change.changedStrokeCount, 1, "Only the new stroke is kept.")
        XCTAssertEqual(change.reverting(after)?.strokes.map(\.path.creationDate), before.strokes.map(\.path.creationDate))
        XCTAssertEqual(change.reapplying(to: before)?.strokes.map(\.path.creationDate), after.strokes.map(\.path.creationDate))
        XCTAssertNil(PencilDrawingChange(from: after, to: after), "No change, no step.")
    }

    func testErasingAStrokeInTheMiddleKeepsItsPlace() throws {
        let strokes = (1...4).map { number in stroke(atHeight: CGFloat(number) * 100) }
        let before = PKDrawing(strokes: strokes)
        let after = PKDrawing(strokes: [strokes[0], strokes[1], strokes[3]])
        let change = try XCTUnwrap(PencilDrawingChange(from: before, to: after))
        XCTAssertEqual(change.changedStrokeCount, 1)
        XCTAssertEqual(change.reverting(after)?.strokes.map(\.path.creationDate), strokes.map(\.path.creationDate))
    }

    func testReorderedStrokesFallBackToTheChangedRun() throws {
        let strokes = (1...4).map { number in stroke(atHeight: CGFloat(number) * 100) }
        let before = PKDrawing(strokes: strokes)
        let after = PKDrawing(strokes: [strokes[0], strokes[2], strokes[1], strokes[3]])
        let change = try XCTUnwrap(PencilDrawingChange(from: before, to: after))
        XCTAssertEqual(change.reverting(after)?.strokes.map(\.path.creationDate), strokes.map(\.path.creationDate))
        XCTAssertEqual(change.reapplying(to: before)?.strokes.map(\.path.creationDate), after.strokes.map(\.path.creationDate))
    }

    func testChangeRefusesADrawingItDidNotProduce() throws {
        let first = stroke(atHeight: 100)
        let change = try XCTUnwrap(PencilDrawingChange(from: PKDrawing(), to: PKDrawing(strokes: [first])))
        XCTAssertNil(change.reverting(PKDrawing(strokes: [stroke(atHeight: 300)])), "Another stroke in its place is not undone blindly.")
        XCTAssertNil(change.reverting(PKDrawing()))
    }

    func testColoredAndMovedStrokesKeepTheirPlaceInTheHistoryThroughTheStoredDrawing() throws {
        let drawn = PKDrawing(strokes: [coloredStroke(atHeight: 100.37), movedStroke(atHeight: 200.61)])
        let readBack = try PKDrawing(data: drawn.dataRepresentation())
        XCTAssertNotEqual(readBack.strokes[1].transform, drawn.strokes[1].transform, "PencilKit stores the transform less precisely.")
        let change = try XCTUnwrap(PencilDrawingChange(from: PKDrawing(), to: drawn))
        XCTAssertEqual(change.reverting(readBack)?.strokes.count, 0, "Undo finds the strokes it recorded in the stored drawing.")
        XCTAssertNil(PencilDrawingChange(from: drawn, to: readBack), "Reading the drawing back is no change.")
        let recolored = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .systemRed), path: drawn.strokes[0].path), drawn.strokes[1]])
        XCTAssertEqual(PencilDrawingChange(from: drawn, to: recolored)?.changedStrokeCount, 2, "A recolored stroke is still a change.")
    }

    // MARK: Helpers

    private func openNotebook(pageCount: Int) async throws -> PDFSession {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent("InkHistory-\(UUID().uuidString).pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: pageCount).write(to: location)
        locations.append(location)
        return try await PDFSession.open(location)
    }

    private func host(_ rootView: AnyView) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: rootView)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        windows.append(window)
        return controller
    }

    private func editingCanvas(for page: PDFPage, in session: PDFSession) async throws -> PDFPageCanvasView {
        func coordinator() -> PDFAnnotationCoordinator? { (session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator }
        try await waitUntil { coordinator()?.editingCanvas(for: page) != nil }
        return try XCTUnwrap(coordinator()?.editingCanvas(for: page))
    }

    private var strokeCount = 0

    private func stroke(atHeight height: CGFloat) -> PKStroke {
        strokeCount += 1
        // Distinct creation dates tell otherwise identical strokes apart.
        let creationDate = Date(timeIntervalSinceReferenceDate: Double(strokeCount))
        let points = (0...10).map { pointIndex in
            PKStrokePoint(location: CGPoint(x: CGFloat(50 + pointIndex * 10), y: height), timeOffset: Double(pointIndex) / 10,
                          size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: creationDate))
    }

    /// A stroke as a Pencil draws it, at points between whole numbers, in a color made from a
    /// hex value as the fixed bar's colors are.
    private func coloredStroke(atHeight height: CGFloat) -> PKStroke {
        strokeCount += 1
        let creationDate = Date(timeIntervalSinceReferenceDate: 812_000_000.123456789 + Double(strokeCount))
        let points = (0...10).map { pointIndex in
            PKStrokePoint(location: CGPoint(x: 50.123456789 + CGFloat(pointIndex) * 10.333333333, y: height + sin(CGFloat(pointIndex)) * 3.7),
                          timeOffset: Double(pointIndex) / 60, size: CGSize(width: 2.345678, height: 2.345678), opacity: 1, force: 0.76543,
                          azimuth: 0.4321, altitude: 1.23456)
        }
        let color = UIColor(red: 212 / 255, green: 56 / 255, blue: 45 / 255, alpha: 1)
        return PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: points, creationDate: creationDate))
    }

    /// A colored stroke the lasso moved and resized, which PencilKit keeps as its transform.
    private func movedStroke(atHeight height: CGFloat) -> PKStroke {
        let stroke = coloredStroke(atHeight: height)
        let transform = CGAffineTransform(a: 1.1234567891, b: 0, c: 0, d: 1.1234567891, tx: 12.3456789012, ty: -7.6543210987)
        return PKStroke(ink: stroke.ink, path: stroke.path, transform: transform, mask: nil)
    }

    /// Each stroke arrives in its own touch event, whose end closes its undo group. Strokes
    /// set in code arrive within one turn of the run loop, so the test ends the turn.
    private func endEvent(of session: PDFSession) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(session.undoManager.groupingLevel, 0)
    }

    private func inkCount(on page: PDFPage) -> Int {
        page.annotations.filter { annotation in annotation.type == "Ink" }.count
    }

    private func attachScreenshot(of controller: UIViewController, named name: String) {
        guard let window = controller.view.window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(condition(), "The hosted PDF workspace did not reach the expected state.")
    }
}
#endif
