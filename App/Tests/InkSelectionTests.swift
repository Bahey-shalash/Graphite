#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import PDFKit
import UniformTypeIdentifiers
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
        // The simulator replaces the system's pasteboard with the Mac's at any moment.
        LassoPasteboard.pasteboard = UIPasteboard(name: UIPasteboard.Name("GraphiteInkSelectionTests-\(UUID().uuidString)"), create: true) ?? .general
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
        if LassoPasteboard.pasteboard !== UIPasteboard.general { UIPasteboard.remove(withName: LassoPasteboard.pasteboard.name) }
        LassoPasteboard.pasteboard = .general
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
        selection.selectContents(enclosedBy: loop(around: CGRect(x: 80, y: 80, width: 240, height: 40)))
        XCTAssertEqual(selection.selectedStrokeIndices, [0])
        let frame = try XCTUnwrap(selection.selectionFrame)
        XCTAssertTrue(frame.contains(CGRect(x: 100, y: 99, width: 200, height: 2)), "The frame surrounds the ink with room to spare.")
        XCTAssertLessThan(frame.maxY, 200)
        XCTAssertEqual(descendants(of: canvas, matching: SelectionFrameView.self).count, 1)

        // A loop over the left third of both takes neither; one around everything takes both.
        selection.selectContents(enclosedBy: loop(around: CGRect(x: 80, y: 80, width: 80, height: 140)))
        XCTAssertTrue(selection.selectedStrokeIndices.isEmpty)
        XCTAssertTrue(descendants(of: canvas, matching: SelectionFrameView.self).isEmpty)
        selection.selectContents(enclosedBy: loop(around: CGRect(x: 80, y: 80, width: 240, height: 140)))
        XCTAssertEqual(selection.selectedStrokeIndices, [0, 1])

        // A tap takes the stroke passing under it, and nothing where there is no ink.
        XCTAssertTrue(selection.selectStroke(at: CGPoint(x: 200, y: 203)))
        XCTAssertEqual(selection.selectedStrokeIndices, [1])
        XCTAssertFalse(selection.selectStroke(at: CGPoint(x: 200, y: 400)))
        XCTAssertTrue(selection.selectedStrokeIndices.isEmpty)

        // The menu offers the clipboard actions and the colors of Settings › Colors.
        selection.select([1])
        let menu = selection.selectionMenuElements(palette: [PaletteColor(name: "red", hex: "#e93147")])
        XCTAssertEqual(menu.compactMap { element in (element as? UIAction)?.title }, ["Cut", "Copy", "Duplicate", "Take Screenshot", "Smooth", "Delete"])
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
        let pasteboardDrawing = try PKDrawing(data: try XCTUnwrap(LassoPasteboard.pasteboard.data(forPasteboardType: PKAppleDrawingTypeIdentifier as String)))
        XCTAssertEqual(pasteboardDrawing.strokes.count, 1)
        XCTAssertNotNil(LassoPasteboard.pasteboard.image)
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

}

// MARK: The lasso's loop, types, pictures, screenshots and the laser pointer

extension InkSelectionTests {
    /// How large a point of the canvas is on screen.
    private func screenScale(of canvas: UIView) -> CGFloat {
        canvas.convert(CGRect(x: 0, y: 0, width: 1, height: 1), to: nil).width
    }

    private func canvasPoint(_ drawingPoint: CGPoint, on canvas: PKCanvasView) -> CGPoint {
        CGPoint(x: drawingPoint.x * canvas.zoomScale, y: drawingPoint.y * canvas.zoomScale)
    }

    private func contrastRatio(_ color: CGColor, against background: UIColor = .white) -> Double {
        func luminance(_ color: UIColor) -> Double {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: nil)
            func linear(_ component: CGFloat) -> Double {
                let value = Double(component)
                return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
        let lighter = max(luminance(UIColor(cgColor: color)), luminance(background)), darker = min(luminance(UIColor(cgColor: color)), luminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func pictureData(size: CGSize, color: UIColor) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return try XCTUnwrap(image.pngData())
    }

    /// The color of an image at a point given in its own points from its top-left corner.
    private func color(of image: UIImage, at point: CGPoint) throws -> (red: Double, green: Double, blue: Double, alpha: Double) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let pixelsPerPoint = Double(cgImage.width) / Double(image.size.width)
        context.draw(cgImage, in: CGRect(x: -point.x * pixelsPerPoint, y: -(Double(cgImage.height) - point.y * pixelsPerPoint - 1),
                                         width: Double(cgImage.width), height: Double(cgImage.height)))
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255, Double(pixel[3]) / 255)
    }

    private func attachScreenshot(of view: UIView, named name: String) {
        guard let window = view.window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        attach(screenshot, named: name)
    }

    private func attach(_ image: UIImage, named name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dot(at point: CGPoint) -> PKStroke {
        let dotPoint = PKStrokePoint(location: point, timeOffset: 0, size: CGSize(width: 5, height: 5), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: [dotPoint], creationDate: Date()))
    }

