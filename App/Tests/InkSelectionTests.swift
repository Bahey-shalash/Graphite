#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import PDFKit
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

/// Graphite's lasso on a hosted PDF page: selecting ink, and moving, resizing, recoloring,
/// duplicating, copying and deleting what is selected.
@MainActor
final class InkSelectionTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var locations: [URL] = []
    private var savedShapesPreference: Any?

    override func setUp() async throws {
        savedShapesPreference = UserDefaults.standard.object(forKey: PDFAnnotationPreferenceKey.drawsShapes)
        UserDefaults.standard.set(false, forKey: PDFAnnotationPreferenceKey.drawsShapes)
        PaletteInkSelection.isOn = false
    }

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        for location in locations { try? FileManager.default.removeItem(at: location) }
        locations = []
        PaletteInkSelection.isOn = false
        if let savedShapesPreference { UserDefaults.standard.set(savedShapesPreference, forKey: PDFAnnotationPreferenceKey.drawsShapes) }
        else { UserDefaults.standard.removeObject(forKey: PDFAnnotationPreferenceKey.drawsShapes) }
    }

    func testALoopTakesTheStrokesMostlyInsideItAndATapTakesTheStrokeUnderIt() async throws {
        let (session, canvas, page) = try await openPageWithCanvas()
        let upperStroke = stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 100))
        let lowerStroke = stroke(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 300, y: 200))
        try await draw([upperStroke, lowerStroke], on: canvas, page: page, session: session)

        canvas.selectsInk = true
        XCTAssertFalse(canvas.isDrawingEnabled, "A canvas that selects does not draw.")
        let selection = canvas.inkSelection
        // Around the upper stroke only.
        selection.selectStrokes(enclosedBy: loop(around: CGRect(x: 80, y: 80, width: 240, height: 40)))
        XCTAssertEqual(selection.selectedStrokeIndices, [0])
        let frame = try XCTUnwrap(selection.selectionFrame)
        XCTAssertTrue(frame.contains(CGRect(x: 100, y: 99, width: 200, height: 2)), "The frame surrounds the ink with room to spare.")
        XCTAssertLessThan(frame.maxY, 200)
        XCTAssertEqual(descendants(of: canvas, matching: SelectionFrameView.self).count, 1)

        // A loop over the left third of both takes neither; one around everything takes both.
        selection.selectStrokes(enclosedBy: loop(around: CGRect(x: 80, y: 80, width: 80, height: 140)))
        XCTAssertTrue(selection.selectedStrokeIndices.isEmpty)
        XCTAssertTrue(descendants(of: canvas, matching: SelectionFrameView.self).isEmpty)
        selection.selectStrokes(enclosedBy: loop(around: CGRect(x: 80, y: 80, width: 240, height: 140)))
        XCTAssertEqual(selection.selectedStrokeIndices, [0, 1])

        // A tap takes the stroke passing under it, and nothing where there is no ink.
        XCTAssertTrue(selection.selectStroke(at: CGPoint(x: 200, y: 203)))
        XCTAssertEqual(selection.selectedStrokeIndices, [1])
        XCTAssertFalse(selection.selectStroke(at: CGPoint(x: 200, y: 400)))
        XCTAssertTrue(selection.selectedStrokeIndices.isEmpty)

        // The menu offers the clipboard actions and the colors of Settings › Colors.
        let menu = selection.selectionMenuElements(palette: [PaletteColor(name: "red", hex: "#e93147")])
        XCTAssertEqual(menu.compactMap { element in (element as? UIAction)?.title }, ["Cut", "Copy", "Duplicate", "Smooth", "Delete"])
        let colorMenu = try XCTUnwrap(menu.compactMap { element in element as? UIMenu }.first)
        XCTAssertEqual(colorMenu.children.map(\.title), ["black", "red"])

        // Choosing a tool again ends selecting, and the selection with it.
        selection.select([0])
        canvas.selectsInk = false
        XCTAssertTrue(canvas.isDrawingEnabled)
        XCTAssertTrue(canvas.inkSelection.selectedStrokeIndices.isEmpty)
        XCTAssertTrue(descendants(of: canvas, matching: SelectionFrameView.self).isEmpty)
    }

    func testMovingAndResizingTheSelectionChangesItsStrokesAsOneUndoStep() async throws {
        let (session, canvas, page) = try await openPageWithCanvas()
        let selectedStroke = stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100), width: 4)
        let otherStroke = stroke(from: CGPoint(x: 100, y: 300), to: CGPoint(x: 200, y: 300), width: 4)
        try await draw([selectedStroke, otherStroke], on: canvas, page: page, session: session)
        canvas.selectsInk = true
        let selection = canvas.inkSelection
        selection.select([0])
        let frame = try XCTUnwrap(selection.selectionFrame)

        // Twice the size, with its top-left corner moved by (50, 20).
        let inkBoundsBefore = selectedStroke.renderBounds
        let newFrame = CGRect(x: frame.minX + 50, y: frame.minY + 20, width: frame.width * 2, height: frame.height * 2)
        selection.moveSelection(in: canvas.drawing, from: frame, to: newFrame)
        try await waitUntil { session.undoAvailability.canUndo && session.hasUnsavedChanges }
        let movedStroke = try XCTUnwrap(canvas.drawing.strokes.first)
        XCTAssertEqual(canvas.drawing.strokes.count, 2)
        XCTAssertEqual(movedStroke.transform, .identity, "The move is in the stroke's points, which is what is saved.")
        // The frame stays where it was left, with the same margin around ink that fills it.
        let frameAfter = try XCTUnwrap(selection.selectionFrame)
        XCTAssertEqual(frameAfter.minX, newFrame.minX, accuracy: 1)
        XCTAssertEqual(frameAfter.minY, newFrame.minY, accuracy: 1)
        XCTAssertEqual(frameAfter.width, newFrame.width, accuracy: 2)
        let inkScale = ((movedStroke.path.last?.location.x ?? 0) - (movedStroke.path.first?.location.x ?? 0)) / 100
        XCTAssertGreaterThan(inkScale, 2, "The margin does not grow with the ink, so the ink grows a little more than the frame.")
        // The extra scale depends on the canvas-to-screen scale and PencilKit's padding;
        // the frame width above verifies the actual requested size without a guessed cap.
        XCTAssertGreaterThan(movedStroke.renderBounds.width, inkBoundsBefore.width * 2)
        XCTAssertEqual(movedStroke.path.first?.size.width ?? 0, 4 * inkScale, accuracy: 0.01, "Larger ink is broader by as much.")
        XCTAssertEqual(canvas.drawing.strokes[1].path.first?.location, otherStroke.path.first?.location, "Other strokes stay.")
        XCTAssertEqual(selection.selectedStrokeIndices, [0], "The moved strokes stay selected.")

        // What is saved draws the same: the moved stroke, as broad as shown.
        try await session.save()
        let reopened = try XCTUnwrap(PDFDocument(url: session.location))
        let savedInk = try XCTUnwrap(reopened.page(at: 0)).annotations.filter { annotation in annotation.type == "Ink" }
        XCTAssertEqual(savedInk.count, 2)

        endEvent(of: session.undoManager)
        session.undoAvailability.undo()
        try await waitUntil { canvas.drawing.strokes.first?.path.first?.location == selectedStroke.path.first?.location }
        XCTAssertEqual(canvas.drawing.strokes.first?.path.first?.size.width ?? 0, 4, accuracy: 0.01)
        XCTAssertTrue(selection.selectedStrokeIndices.isEmpty, "Undo changes the drawing under the selection, which ends.")
        XCTAssertEqual(canvas.drawing.strokes.count, 2)
    }

    func testRecoloringDuplicatingAndDeletingTheSelection() async throws {
        let (session, canvas, page) = try await openPageWithCanvas()
        let highlighted = stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 100), ink: PKInk(.marker, color: UIColor.yellow.withAlphaComponent(0.5)), width: 20)
        let written = stroke(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 300, y: 200))
        try await draw([highlighted, written], on: canvas, page: page, session: session)
        canvas.selectsInk = true
        let selection = canvas.inkSelection

        // Each stroke keeps its ink and its opacity under a new color.
        selection.select([0, 1])
        selection.recolorSelection(.red)
        try await waitUntil { session.undoAvailability.canUndo }
        let recolored = canvas.drawing.strokes
        XCTAssertEqual(recolored.map(\.ink.inkType), [.marker, .pen])
        XCTAssertEqual(recolored[0].ink.color.cgColor.alpha, 0.5, accuracy: 0.01)
        XCTAssertEqual(recolored[1].ink.color.cgColor.alpha, 1, accuracy: 0.01)
        for stroke in recolored {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
            stroke.ink.color.getRed(&red, green: &green, blue: &blue, alpha: nil)
            XCTAssertEqual(red, 1, accuracy: 0.01)
            XCTAssertEqual(green + blue, 0, accuracy: 0.01)
        }
        XCTAssertEqual(recolored[0].path.first?.location, highlighted.path.first?.location)
        XCTAssertEqual(selection.selectedStrokeIndices, [0, 1])
        endEvent(of: session.undoManager)

        // Copies are added after everything else, a little down and to the right, and are
        // what is selected then. With the shape tool on they are still copies, not shapes.
        UserDefaults.standard.set(true, forKey: PDFAnnotationPreferenceKey.drawsShapes)
        try await Task.sleep(for: .milliseconds(200))
        selection.select([1])
        selection.duplicateSelection()
        try await waitUntil { self.inkAnnotationCount(on: page) == 3 }
        XCTAssertEqual(canvas.drawing.strokes.count, 3)
        XCTAssertEqual(selection.selectedStrokeIndices, [2])
        let copiedStroke = canvas.drawing.strokes[2]
        XCTAssertEqual(copiedStroke.path.count, written.path.count, "A copied line is not redrawn as a shape.")
        XCTAssertGreaterThan(copiedStroke.path.first?.location.x ?? 0, 100)
        XCTAssertGreaterThan(copiedStroke.path.first?.location.y ?? 0, 200)
        UserDefaults.standard.set(false, forKey: PDFAnnotationPreferenceKey.drawsShapes)
        endEvent(of: session.undoManager)

        // Copy puts PencilKit ink and a picture on the pasteboard; paste adds it where asked.
        selection.copySelection()
        let pasteboardDrawing = try PKDrawing(data: try XCTUnwrap(UIPasteboard.general.data(forPasteboardType: PKAppleDrawingTypeIdentifier as String)))
        XCTAssertEqual(pasteboardDrawing.strokes.count, 1)
        XCTAssertNotNil(UIPasteboard.general.image)
        // The place is in the canvas's points, which its zoom (`PDFPageOverlayView`) makes
        // larger than the drawing's.
        selection.pasteInk(at: CGPoint(x: 300 * canvas.zoomScale, y: 500 * canvas.zoomScale))
        try await waitUntil { self.inkAnnotationCount(on: page) == 4 }
        XCTAssertEqual(selection.selectedStrokeIndices, [3])
        XCTAssertEqual(canvas.drawing.strokes[3].renderBounds.midX, 300, accuracy: 1)
        XCTAssertEqual(canvas.drawing.strokes[3].renderBounds.midY, 500, accuracy: 1)
        endEvent(of: session.undoManager)

        // Delete removes the selected strokes and the selection; one undo brings them back.
        selection.select([0, 3])
        selection.deleteSelection()
        try await waitUntil { self.inkAnnotationCount(on: page) == 2 }
        XCTAssertEqual(canvas.drawing.strokes.count, 2)
        XCTAssertEqual(canvas.drawing.strokes.map(\.ink.inkType), [.pen, .pen])
        XCTAssertTrue(selection.selectedStrokeIndices.isEmpty)
        endEvent(of: session.undoManager)
        session.undoAvailability.undo()
        try await waitUntil { canvas.drawing.strokes.count == 4 }
        XCTAssertEqual(canvas.drawing.strokes.first?.ink.inkType, .marker)
    }

    func testThePalettesSwitchPutsCanvasesIntoSelectingAndAToolChoiceEndsIt() async throws {
        UserDefaults.standard.set(PencilToolbarStyle.floating.rawValue, forKey: PencilToolbarStyle.preferenceKey)
        defer { UserDefaults.standard.removeObject(forKey: PencilToolbarStyle.preferenceKey) }
        let (session, canvas, _) = try await openPageWithCanvas()
        XCTAssertTrue(canvas.followsToolPicker)
        XCTAssertFalse(canvas.selectsInk)

        let toolPicker = PencilToolPalette.makeToolPicker()
        PaletteInkSelection.isOn = true
        XCTAssertTrue(canvas.selectsInk)
        XCTAssertFalse(canvas.isDrawingEnabled)

        // The palette's menu shows the switch as on, and choosing a tool in the palette ends it.
        let inlineMenus = PencilToolPalette.menuElements(for: toolPicker, palette: []).compactMap { element in element as? UIMenu }
        let switches = inlineMenus.flatMap(\.children).compactMap { element in element as? UIAction }
        XCTAssertEqual(switches.first { action in action.title == "Select Ink" }?.state, .on)
        let otherToolItem = try XCTUnwrap(toolPicker.toolItems.first { item in item !== toolPicker.selectedToolItem })
        toolPicker.selectedToolItem = otherToolItem
        try await waitUntil { !PaletteInkSelection.isOn }
        XCTAssertFalse(canvas.selectsInk)
        XCTAssertTrue(canvas.isDrawingEnabled)
        _ = session
    }

    // MARK: Helpers

    func testStraighteningALineOfWritingAndSmoothingItsStrokesAreUndoableSteps() async throws {
        let (session, canvas, page) = try await openPageWithCanvas()
        // Six zigzag "letters" along a line that runs 12 degrees downhill.
        let slope = tan(12 * CGFloat.pi / 180)
        let letters = (0..<6).map { letterIndex -> PKStroke in
            let startX = 100 + CGFloat(letterIndex) * 45
            let points = (0...12).map { pointIndex -> PKStrokePoint in
                let x = startX + CGFloat(pointIndex) * 3
                let y = 300 + (x - 100) * slope + (pointIndex.isMultiple(of: 2) ? -12 : 12)
                return PKStrokePoint(location: CGPoint(x: x, y: y), timeOffset: Double(pointIndex) / 60, size: CGSize(width: 3, height: 3),
                                     opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        }
        try await draw(letters, on: canvas, page: page, session: session)
        canvas.selectsInk = true
        let selection = canvas.inkSelection
        selection.select(Array(letters.indices))
        let slant = try XCTUnwrap(selection.selectionSlant)
        XCTAssertEqual(slant, 12 * .pi / 180, accuracy: 0.03)
        XCTAssertTrue(selection.selectionMenuElements().contains { element in element.title == "Straighten" })
        let middleBefore = selection.selectedStrokes.reduce(CGRect.null) { bounds, stroke in bounds.union(stroke.renderBounds) }

        // Each change is recorded once the canvas reports it; the next waits for that.
        let versionBeforeStraightening = session.changeVersion
        selection.straightenSelection()
        try await waitUntil { selection.selectionSlant == nil && session.changeVersion > versionBeforeStraightening }
        let straightened = selection.selectedStrokes.reduce(CGRect.null) { bounds, stroke in bounds.union(stroke.renderBounds) }
        XCTAssertEqual(straightened.midX, middleBefore.midX, accuracy: 2, "Turned about its middle.")
        XCTAssertEqual(straightened.midY, middleBefore.midY, accuracy: 2)
        XCTAssertLessThan(straightened.height, middleBefore.height - 40, "The line runs level now.")
        XCTAssertFalse(selection.selectionMenuElements().contains { element in element.title == "Straighten" })
        endEvent(of: session.undoManager)

        // Smoothing keeps each stroke's ends and flattens its zigzag.
        let before = canvas.drawing.strokes
        func inkHeightOnThePage() -> CGFloat {
            page.annotations.filter { annotation in annotation.type == "Ink" }.reduce(CGRect.null) { bounds, annotation in bounds.union(annotation.bounds) }.height
        }
        let inkHeightBeforeSmoothing = inkHeightOnThePage()
        let versionBeforeSmoothing = session.changeVersion
        selection.smoothSelection()
        try await waitUntil { session.changeVersion > versionBeforeSmoothing }
        XCTAssertLessThan(inkHeightOnThePage(), inkHeightBeforeSmoothing - 1, "The page's ink, which is saved, is smoothed too.")
        for (smoothedStroke, originalStroke) in zip(canvas.drawing.strokes, before) {
            XCTAssertEqual(smoothedStroke.path.first?.location, originalStroke.path.first?.location)
            XCTAssertEqual(smoothedStroke.path.last?.location, originalStroke.path.last?.location)
            XCTAssertLessThan(smoothedStroke.renderBounds.height, originalStroke.renderBounds.height)
        }
        endEvent(of: session.undoManager)

        // Each is one step of the PDF's history, which keeps the ink as page annotations.
        func secondPoint(of strokes: [PKStroke]) -> CGPoint { strokes.first?.path.dropFirst().first?.location ?? .zero }
        func isClose(_ point: CGPoint, to otherPoint: CGPoint) -> Bool { abs(point.x - otherPoint.x) < 0.1 && abs(point.y - otherPoint.y) < 0.1 }
        session.undoAvailability.undo()
        try await waitUntil { isClose(secondPoint(of: canvas.drawing.strokes), to: secondPoint(of: before)) }
        session.undoAvailability.undo()
        try await waitUntil { isClose(secondPoint(of: canvas.drawing.strokes), to: secondPoint(of: letters)) }
    }

    private func openPageWithCanvas() async throws -> (PDFSession, PDFPageCanvasView, PDFPage) {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent("InkSelection-\(UUID().uuidString).pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank)).write(to: location)
        locations.append(location)
        let session = try await PDFSession.open(location)
        let controller = UIHostingController(rootView: AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        windows.append(window)
        let page = try XCTUnwrap(session.document.page(at: 0))
        func coordinator() -> PDFAnnotationCoordinator? { (session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator }
        try await waitUntil { coordinator()?.editingCanvas(for: page) != nil }
        return (session, try XCTUnwrap(coordinator()?.editingCanvas(for: page)), page)
    }

    /// Gives the canvas strokes as if they had been drawn, and waits until they are recorded.
    private func draw(_ strokes: [PKStroke], on canvas: PDFPageCanvasView, page: PDFPage, session: PDFSession) async throws {
        canvas.drawing = PKDrawing(strokes: strokes)
        try await waitUntil { self.inkAnnotationCount(on: page) == strokes.count }
        endEvent(of: session.undoManager)
    }

    private func inkAnnotationCount(on page: PDFPage) -> Int {
        page.annotations.filter { annotation in annotation.type == "Ink" }.count
    }

    private func stroke(from start: CGPoint, to end: CGPoint, ink: PKInk = PKInk(.pen, color: .black), width: CGFloat = 4) -> PKStroke {
        let points = (0...20).map { pointIndex -> PKStrokePoint in
            let fraction = CGFloat(pointIndex) / 20
            let location = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
            return PKStrokePoint(location: location, timeOffset: Double(pointIndex) / 60, size: CGSize(width: width, height: width),
                                 opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    private func loop(around rectangle: CGRect) -> [CGPoint] {
        [CGPoint(x: rectangle.minX, y: rectangle.minY), CGPoint(x: rectangle.maxX, y: rectangle.minY),
         CGPoint(x: rectangle.maxX, y: rectangle.maxY), CGPoint(x: rectangle.minX, y: rectangle.maxY)]
    }

    /// Steps made in code arrive within one turn of the run loop, in one undo group.
    private func endEvent(of history: UndoManager) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(history.groupingLevel, 0)
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            if ContinuousClock.now > deadline { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "The hosted view did not reach the expected state.")
    }
}
#endif