    func testTheLoopIsTheAccentAsOnWhiteOverAHaloAtTheSameWidthAtAnyZoomAndInDarkAppearance() async throws {
        let (session, canvas, _) = try await openPageWithCanvas()
        let window = try XCTUnwrap(canvas.window)
        window.overrideUserInterfaceStyle = .dark
        defer { window.overrideUserInterfaceStyle = .unspecified }
        canvas.selectsInk = true
        let selection = canvas.inkSelection
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        let fittedScale = pdfView.scaleFactor
        for scaleFactor in [fittedScale, fittedScale * 0.5, fittedScale * 2.5] {
            pdfView.scaleFactor = scaleFactor
            pdfView.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            selection.loopDidBegin(at: canvasPoint(CGPoint(x: 100, y: 100), on: canvas), reaching: canvasPoint(CGPoint(x: 140, y: 110), on: canvas))
            selection.loopDidMove(to: canvasPoint(CGPoint(x: 200, y: 180), on: canvas))
            selection.loopDidMove(to: canvasPoint(CGPoint(x: 120, y: 220), on: canvas))
            let layers = try XCTUnwrap(selection.shownLoopLayers, "The loop shows while it is drawn.")
            let scale = screenScale(of: canvas)
            XCTAssertEqual(layers.line.lineWidth * scale, 1.5, accuracy: 0.01, "The line is 1.5 points on screen at any zoom.")
            XCTAssertEqual(CGFloat(layers.line.lineDashPattern?.first?.doubleValue ?? 0) * scale, 6, accuracy: 0.01)
            XCTAssertEqual(layers.halo.lineWidth * scale, 3.5, accuracy: 0.01, "A point of white halo on each side.")
            if scaleFactor == fittedScale * 0.5 { attachScreenshot(of: canvas, named: "Lasso loop on a zoomed-out page, dark appearance") }
            selection.loopWasCancelled()
            XCTAssertNil(selection.shownLoopLayers)
        }
        // On the white page in dark appearance, the line is the accent as it reads on white.
        selection.loopDidBegin(at: canvasPoint(CGPoint(x: 100, y: 100), on: canvas), reaching: canvasPoint(CGPoint(x: 140, y: 110), on: canvas))
        let layers = try XCTUnwrap(selection.shownLoopLayers)
        let lineColor = try XCTUnwrap(layers.line.strokeColor)
        XCTAssertGreaterThanOrEqual(contrastRatio(lineColor), 3, "The line stands out from a white page: \(contrastRatio(lineColor)):1.")
        XCTAssertEqual(UIColor(cgColor: try XCTUnwrap(layers.halo.strokeColor)).cgColor.alpha, 0.9, accuracy: 0.01)
        selection.loopWasCancelled()
    }

    func testALoopTakesADotARectangleTakesWhatItEnclosesAndATapMovesTheSelection() async throws {
        let shapeBefore = LassoShape.stored
        defer { LassoShape.stored = shapeBefore }
        let (session, canvas, page) = try await openPageWithCanvas()
        let line = stroke(from: CGPoint(x: 100, y: 300), to: CGPoint(x: 300, y: 300))
        try await draw([dot(at: CGPoint(x: 150, y: 150)), line], on: canvas, page: page, session: session)
        canvas.selectsInk = true
        let selection = canvas.inkSelection

        // A freehand loop around the dot of an "i" takes it.
        LassoShape.stored = .freehand
        selection.selectContents(enclosedBy: loop(around: CGRect(x: 130, y: 130, width: 40, height: 40)).map { point in canvasPoint(point, on: canvas) })
        XCTAssertEqual(selection.selectedStrokeIndices, [0])

        // A rectangle dragged from one corner to the other takes what it encloses.
        LassoShape.stored = .rectangle
        selection.loopDidBegin(at: canvasPoint(CGPoint(x: 80, y: 260), on: canvas), reaching: canvasPoint(CGPoint(x: 120, y: 280), on: canvas))
        selection.loopDidMove(to: canvasPoint(CGPoint(x: 250, y: 330), on: canvas))
        let rectangleLayers = try XCTUnwrap(selection.shownLoopLayers)
        XCTAssertNotNil(rectangleLayers.line.fillColor, "The box being dragged is tinted.")
        attachScreenshot(of: canvas, named: "Rectangular lasso being dragged")
        selection.loopDidEnd(at: canvasPoint(CGPoint(x: 320, y: 330), on: canvas))
        XCTAssertEqual(selection.selectedStrokeIndices, [1])
        XCTAssertNotNil(selection.selectionFrame)

        // A box thinner than a tap's reach on screen is a slip, and takes nothing.
        selection.loopDidBegin(at: canvasPoint(CGPoint(x: 80, y: 290), on: canvas), reaching: canvasPoint(CGPoint(x: 90, y: 291), on: canvas))
        selection.loopDidEnd(at: canvasPoint(CGPoint(x: 320, y: 292), on: canvas))
        XCTAssertTrue(selection.selectedStrokeIndices.isEmpty)
        XCTAssertFalse(selection.isShowingLassoedArea)

        // With one stroke selected, a tap on another selects it at once.
        selection.select([1])
        XCTAssertTrue(selection.selectStroke(at: canvasPoint(CGPoint(x: 150, y: 151), on: canvas)))
        XCTAssertEqual(selection.selectedStrokeIndices, [0])

        // The frame around a dot is small, but its middle moves it: the handles' touch areas
        // reach only a quarter of the way in.
        let frameView = try XCTUnwrap(descendants(of: canvas, matching: SelectionFrameView.self).first)
        frameView.layoutIfNeeded()
        let middle = CGPoint(x: frameView.bounds.midX, y: frameView.bounds.midY)
        XCTAssertTrue(frameView.hitTest(middle, with: nil) === frameView, "A touch in the middle of a small frame moves it.")
        let corner = CGPoint(x: frameView.bounds.maxX + 4 / screenScale(of: canvas), y: frameView.bounds.maxY + 4 / screenScale(of: canvas))
        XCTAssertFalse(frameView.hitTest(corner, with: nil) === frameView, "Beside the corner, the handle resizes.")
        let besideTopLeft = CGPoint(x: -4 / screenScale(of: canvas), y: -4 / screenScale(of: canvas))
        XCTAssertNil(frameView.hitTest(besideTopLeft, with: nil), "A frame too small for four knobs has one, at its bottom-right corner.")
    }

    func testTheFrameFollowsTheInkAndKeepsItsSizeOnScreenWhenThePageIsZoomed() async throws {
        let (session, canvas, page) = try await openPageWithCanvas()
        try await draw([stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 100))], on: canvas, page: page, session: session)
        canvas.selectsInk = true
        let selection = canvas.inkSelection
        selection.select([0])
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        pdfView.scaleFactor *= 2.2
        pdfView.layoutIfNeeded()
        // The overlay draws the canvas sharper in steps, which moves the frame's coordinates.
        try await waitUntil {
            guard let frame = selection.selectionFrame, let frameView = self.descendants(of: canvas, matching: SelectionFrameView.self).first else { return false }
            let inkFrame = CGRect(x: 100 * canvas.zoomScale, y: 98 * canvas.zoomScale, width: 200 * canvas.zoomScale, height: 4 * canvas.zoomScale)
            return frame.contains(inkFrame) && abs(frameView.contentScale - self.screenScale(of: canvas)) < 0.01
        }
        // Scrolled to the ink, the frame is around it, its handles the same size on screen.
        let cropBox = page.bounds(for: .cropBox)
        pdfView.go(to: CGRect(x: cropBox.minX + 60, y: cropBox.maxY - 300, width: 300, height: 260), on: page)
        pdfView.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let frameView = try XCTUnwrap(descendants(of: canvas, matching: SelectionFrameView.self).first)
        XCTAssertEqual(frameView.contentScale, screenScale(of: canvas), accuracy: 0.01)
        attachScreenshot(of: canvas, named: "Selected ink on a zoomed-in page")
    }

    func testAnAreaWithNothingInItIsMarkedAndItsMenuTakesAScreenshot() async throws {
        let (session, canvas, page) = try await openPageWithCanvas()
        try await draw([stroke(from: CGPoint(x: 100, y: 500), to: CGPoint(x: 300, y: 500))], on: canvas, page: page, session: session)
        canvas.selectsInk = true
        let selection = canvas.inkSelection
        let area = CGRect(x: 60, y: 60, width: 300, height: 200)
        selection.selectContents(enclosedBy: loop(around: area).map { point in canvasPoint(point, on: canvas) })
        XCTAssertTrue(selection.selectedStrokeIndices.isEmpty)
        XCTAssertTrue(selection.isShowingLassoedArea)
        XCTAssertNotNil(selection.shownLoopLayers?.line.fillColor, "The marked area is tinted.")
        LassoPasteboard.pasteboard.items = []
        XCTAssertEqual(selection.areaMenuElements().map(\.title), ["Take Screenshot"])
        _ = try putImageOnPasteboard(size: CGSize(width: 40, height: 40), color: .red)
        XCTAssertEqual(selection.areaMenuElements().map(\.title), ["Take Screenshot", "Paste"], "An image can be pasted in the area.")
        let region = try XCTUnwrap(selection.captureRegion)
        XCTAssertEqual(region.minX, area.minX, accuracy: 0.5)
        XCTAssertEqual(region.width, area.width, accuracy: 0.5)
        attachScreenshot(of: canvas, named: "Marked area")
        // A tap beside it ends it.
        XCTAssertFalse(selection.selectStroke(at: canvasPoint(CGPoint(x: 400, y: 700), on: canvas)))
        XCTAssertFalse(selection.isShowingLassoedArea)
        XCTAssertNil(selection.shownLoopLayers)
    }

    func testAScreenshotDrawsThePageItsPicturesAndInkAtPrintResolutionAtAnyZoom() async throws {
        let (session, canvas, page) = try await openPageWithCanvas()
        try await session.addPicture(imageData: try pictureData(size: CGSize(width: 400, height: 200), color: .red))
        session.selectedPicture = nil
        endEvent(of: session.undoManager)
        let picture = try XCTUnwrap(canvas.lassoPictures().first)
        // Black ink across the top of the picture, and a highlighter on the white page.
        let ink = stroke(from: CGPoint(x: picture.frame.minX + 20, y: picture.frame.minY + 10), to: CGPoint(x: picture.frame.maxX - 20, y: picture.frame.minY + 10), width: 6)
        let highlight = stroke(from: CGPoint(x: picture.frame.minX, y: picture.frame.maxY + 40), to: CGPoint(x: picture.frame.maxX, y: picture.frame.maxY + 40),
                               ink: PKInk(.marker, color: UIColor(red: 1, green: 1, blue: 0, alpha: 0.5)), width: 20)
        try await draw([ink, highlight], on: canvas, page: page, session: session)
        canvas.selectsInk = true
        let selection = canvas.inkSelection
        let area = picture.frame.insetBy(dx: -30, dy: -30).union(highlight.renderBounds.insetBy(dx: -10, dy: -10))
        selection.selectContents(enclosedBy: loop(around: area).map { point in canvasPoint(point, on: canvas) })
        XCTAssertEqual(selection.selectedStrokeIndices, [0, 1])
        XCTAssertEqual(selection.selectedPictureIdentifiers, [picture.identifier])
        let region = try XCTUnwrap(selection.captureRegion)

        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        var pixelSizes: [CGSize] = []
        for scaleFactor in [pdfView.scaleFactor, pdfView.scaleFactor * 0.4] {
            pdfView.scaleFactor = scaleFactor
            pdfView.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            let image = try XCTUnwrap(selection.captureImage())
            pixelSizes.append(CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale))
            XCTAssertEqual(image.size.width, region.integral.width, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(image.scale, LassoAreaCapture.preferredPixelsPerPoint, "Drawn at 288 pixels per inch, not taken from the screen.")
            func local(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x - region.integral.minX, y: point.y - region.integral.minY) }
            let pictureColor = try color(of: image, at: local(CGPoint(x: picture.frame.midX, y: picture.frame.midY + 30)))
            XCTAssertGreaterThan(pictureColor.red, 0.8); XCTAssertLessThan(pictureColor.green, 0.3)
            let inkColor = try color(of: image, at: local(CGPoint(x: picture.frame.midX, y: picture.frame.minY + 10)))
            XCTAssertLessThan(inkColor.red, 0.3, "The ink is drawn over the picture.")
            let highlightColor = try color(of: image, at: local(CGPoint(x: picture.frame.midX, y: picture.frame.maxY + 40)))
            XCTAssertGreaterThan(highlightColor.red, 0.9)
            XCTAssertEqual(highlightColor.blue, 0.5, accuracy: 0.15, "The highlighter is drawn once, not again from the page's annotation.")
            let paperColor = try color(of: image, at: local(CGPoint(x: region.minX + 3, y: region.minY + 3)))
            XCTAssertGreaterThan(paperColor.blue, 0.95, "The page is white paper.")
            if scaleFactor != pdfView.scaleFactor || pixelSizes.count == 1 { attach(image, named: "Screenshot of a page area at scale \(scaleFactor)") }
        }
        XCTAssertEqual(pixelSizes.first, pixelSizes.last, "A zoomed-out page gives the same sharp picture.")

        // A page shown turned gives the picture turned as it is shown.
        page.rotation = 90
        defer { page.rotation = 0 }
        let turnedImage = try XCTUnwrap(selection.captureImage())
        XCTAssertEqual(turnedImage.size.width, region.integral.height, accuracy: 0.5)
        XCTAssertEqual(turnedImage.size.height, region.integral.width, accuracy: 0.5)
    }

    func testInkAndPicturesSelectedTogetherMoveResizeAndDeleteAsOneUndoStep() async throws {
        let (session, canvas, page) = try await openPageWithCanvas()
        try await session.addPicture(imageData: try pictureData(size: CGSize(width: 400, height: 200), color: .systemTeal))
        session.selectedPicture = nil
        endEvent(of: session.undoManager)
        let picture = try XCTUnwrap(canvas.lassoPictures().first)
        let pictureBoundsBefore = try XCTUnwrap(session.pictures(on: page).first).bounds
        let writing = stroke(from: CGPoint(x: picture.frame.minX, y: picture.frame.minY - 30), to: CGPoint(x: picture.frame.maxX, y: picture.frame.minY - 30))
        try await draw([writing], on: canvas, page: page, session: session)
        canvas.selectsInk = true
        let selection = canvas.inkSelection
        selection.selectContents(enclosedBy: loop(around: picture.frame.insetBy(dx: -20, dy: -50)).map { point in canvasPoint(point, on: canvas) })
        XCTAssertEqual(selection.selectedStrokeIndices, [0])
        XCTAssertEqual(selection.selectedPictureIdentifiers, [picture.identifier])
        XCTAssertEqual(selection.selectionMenuElements(palette: []).compactMap { element in (element as? UIAction)?.title },
                       ["Copy", "Take Screenshot", "Smooth", "Delete"], "Ink and pictures are copied as a picture; Cut and Duplicate would lose the pictures.")
        let frameView = try XCTUnwrap(descendants(of: canvas, matching: SelectionFrameView.self).first)
        XCTAssertEqual(frameView.accessibilityLabel, "Selected ink and images")
        XCTAssertTrue(frameView.accessibilityCustomActions?.contains { action in action.name == "Take Screenshot" } ?? false)
        attachScreenshot(of: canvas, named: "Ink and a picture selected together")

        // Moved by (40, 60) and half as large again: the picture and the ink go together.
        let frame = try XCTUnwrap(selection.selectionFrame)
        let newFrame = CGRect(x: frame.minX + 40 * canvas.zoomScale, y: frame.minY + 60 * canvas.zoomScale, width: frame.width * 1.5, height: frame.height * 1.5)
        let versionBefore = session.changeVersion
        selection.moveSelection(in: canvas.drawing, from: frame, to: newFrame)
        try await waitUntil { session.changeVersion > versionBefore }
        let movedPicture = try XCTUnwrap(canvas.lassoPictures().first)
        XCTAssertGreaterThan(movedPicture.frame.width, picture.frame.width * 1.4)
        XCTAssertGreaterThan(movedPicture.frame.minX, picture.frame.minX + 30)
        let movedInk = try XCTUnwrap(canvas.drawing.strokes.first)
        XCTAssertLessThan(movedInk.renderBounds.maxY, movedPicture.frame.minY, "The ink stays above the picture.")
        XCTAssertGreaterThan(movedInk.renderBounds.minX, writing.renderBounds.minX + 30)
        XCTAssertEqual(selection.selectedPictureIdentifiers, [picture.identifier], "Both stay selected.")
        endEvent(of: session.undoManager)

        // One undo puts both back.
        session.undoAvailability.undo()
        try await waitUntil { canvas.drawing.strokes.first?.path.first?.location == writing.path.first?.location }
        XCTAssertEqual(try XCTUnwrap(session.pictures(on: page).first).bounds, pictureBoundsBefore)
        endEvent(of: session.undoManager)

        // Deleting both is one step too.
        selection.select([0], pictures: [picture.identifier])
        selection.deleteSelection()
        try await waitUntil { canvas.drawing.strokes.isEmpty && session.pictures(on: page).isEmpty }
        endEvent(of: session.undoManager)
        session.undoAvailability.undo()
        try await waitUntil { canvas.drawing.strokes.count == 1 && session.pictures(on: page).count == 1 }
        XCTAssertNil(session.errorMessage)
    }

    func testOnADrawingTheLassoMovesInkAndPicturesTogetherAndTakesAScreenshot() async throws {
        var request = DrawingEditorRequest(target: .newDrawing(notePath: try VaultPath("Note.md"), insertionRange: NSRange(location: 0, length: 0)),
                                           title: "Circuit", initialStrokeData: PKDrawing(strokes: [stroke(from: CGPoint(x: 60, y: 90), to: CGPoint(x: 240, y: 90))]).dataRepresentation(),
                                           canvasWidth: 760, background: .white, format: .png)
        request.pictures = [DrawingBackgroundImage(imageData: try pictureData(size: CGSize(width: 200, height: 100), color: .red),
                                                   frame: CGRect(x: 40, y: 120, width: 200, height: 100))]
        var addedPictures: [(Data, String)] = []
        let destination = LassoNoteDestination(noteName: "Note") { pngData, name in addedPictures.append((pngData, name)) }
        let controller = UIHostingController(rootView: AnyView(DrawingEditor(request: request, noteDestination: destination, save: { _, _ in },
            exportCopy: { _, _ in throw CocoaError(.featureUnsupported) }, preserveDraft: { _ in }, removeDraft: {})))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        windows.append(window)
        try await waitUntil { !self.descendants(of: controller.view, matching: InfiniteCanvasView.self).isEmpty }
        let canvas = try XCTUnwrap(descendants(of: controller.view, matching: InfiniteCanvasView.self).first)
        try await waitUntil { canvas.zoomScale > 0 && canvas.bounds.width > 0 }
        let history = try XCTUnwrap(descendants(of: canvas, matching: PencilToolPickerHostView.self).first?.documentUndoManager)
        canvas.selectsInk = true
        let selection = canvas.inkSelection
        selection.selectContents(enclosedBy: loop(around: CGRect(x: 20, y: 60, width: 260, height: 180)).map { point in canvasPoint(point, on: canvas) })
        XCTAssertEqual(selection.selectedStrokeIndices, [0])
        XCTAssertEqual(selection.selectedPictureIdentifiers.count, 1)

        // The picture of the area: white paper, the red picture, the black ink.
        let image = try XCTUnwrap(selection.captureImage())
        XCTAssertEqual(image.size.width, 260, accuracy: 0.5)
        XCTAssertGreaterThan(try color(of: image, at: CGPoint(x: 120, y: 120)).red, 0.8)
        XCTAssertLessThan(try color(of: image, at: CGPoint(x: 120, y: 120)).green, 0.3)
        XCTAssertLessThan(try color(of: image, at: CGPoint(x: 100, y: 30)).red, 0.3)
        XCTAssertGreaterThan(try color(of: image, at: CGPoint(x: 250, y: 10)).green, 0.95)
        attach(image, named: "Screenshot of a drawing area")
        // Add to Note gives the note the picture's PNG, named after the drawing.
        let activity = AddToNoteActivity(destination: destination, image: image, name: canvas.lassoCaptureName)
        XCTAssertEqual(activity.activityTitle, "Add to “Note”")
        activity.perform()
        XCTAssertEqual(addedPictures.first?.1, "Circuit")
        let addedImage = try XCTUnwrap(addedPictures.first.flatMap { pngData, _ in UIImage(data: pngData) })
        XCTAssertEqual(addedImage.size.width * addedImage.scale, image.size.width * image.scale, accuracy: 1)

        // Take Screenshot offers the picture in the share sheet, at the area.
        selection.takeScreenshot()
        try await waitUntil { controller.presentedViewController is UIActivityViewController }
        try await Task.sleep(for: .seconds(1.5))
        attachScreenshot(of: canvas, named: "Share sheet of a drawing area's screenshot")
        controller.dismiss(animated: false)
        try await waitUntil { controller.presentedViewController == nil }
        XCTAssertEqual(selection.selectedPictureIdentifiers.count, 1, "The selection stays to be worked on.")

        // Moving moves both, and one undo puts both back.
        endEvent(of: history)
        let frame = try XCTUnwrap(selection.selectionFrame)
        selection.moveSelection(in: canvas.drawing, from: frame, to: frame.offsetBy(dx: 100 * canvas.zoomScale, dy: 200 * canvas.zoomScale))
        let movedPicture = try XCTUnwrap(canvas.lassoPictures().first)
        XCTAssertEqual(movedPicture.frame.minX, 140, accuracy: 1)
        XCTAssertEqual(movedPicture.frame.minY, 320, accuracy: 1)
        XCTAssertEqual(canvas.drawing.strokes.first?.path.first?.location.x ?? 0, 160, accuracy: 1)
        endEvent(of: history)
        history.undo()
        try await waitUntil { canvas.lassoPictures().first?.frame.minX == 40 }
        XCTAssertEqual(canvas.drawing.strokes.first?.path.first?.location.x ?? 0, 60, accuracy: 0.5)
    }

    func testTheLaserPointsWithoutChangingTheDocumentAndTheBarAndPaletteChooseIt() async throws {
        XCTAssertNotNil(UIImage(systemName: PencilToolKind.laser.symbolName))
        XCTAssertNotNil(UIImage(systemName: LassoShape.rectangle.symbolName))
        let (session, canvas, page) = try await openPageWithCanvas()
        try await draw([stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 100))], on: canvas, page: page, session: session)
        let drawingBefore = canvas.drawing
        try await session.save()
        let canUndoBefore = session.undoAvailability.canUndo

        // The fixed bar's laser and lasso.
        let toolPicker = PencilToolPalette.makeToolPicker()
        var laserTool = PencilToolbox.shared.selection
        laserTool.kind = .laser
        canvas.takeTool(from: toolPicker, fixedTool: laserTool)
        XCTAssertTrue(canvas.pointsWithLaser)
        XCTAssertFalse(canvas.selectsInk)
        XCTAssertFalse(canvas.isDrawingEnabled)
        var lassoTool = laserTool
        lassoTool.kind = .lasso
        canvas.takeTool(from: toolPicker, fixedTool: lassoTool)
        XCTAssertTrue(canvas.selectsInk)
        XCTAssertFalse(canvas.pointsWithLaser)
        canvas.takeTool(from: toolPicker, fixedTool: laserTool)

        // The dot follows the touch.
        let window = try XCTUnwrap(canvas.window)
        let overlay = LaserPointerOverlayView.overlay(in: window)
        XCTAssertTrue(overlay.superview === window)
        XCTAssertFalse(overlay.isUserInteractionEnabled)
        overlay.showDot(at: CGPoint(x: 300, y: 400))
        XCTAssertTrue(overlay.isShowingDot)
        XCTAssertEqual(overlay.dotCenter, CGPoint(x: 300, y: 400))
        overlay.hideDot()

        // Pressing harder broadens the core; a finger draws at the regular width.
        XCTAssertEqual(LaserPointerOverlayView.coreWidth(forPressure: nil), LaserPointerOverlayView.regularCoreWidth)
        XCTAssertLessThan(LaserPointerOverlayView.coreWidth(forPressure: 0.1), LaserPointerOverlayView.coreWidth(forPressure: 0.9))

        // Lines accumulate: each stays after its lift, and several show together.
        overlay.beginTrail(at: CGPoint(x: 200, y: 450), width: LaserPointerOverlayView.coreWidth(forPressure: 0.1))
        for step in 1...20 {
            overlay.extendTrail(to: CGPoint(x: 200 + CGFloat(step) * 12, y: 450 + CGFloat(step % 4) * 10),
                                width: LaserPointerOverlayView.coreWidth(forPressure: CGFloat(step) / 20))
        }
        overlay.endTrail()
        let firstLine = try XCTUnwrap(overlay.lines.first)
        XCTAssertGreaterThan(firstLine.widths.last ?? 0, (firstLine.widths.first ?? 0) * 2, "Width follows pressure.")
        overlay.beginTrail(at: CGPoint(x: 200, y: 560))
        overlay.extendTrail(to: CGPoint(x: 460, y: 580))
        overlay.endTrail()
        XCTAssertEqual(overlay.lines.count, 2, "Both lines show together.")
        attachScreenshot(of: canvas, named: "Laser neon lines")
        if UIAccessibility.isReduceMotionEnabled { XCTAssertFalse(overlay.isPulsing) } else { XCTAssertTrue(overlay.isPulsing, "The glow pulses gently.") }

        // They stay for a moment after the last lift, then fade together.
        try await Task.sleep(for: .seconds(LaserPointerOverlayView.idleDelay * 0.6))
        XCTAssertEqual(overlay.lines.count, 2)
        XCTAssertFalse(overlay.isFading)
        try await waitUntil { overlay.isFading }
        try await Task.sleep(for: .seconds(LaserPointerOverlayView.lineFadeDuration / 3))
        XCTAssertLessThan(overlay.linesOpacity, 1, "The lines fade together.")
        // A new line during the fade calls it off: every line is back at full strength.
        overlay.beginTrail(at: CGPoint(x: 220, y: 650))
        XCTAssertFalse(overlay.isFading)
        XCTAssertEqual(overlay.linesOpacity, 1)
        XCTAssertEqual(overlay.lines.count, 3)
        overlay.extendTrail(to: CGPoint(x: 400, y: 660))
        // While a line is drawn, nothing fades, however long.
        try await Task.sleep(for: .seconds(LaserPointerOverlayView.idleDelay + LaserPointerOverlayView.lineFadeDuration + 0.2))
        XCTAssertEqual(overlay.lines.count, 3)
        XCTAssertEqual(overlay.linesOpacity, 1)
        overlay.endTrail()
        try await waitUntil { overlay.lines.isEmpty }
        XCTAssertFalse(overlay.isPulsing)
        XCTAssertFalse(overlay.isShowingDot)

        // Nothing changed: the ink, the history, the file.
        XCTAssertEqual(canvas.drawing, drawingBefore)
        XCTAssertEqual(session.undoAvailability.canUndo, canUndoBefore)
        XCTAssertFalse(session.hasUnsavedChanges)

        // The palette's menu offers the laser; it and Select Ink are never on together.
        PaletteInkSelection.isOn = true
        PaletteInkSelection.pointsWithLaser = true
        XCTAssertFalse(PaletteInkSelection.isOn)
        let inlineMenus = PencilToolPalette.menuElements(for: toolPicker, palette: []).compactMap { element in element as? UIMenu }
        let actions = inlineMenus.flatMap(\.children).compactMap { element in element as? UIAction }
        XCTAssertEqual(actions.first { action in action.title == "Laser Pointer" }?.state, .on)
        XCTAssertEqual(actions.first { action in action.title == "Select Ink" }?.state, .off)
        let typeMenus = inlineMenus.flatMap(\.children).compactMap { element in element as? UIMenu }.map(\.title)
        XCTAssertEqual(typeMenus, ["Lasso Type", "Laser Type"])
        PaletteInkSelection.pointsWithLaser = false
    }

    func testPicturesOfAnAreaAreDrawnAtPrintResolutionWithinTheirPixelLimits() {
        XCTAssertEqual(LassoAreaCapture.pixelsPerPoint(for: CGRect(x: 0, y: 0, width: 600, height: 800), screenPixelsPerPoint: 2), 4)
        XCTAssertEqual(LassoAreaCapture.pixelsPerPoint(for: CGRect(x: 0, y: 0, width: 600, height: 800), screenPixelsPerPoint: 6), 6, "A finer screen gives a finer picture.")
        XCTAssertLessThanOrEqual(LassoAreaCapture.pixelsPerPoint(for: CGRect(x: 0, y: 0, width: 3000, height: 3000), screenPixelsPerPoint: 2) * 3000, 6_000)
        let tallScale = LassoAreaCapture.pixelsPerPoint(for: CGRect(x: 0, y: 0, width: 1400, height: 5000), screenPixelsPerPoint: 2)
        XCTAssertLessThanOrEqual(tallScale * tallScale * 1400 * 5000, LassoAreaCapture.maximumPixelCount * 1.0001)
    }

    func testACornerHandlePastThePagesEdgeStandsInsideItAndTakesTouches() async throws {
        let (session, canvas, page) = try await openPageWithCanvas()
        // Ink hanging past the page's top-left corner, as a stroke begun off the page.
        try await draw([stroke(from: CGPoint(x: -40, y: -30), to: CGPoint(x: 120, y: 80))], on: canvas, page: page, session: session)
        canvas.selectsInk = true
        canvas.inkSelection.select([0])
        let frameView = try XCTUnwrap(descendants(of: canvas, matching: SelectionFrameView.self).first)
        frameView.layoutIfNeeded()
        let frameInCanvas = frameView.frame
        XCTAssertLessThan(frameInCanvas.minX, 0, "The frame reaches past the page's edge.")
        XCTAssertLessThan(frameInCanvas.minY, 0)
        // The top-left handle stands just inside the corner and takes a touch there.
        let screenScale = screenScale(of: canvas)
        // Inside the part of the page a touch reaches: below the bars, where they cover it.
        let reachableArea = canvas.bounds.inset(by: canvas.safeAreaInsets)
        let insideCorner = CGPoint(x: reachableArea.minX + 22 / screenScale, y: reachableArea.minY + 22 / screenScale)
        let touched = try XCTUnwrap(canvas.hitTest(insideCorner, with: nil))
        XCTAssertTrue(touched.isDescendant(of: frameView) && touched !== frameView, "A handle, not the frame's middle, takes the touch.")
        attachScreenshot(of: canvas, named: "Handles of ink past the page's corner")
        _ = session
    }

    func testAHandRestingWhileThePencilWritesIsNotTakenByTheLaserOrTheLasso() {
        XCTAssertTrue(CanvasToolTouches.isHandResting(touchType: .direct, isPalmRejectionOn: true, isPencilActive: true))
        XCTAssertFalse(CanvasToolTouches.isHandResting(touchType: .direct, isPalmRejectionOn: true, isPencilActive: false), "A finger points when no Pencil is about.")
        XCTAssertFalse(CanvasToolTouches.isHandResting(touchType: .direct, isPalmRejectionOn: false, isPencilActive: true), "With palm rejection off, every finger points.")
        XCTAssertFalse(CanvasToolTouches.isHandResting(touchType: .pencil, isPalmRejectionOn: true, isPencilActive: true), "The Pencil is never a hand.")
    }

    // MARK: Pasting pictures, and the laser's glyph

    private func putImageOnPasteboard(size: CGSize, color: UIColor) throws -> Data {
        let imageData = try pictureData(size: size, color: color)
        LassoPasteboard.pasteboard.items = [[UTType.png.identifier: imageData]]
        return imageData
    }

    func testAnImageOnThePasteboardIsPastedOnAPDFPageAsAPictureWhereAskedInOneStep() async throws {
        let (session, canvas, page) = try await openPageWithCanvas()
        canvas.selectsInk = true
        let selection = canvas.inkSelection
        _ = try putImageOnPasteboard(size: CGSize(width: 400, height: 200), color: .systemGreen)
        XCTAssertTrue(LassoPasteboard.hasContent)
        endEvent(of: session.undoManager)

        // Pasted where the lasso's tap asked, at half its pixels, selected to be arranged.
        selection.paste(at: canvasPoint(CGPoint(x: 300, y: 250), on: canvas))
        try await waitUntil { session.pictures(on: page).count == 1 }
        let picture = try XCTUnwrap(canvas.lassoPictures().first)
        XCTAssertEqual(picture.frame.midX, 300, accuracy: 1)
        XCTAssertEqual(picture.frame.midY, 250, accuracy: 1)
        XCTAssertEqual(picture.frame.width, 200, accuracy: 2, "Placed on whole points.")
        XCTAssertNotNil(session.selectedPicture, "It is selected, to be moved, resized or rotated.")
        try await Task.sleep(for: .milliseconds(300))
        attachScreenshot(of: canvas, named: "Image pasted on a PDF page")
        endEvent(of: session.undoManager)
        session.undoAvailability.undo()
        try await waitUntil { session.pictures(on: page).isEmpty }
        session.selectedPicture = nil

        // A screenshot taken here is pasted at the size of its area, not twice it.
        let area = CGRect(x: 60, y: 60, width: 180, height: 90)
        selection.selectContents(enclosedBy: loop(around: area).map { point in canvasPoint(point, on: canvas) })
        let screenshot = try XCTUnwrap(selection.captureImage())
        LassoPasteboard.rememberScreenshot(screenshot)
        LassoPasteboard.pasteboard.items = [[UTType.png.identifier: try XCTUnwrap(screenshot.pngData())]]
        selection.clearSelection()
        endEvent(of: session.undoManager)
        // ⌘V puts it in the middle of the page in view.
        let coordinator = try XCTUnwrap((session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator)
        coordinator.pasteFromPasteboard()
        try await waitUntil { session.pictures(on: page).count == 1 }
        XCTAssertEqual(try XCTUnwrap(canvas.lassoPictures().first).frame.width, area.width, accuracy: 2)
        XCTAssertNil(session.errorMessage)

        // A photo copied in another app, as JPEG alone, is pasted the same way.
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        }
        LassoPasteboard.pasteboard.items = [[UTType.jpeg.identifier: try XCTUnwrap(photo.jpegData(compressionQuality: 0.9))]]
        guard case .image = LassoPasteboard.content() else { return XCTFail("A JPEG on the pasteboard is an image to paste.") }
        endEvent(of: session.undoManager)
        selection.paste(at: canvasPoint(CGPoint(x: 200, y: 600), on: canvas))
        try await waitUntil { session.pictures(on: page).count == 2 }
    }

    func testAnImageOnThePasteboardIsPastedOnADrawingWhereAsked() async throws {
        let request = DrawingEditorRequest(target: .newDrawing(notePath: try VaultPath("Note.md"), insertionRange: NSRange(location: 0, length: 0)),
                                           title: "Paste", initialStrokeData: Data(), canvasWidth: 760, background: .white, format: .png)
        let controller = UIHostingController(rootView: AnyView(DrawingEditor(request: request, save: { _, _ in },
            exportCopy: { _, _ in throw CocoaError(.featureUnsupported) }, preserveDraft: { _ in }, removeDraft: {})))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        windows.append(window)
        try await waitUntil { !self.descendants(of: controller.view, matching: InfiniteCanvasView.self).isEmpty }
        let canvas = try XCTUnwrap(descendants(of: controller.view, matching: InfiniteCanvasView.self).first)
        try await waitUntil { canvas.zoomScale > 0 && canvas.bounds.width > 0 }
        _ = try putImageOnPasteboard(size: CGSize(width: 300, height: 120), color: .systemPurple)
        canvas.selectsInk = true
        canvas.inkSelection.paste(at: canvasPoint(CGPoint(x: 400, y: 300), on: canvas))
        try await waitUntil { canvas.lassoPictures().count == 1 }
        let picture = try XCTUnwrap(canvas.lassoPictures().first)
        XCTAssertEqual(picture.frame.midX, 400, accuracy: 1)
        XCTAssertEqual(picture.frame.midY, 300, accuracy: 1)
        XCTAssertEqual(picture.frame.width, 150, accuracy: 1)
        // ⌘V too, in the middle of what is on screen.
        let host = try XCTUnwrap(descendants(of: canvas, matching: PencilToolPickerHostView.self).first)
        XCTAssertTrue(host.canPerformAction(#selector(UIResponderStandardEditActions.paste(_:)), withSender: nil))
        host.paste(nil)
        try await waitUntil { canvas.lassoPictures().count == 2 }
    }

    func testTheLaserHasAGlyphOfTheBarsFamilyAndOffersNoColors() throws {
        XCTAssertFalse(PencilToolRow.offersColors(toolInUse: .laser), "The laser offers only Dot or Line.")
        XCTAssertTrue(PencilToolRow.offersColors(toolInUse: .ink))
        XCTAssertNotNil(LaserPointerGlyph.templateImage())
        // The dot's red against the bar, white or black: at least 3:1, more with Increase Contrast.
        for isDark in [false, true] {
            for increasedContrast in [false, true] {
                let dot = UIColor(LaserPointerGlyph.dotColor(isDark: isDark, increasedContrast: increasedContrast)).cgColor
                let ratio = contrastRatio(dot, against: isDark ? .black : .white)
                XCTAssertGreaterThanOrEqual(ratio, increasedContrast ? 6 : 3, "dark \(isDark), increased contrast \(increasedContrast): \(ratio):1")
            }
        }

        // The comparison sheet for the owner: three candidates among the bar's own tool
        // glyphs, in light and dark, not in use and in use.
        let toolbox = PencilToolbox(defaults: UserDefaults(suiteName: "LaserGlyphSheet-\(UUID().uuidString)")!)
        func row(candidate: String?, isDark: Bool) -> some View {
            HStack(spacing: 2) {
                ForEach(Array(toolbox.presets.enumerated()), id: \.element.id) { presetIndex, preset in
                    PencilToolGlyph(tool: .ink(preset.ink), inkHex: preset.colorHex, isInUse: presetIndex == 0)
                }
                PencilToolGlyph(tool: .eraser, isInUse: false)
                PencilToolGlyph(tool: .lasso, isInUse: false)
                ForEach([false, true], id: \.self) { isInUse in
                    Group {
                        if let candidate {
                            VStack(spacing: 3) {
                                Image(systemName: candidate)
                                    .font(.system(size: 17, weight: isInUse ? .semibold : .regular))
                                    .foregroundStyle(isInUse ? .primary : .secondary)
                                    .frame(height: 22)
                                Capsule().fill(.clear).frame(width: 16, height: 3)
                            }
                        } else {
                            VStack(spacing: 3) {
                                LaserPointerGlyph(isInUse: isInUse).frame(height: 22)
                                Capsule().fill(.clear).frame(width: 16, height: 3)
                            }
                        }
                    }
                    .frame(width: PencilToolbarMetrics.buttonSide, height: PencilToolbarMetrics.buttonSide)
                    .background(isInUse ? PencilToolbarMetrics.selectedFill : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius, style: .continuous))
                }
                Text(candidate ?? "Custom pointer").font(.footnote).foregroundStyle(.secondary).padding(.leading, 12).frame(width: 190, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(height: PencilToolbarMetrics.height)
            .background(isDark ? Color.black : Color.white)
            .environment(\.colorScheme, isDark ? .dark : .light)
        }
        let sheet = VStack(spacing: 0) {
            ForEach([false, true], id: \.self) { isDark in
                ForEach([nil, "cursorarrow.rays", "hand.point.up.left"] as [String?], id: \.self) { candidate in row(candidate: candidate, isDark: isDark) }
            }
        }
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        attach(image, named: "laser-icon-options")
    }
}
#endif
