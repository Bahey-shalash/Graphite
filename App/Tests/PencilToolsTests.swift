#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import PDFKit
import ImageIO
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// The shape tool, pen presets, Pencil double-tap in notes, and drawing on images.
@MainActor
final class PencilToolsTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var temporaryLocations: [URL] = []
    private var savedShapesPreference: Any?

    override func setUp() async throws {
        savedShapesPreference = UserDefaults.standard.object(forKey: PDFAnnotationPreferenceKey.drawsShapes)
    }

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        for location in temporaryLocations { try? FileManager.default.removeItem(at: location) }
        temporaryLocations = []
        if let savedShapesPreference { UserDefaults.standard.set(savedShapesPreference, forKey: PDFAnnotationPreferenceKey.drawsShapes) }
        else { UserDefaults.standard.removeObject(forKey: PDFAnnotationPreferenceKey.drawsShapes) }
        // A test that stops early must not leave double-tap turned off on the simulator.
        UserDefaults.standard.removeObject(forKey: "GraphiteDrawsOnPencilDoubleTap")
    }

    // MARK: Lasso

    /// PencilKit's lasso selection is a text input inside the canvas that makes itself
    /// first responder. `SelectionStandIn` takes its place: the real one needs a drag.
    func testLassoSelectionDoesNotRaiseTheKeyboardOrTakeThePaletteFromTheDocument() async throws {
        final class SelectionStandIn: UIView, UIKeyInput {
            var hasText: Bool { false }
            func insertText(_ text: String) {}
            func deleteBackward() {}
            override var canBecomeFirstResponder: Bool { true }
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 600))
        windows.append(window)
        let canvas = HistoryCanvasView(frame: window.bounds)
        let toolPickerHost = PencilToolPickerHostView()
        toolPickerHost.canvases = { [canvas] }
        let selection = SelectionStandIn(frame: CGRect(x: 10, y: 10, width: 50, height: 50))
        let searchField = UITextField(frame: CGRect(x: 0, y: 500, width: 200, height: 40))
        canvas.addSubview(selection)
        window.addSubview(canvas)
        window.addSubview(toolPickerHost)
        window.addSubview(searchField)
        window.makeKeyAndVisible()

        let selectionInputView = try XCTUnwrap(selection.inputView, "The selection uses the canvas's input view instead of the keyboard.")
        XCTAssertTrue(selectionInputView === canvas.inputView)
        XCTAssertEqual(selectionInputView.bounds.height, 0)
        XCTAssertNil(toolPickerHost.inputView)

        XCTAssertTrue(toolPickerHost.becomeFirstResponder())
        XCTAssertTrue(selection.becomeFirstResponder())
        XCTAssertTrue(canvas.containsFirstResponder)
        try await waitUntil { toolPickerHost.isFirstResponder }
        XCTAssertFalse(canvas.containsFirstResponder, "The palette's Undo and Redo stay with the document while strokes are selected.")

        XCTAssertTrue(searchField.becomeFirstResponder())
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(searchField.isFirstResponder, "Only a selection inside a canvas gives first responder back.")

        XCTAssertTrue(toolPickerHost.becomeFirstResponder())
        toolPickerHost.takesFirstResponderBackFromSelections = false
        XCTAssertTrue(selection.becomeFirstResponder())
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(selection.isFirstResponder, "A host told to give up first responder lets go.")
        selection.resignFirstResponder()
    }

    func testHistoryKeepsTheLassoToolAndPutsAMovedStrokeBackAndForth() throws {
        let original = stroke(through: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 40), CGPoint(x: 140, y: 20)])
        // The lasso moves a stroke by changing its transform; to PencilKit it is the same stroke.
        var moved = original
        moved.transform = CGAffineTransform(translationX: 100, y: 0)
        let drawingBefore = PKDrawing(strokes: [original]), drawingAfter = PKDrawing(strokes: [moved])
        let change = try XCTUnwrap(PencilDrawingChange(from: drawingBefore, to: drawingAfter))

        let canvas = HistoryCanvasView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        canvas.tool = PKLassoTool()
        canvas.drawing = drawingAfter
        let reverted = try XCTUnwrap(change.reverting(canvas.drawing))
        canvas.showDrawingFromHistory(reverted)
        XCTAssertTrue(canvas.tool is PKLassoTool, "Ending the selection leaves the lasso selected.")
        XCTAssertEqual(canvas.drawing.strokes.map(\.transform), [.identity])
        XCTAssertEqual(canvas.recordedDrawing.strokes.count, 1)

        // The strokes history puts back are new strokes that look the same, so the next
        // step of the history still recognizes them.
        let redone = try XCTUnwrap(change.reapplying(to: canvas.drawing))
        canvas.showDrawingFromHistory(redone)
        XCTAssertEqual(canvas.drawing.strokes.map(\.transform), [CGAffineTransform(translationX: 100, y: 0)])
        XCTAssertEqual(canvas.drawing.strokes.first?.randomSeed, original.randomSeed)
        XCTAssertEqual(canvas.drawing.strokes.first?.path.creationDate, original.path.creationDate)
        XCTAssertNotNil(change.reverting(canvas.drawing), "Undo works again after redo.")
    }

    // MARK: Shapes


    func testRoundStrokeBecomesACircleInTheSameInkAndHandwritingStaysAsDrawn() throws {
        let wobblyCircle = stroke(through: circlePoints(center: CGPoint(x: 200, y: 200), radius: 70), color: .blue)
        let shape = try XCTUnwrap(PencilShapes.shapeStroke(for: wobblyCircle))
        XCTAssertEqual(shape.ink.inkType, wobblyCircle.ink.inkType)
        XCTAssertEqual(shape.ink.color, wobblyCircle.ink.color)
        for point in shape.path.interpolatedPoints(by: .distance(10)) {
            XCTAssertEqual(hypot(point.location.x - 200, point.location.y - 200), 70, accuracy: 6, "Every point lies on the circle.")
        }
        let cursive = stroke(through: (0...60).map { pointIndex in CGPoint(x: 40 + Double(pointIndex) * 5, y: 300 + 22 * sin(Double(pointIndex) * 0.4)) })
        XCTAssertNil(PencilShapes.shapeStroke(for: cursive))

        let existing = stroke(through: [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 60), CGPoint(x: 40, y: 20), CGPoint(x: 70, y: 70), CGPoint(x: 90, y: 30)])
        let before = PKDrawing(strokes: [existing])
        let shaped = try XCTUnwrap(PencilShapes.replacingNewStroke(in: PKDrawing(strokes: [existing, wobblyCircle]), previousDrawing: before))
        XCTAssertEqual(shaped.strokes.count, 2)
        XCTAssertEqual(shaped.strokes[0].path.count, existing.path.count, "Earlier strokes are untouched.")
        XCTAssertNil(PencilShapes.replacingNewStroke(in: before, previousDrawing: before), "Nothing new, nothing replaced.")
    }

    func testShapeToolOnAPDFPageIsOneUndoStep() async throws {
        UserDefaults.standard.set(true, forKey: PDFAnnotationPreferenceKey.drawsShapes)
        let location = FileManager.default.temporaryDirectory.appendingPathComponent("Shapes-\(UUID().uuidString).pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank)).write(to: location)
        temporaryLocations.append(location)
        let session = try await PDFSession.open(location)
        _ = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let page = try XCTUnwrap(session.document.page(at: 0))
        func coordinator() -> PDFAnnotationCoordinator? { (session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator }
        try await waitUntil { coordinator()?.editingCanvas(for: page) != nil }
        let canvas = try XCTUnwrap(coordinator()?.editingCanvas(for: page))

        let drawnStroke = stroke(through: circlePoints(center: CGPoint(x: 200, y: 200), radius: 60))
        canvas.drawing = PKDrawing(strokes: [drawnStroke])
        try await waitUntil { page.annotations.contains { annotation in annotation.type == "Ink" } }
        let shapeStroke = try XCTUnwrap(canvas.drawing.strokes.first)
        XCTAssertNotEqual(shapeStroke.path.count, drawnStroke.path.count, "The canvas shows the circle, not the wobbly stroke.")
        XCTAssertEqual(page.annotations.filter { annotation in annotation.type == "Ink" }.count, 1)
        try await waitUntil { session.undoAvailability.canUndo }

        session.undoAvailability.undo()
        try await waitUntil { page.annotations.filter { annotation in annotation.type == "Ink" }.isEmpty }
        XCTAssertTrue(canvas.drawing.strokes.isEmpty, "One undo removes the shape; the wobbly stroke does not come back as a second step.")
        XCTAssertFalse(session.undoAvailability.canUndo)

        // With the tool off, the same stroke stays as drawn.
        UserDefaults.standard.set(false, forKey: PDFAnnotationPreferenceKey.drawsShapes)
        try await Task.sleep(for: .milliseconds(200))
        canvas.drawing = PKDrawing(strokes: [drawnStroke])
        try await waitUntil { page.annotations.contains { annotation in annotation.type == "Ink" } }
        XCTAssertEqual(canvas.drawing.strokes.first?.path.count, drawnStroke.path.count)
    }

    func testHoldingAtTheEndOfAStrokeShowsItsShapeWhichTakesTheStrokesPlaceOnLift() async throws {
        UserDefaults.standard.set(false, forKey: PDFAnnotationPreferenceKey.drawsShapes)
        let location = FileManager.default.temporaryDirectory.appendingPathComponent("Hold-\(UUID().uuidString).pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank)).write(to: location)
        temporaryLocations.append(location)
        let session = try await PDFSession.open(location)
        _ = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let page = try XCTUnwrap(session.document.page(at: 0))
        func coordinator() -> PDFAnnotationCoordinator? { (session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator }
        try await waitUntil { coordinator()?.editingCanvas(for: page) != nil }
        let canvas = try XCTUnwrap(coordinator()?.editingCanvas(for: page))
        func inkAnnotationCount() -> Int { page.annotations.filter { annotation in annotation.type == "Ink" }.count }

        // The canvas watches its strokes without coming between PencilKit and the touch.
        let holdRecognizer = try XCTUnwrap(canvas.gestureRecognizers?.compactMap { recognizer in recognizer as? StrokeHoldRecognizer }.first)
        XCTAssertFalse(holdRecognizer.cancelsTouchesInView)
        XCTAssertFalse(holdRecognizer.delaysTouchesBegan)
        XCTAssertFalse(holdRecognizer.canPrevent(canvas.drawingGestureRecognizer))
        XCTAssertFalse(holdRecognizer.canBePrevented(by: canvas.drawingGestureRecognizer))

        // A hold at the end of handwriting shows nothing, and the writing stays as drawn.
        let cursivePoints = (0...60).map { pointIndex in CGPoint(x: 40 + Double(pointIndex) * 5, y: 420 + 22 * sin(Double(pointIndex) * 0.4)) }
        canvas.strokeTouchDidRest(afterStrokeThrough: cursivePoints)
        XCTAssertFalse(canvas.isShowingShapePreview)
        canvas.strokeTouchDidEnd(wasCancelled: false)
        let cursive = stroke(through: cursivePoints, color: .purple, width: 3.3)
        canvas.tool = PKInkingTool(.pen, color: .purple, width: 7.7)
        XCTAssertNil(HistoryCanvasView.footprint(of: PKInkingTool(.pen, color: .purple, width: 7.7)), "No stroke has been drawn with this tool yet.")
        canvas.drawing = PKDrawing(strokes: [cursive])
        try await waitUntil { inkAnnotationCount() == 1 }
        XCTAssertEqual(canvas.drawing.strokes.first?.path.count, cursive.path.count)
        endEvent(of: session.undoManager)

        // With a tool that has not drawn yet, a hold at the end of a round stroke shows the
        // circle over the stroke PencilKit is still drawing.
        canvas.tool = PKInkingTool(.pen, color: .purple, width: 9.9)
        let roundPoints = circlePoints(center: CGPoint(x: 200, y: 200), radius: 60)
        canvas.strokeTouchDidRest(afterStrokeThrough: roundPoints)
        XCTAssertTrue(canvas.isShowingShapePreview)
        // Drawing on withdraws it, and the stroke then stays as drawn.
        canvas.strokeTouchDidMove(to: CGPoint(x: 300, y: 300), leftRestingPlace: true)
        XCTAssertFalse(canvas.isShowingShapePreview)
        canvas.strokeTouchDidEnd(wasCancelled: false)

        // Lifting while it shows replaces the stroke with the circle, as one undo step.
        canvas.strokeTouchDidRest(afterStrokeThrough: roundPoints)
        canvas.strokeTouchDidMove(to: CGPoint(x: 261, y: 216), leftRestingPlace: false)
        canvas.strokeTouchDidEnd(wasCancelled: false)
        XCTAssertTrue(canvas.isShowingShapePreview, "The shape stays until the stroke arrives.")
        let roundStroke = stroke(through: roundPoints, color: .purple, width: 3.3)
        canvas.drawing = PKDrawing(strokes: [cursive, roundStroke])
        try await waitUntil { canvas.drawing.strokes.count == 2 && !canvas.isShowingShapePreview }
        let circle = try XCTUnwrap(canvas.drawing.strokes.last)
        XCTAssertNotEqual(circle.path.count, roundStroke.path.count, "The canvas shows the circle, not the wobbly stroke.")
        for point in circle.path.interpolatedPoints(by: .distance(10)) {
            XCTAssertEqual(hypot(point.location.x - 200, point.location.y - 200), 60, accuracy: 6)
        }
        endEvent(of: session.undoManager)
        session.undoAvailability.undo()
        try await waitUntil { canvas.drawing.strokes.count == 1 }
        XCTAssertEqual(canvas.drawing.strokes.first?.path.count, cursive.path.count, "One undo removes the circle; the wobbly stroke does not come back.")

        // The hold is used up: the same stroke, not held, stays as drawn.
        canvas.drawing = PKDrawing(strokes: [cursive, roundStroke])
        try await waitUntil { inkAnnotationCount() == 2 }
        XCTAssertEqual(canvas.drawing.strokes.last?.path.count, roundStroke.path.count)
        endEvent(of: session.undoManager)

        // That stroke told the canvas how the tool marks the page. From then on the hand can
        // move on after a hold to stretch the shape: PencilKit's own stroke is discarded, so
        // none arrives, and the canvas adds the shape when the touch lifts.
        let footprint = try XCTUnwrap(HistoryCanvasView.footprint(of: PKInkingTool(.pen, color: .purple, width: 9.9)))
        XCTAssertEqual(footprint.size.width, 3.3, accuracy: 0.01, "A tool's width setting is not what it draws.")
        let squarePoints = [CGPoint(x: 300, y: 500), CGPoint(x: 400, y: 500), CGPoint(x: 400, y: 600), CGPoint(x: 300, y: 600), CGPoint(x: 300, y: 503)]
            .reduce(into: [CGPoint]()) { points, corner in
                guard let last = points.last else { return points.append(corner) }
                points += (1...20).map { step in CGPoint(x: last.x + (corner.x - last.x) * Double(step) / 20, y: last.y + (corner.y - last.y) * Double(step) / 20) }
            }
        canvas.strokeTouchDidRest(afterStrokeThrough: squarePoints)
        XCTAssertTrue(canvas.isShowingShapePreview)
        // A resting hand trembles without moving the shape; leaving the rest drags it, here
        // to twice the distance from the square's middle.
        canvas.strokeTouchDidMove(to: CGPoint(x: 301, y: 502), leftRestingPlace: false)
        canvas.strokeTouchDidMove(to: CGPoint(x: 280, y: 480), leftRestingPlace: true)
        canvas.strokeTouchDidMove(to: CGPoint(x: 250, y: 450), leftRestingPlace: false)
        canvas.strokeTouchDidEnd(wasCancelled: false)
        XCTAssertFalse(canvas.isShowingShapePreview)
        try await waitUntil { inkAnnotationCount() == 3 }
        let square = try XCTUnwrap(canvas.drawing.strokes.last)
        XCTAssertEqual(square.ink.inkType, .pen)
        XCTAssertEqual(square.path.first?.size.width ?? 0, 3.3, accuracy: 0.01, "The shape is drawn as the tool draws.")
        let squareBounds = square.path.reduce(CGRect.null) { bounds, point in bounds.union(CGRect(origin: point.location, size: .zero)) }
        XCTAssertEqual(squareBounds.midX, 350, accuracy: 3)
        XCTAssertEqual(squareBounds.midY, 550, accuracy: 3)
        XCTAssertEqual(squareBounds.width, 200, accuracy: 8, "Dragged to twice its size about its middle.")
        XCTAssertEqual(squareBounds.height, 200, accuracy: 8)
        endEvent(of: session.undoManager)
        session.undoAvailability.undo()
        try await waitUntil { canvas.drawing.strokes.count == 2 }

        // A cancelled touch leaves neither the stroke, which was discarded, nor a shape.
        canvas.strokeTouchDidRest(afterStrokeThrough: squarePoints)
        canvas.strokeTouchDidMove(to: CGPoint(x: 250, y: 450), leftRestingPlace: true)
        canvas.strokeTouchDidEnd(wasCancelled: true)
        XCTAssertFalse(canvas.isShowingShapePreview)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(canvas.drawing.strokes.count, 2)

        // Turned off in Settings, no touch is watched.
        let drawingTouch = UITouch()
        XCTAssertTrue(holdRecognizer.tracksTouch(drawingTouch) || !canvas.drawingGestureRecognizer.allowedTouchTypes.contains(NSNumber(value: drawingTouch.type.rawValue)))
        UserDefaults.standard.set(false, forKey: StrokeHoldPreference.key)
        defer { UserDefaults.standard.removeObject(forKey: StrokeHoldPreference.key) }
        XCTAssertFalse(holdRecognizer.tracksTouch(drawingTouch))
    }

    func testDrawingEditorUsesItsOwnHistoryAndTheShapeTool() async throws {
        UserDefaults.standard.set(true, forKey: PDFAnnotationPreferenceKey.drawsShapes)
        let request = DrawingEditorRequest(target: .newDrawing(notePath: try VaultPath("Note.md"), insertionRange: NSRange(location: 0, length: 0)),
                                           title: "New Drawing", initialStrokeData: Data(), canvasWidth: nil, background: .white, format: .png)
        let controller = try host(AnyView(DrawingEditor(request: request, save: { _, _ in },
            exportCopy: { _, _ in throw CocoaError(.featureUnsupported) }, preserveDraft: { _ in }, removeDraft: {})))
        try await waitUntil { !self.descendants(of: controller.view, matching: InfiniteCanvasView.self).isEmpty }
        let canvas = try XCTUnwrap(descendants(of: controller.view, matching: InfiniteCanvasView.self).first)
        let toolPickerHost = try XCTUnwrap(descendants(of: controller.view, matching: PencilToolPickerHostView.self).first)
        let history = try XCTUnwrap(toolPickerHost.undoManager)
        XCTAssertFalse(history === canvas.undoManager, "PencilKit's own steps are not the drawing's history.")
        XCTAssertFalse(history === canvas.window?.undoManager)

        let drawnStroke = stroke(through: [CGPoint(x: 100, y: 100), CGPoint(x: 160, y: 102), CGPoint(x: 220, y: 99), CGPoint(x: 280, y: 103), CGPoint(x: 340, y: 100), CGPoint(x: 400, y: 101)])
        canvas.drawing = PKDrawing(strokes: [drawnStroke])
        try await waitUntil { history.canUndo }
        let line = try XCTUnwrap(canvas.drawing.strokes.first)
        let lineHeights = line.path.interpolatedPoints(by: .distance(20)).map(\.location.y)
        XCTAssertEqual(lineHeights.max() ?? 0, lineHeights.min() ?? 1, accuracy: 0.01, "A nearly level stroke becomes a level line.")
        endEvent(of: history)
        history.undo()
        try await waitUntil { canvas.drawing.strokes.isEmpty }
        history.redo()
        try await waitUntil { canvas.drawing.strokes.count == 1 }
        attachScreenshot(of: controller, named: "Drawing editor with a shape")
    }

    // MARK: Palette

    func testPaletteHasEveryToolOnceAndTheColorsAndShapesButton() throws {
        let toolPicker = PencilToolPalette.makeToolPicker()
        let inkTypes = toolPicker.toolItems.compactMap { item in (item as? PKToolPickerInkingItem)?.inkingTool.inkType }
        XCTAssertEqual(Set(inkTypes).count, inkTypes.count, "No pen appears twice.")
        for inkType in [PKInkingTool.InkType.pen, .monoline, .marker, .pencil, .crayon, .fountainPen, .watercolor] {
            XCTAssertTrue(inkTypes.contains(inkType), "Missing \(inkType.rawValue)")
        }
        XCTAssertTrue(toolPicker.toolItems.contains { item in item is PKToolPickerEraserItem })
        XCTAssertTrue(toolPicker.toolItems.contains { item in item is PKToolPickerLassoItem })
        XCTAssertTrue(toolPicker.toolItems.contains { item in item is PKToolPickerRulerItem })
        XCTAssertFalse(toolPicker.showsDrawingPolicyControls)
        XCTAssertNotNil(toolPicker.stateAutosaveName, "The tools keep their colors and widths between launches.")

        UserDefaults.standard.set(false, forKey: PDFAnnotationPreferenceKey.drawsShapes)
        let accessoryItem = PencilToolPalette.makeAccessoryItem(for: toolPicker)
        let accessoryButton = try XCTUnwrap(accessoryItem.customView as? UIButton)
        XCTAssertNotNil(accessoryButton.menu)
        XCTAssertTrue(accessoryButton.showsMenuAsPrimaryAction)
        XCTAssertFalse(accessoryButton.isSelected)
        XCTAssertEqual(accessoryButton.accessibilityValue, "Shapes off")
        PencilToolPalette.updateShapesButton(accessoryItem, isOn: true)
        XCTAssertTrue(accessoryButton.isSelected)
        XCTAssertEqual(accessoryButton.accessibilityValue, "Shapes on", "The state is announced, not shown by color alone.")

        // The menu: the favorite colors, then the Draw Shapes switch showing the preference.
        let elements = PencilToolPalette.menuElements(for: toolPicker, palette: [PaletteColor(name: "red", hex: "#e93147")])
        XCTAssertEqual(elements.count, 2)
        let shapesSwitch = try XCTUnwrap((elements.last as? UIMenu)?.children.first as? UIAction)
        XCTAssertEqual(shapesSwitch.title, "Draw Shapes")
        XCTAssertEqual(shapesSwitch.state, .off)
        UserDefaults.standard.set(true, forKey: PDFAnnotationPreferenceKey.drawsShapes)
        let elementsWithShapesOn = PencilToolPalette.menuElements(for: toolPicker, palette: [])
        XCTAssertEqual(((elementsWithShapesOn.last as? UIMenu)?.children.first as? UIAction)?.state, .on)
    }

    func testFavoriteColorGoesToTheToolInUseAndKeepsItsKindWidthAndOpacity() throws {
        let toolPicker = PencilToolPalette.makeToolPicker()
        // The test must not change the tools the simulator's app remembers.
        toolPicker.stateAutosaveName = nil
        let favorites = [PaletteColor(name: "red", hex: "#e93147"), PaletteColor(name: "blue", hex: "#086ddd")]
        func swatches() throws -> [UIAction] {
            try XCTUnwrap(PencilToolPalette.favoriteColorsMenu(for: toolPicker, palette: favorites).children as? [UIAction])
        }
        let marker = try XCTUnwrap(toolPicker.toolItems.first { item in (item as? PKToolPickerInkingItem)?.inkingTool.inkType == .marker })
        toolPicker.selectedToolItemIdentifier = marker.identifier
        let markerBefore = try XCTUnwrap(PencilToolPalette.inkingToolInUse(of: toolPicker))
        XCTAssertEqual(try swatches().map(\.title), ["red", "blue"])
        XCTAssertTrue(try swatches().allSatisfy { swatch in swatch.state == .off && !swatch.attributes.contains(.disabled) })

        PencilToolPalette.applyColor(try XCTUnwrap(UIColor(graphiteHex: "#086ddd")), to: toolPicker)
        let markerAfter = try XCTUnwrap(PencilToolPalette.inkingToolInUse(of: toolPicker))
        XCTAssertEqual(markerAfter.inkType, .marker)
        XCTAssertEqual(markerAfter.width, markerBefore.width)
        XCTAssertEqual(markerAfter.color.cgColor.alpha, markerBefore.color.cgColor.alpha, accuracy: 0.001, "A highlighter stays see-through.")
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        markerAfter.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 0x08 / 255.0, accuracy: 0.01); XCTAssertEqual(green, 0x6d / 255.0, accuracy: 0.01); XCTAssertEqual(blue, 0xdd / 255.0, accuracy: 0.01)
        XCTAssertEqual(try swatches().map(\.state), [.off, .on], "The menu marks the color in use.")

        // The other tools keep their colors.
        let pen = try XCTUnwrap(toolPicker.toolItems.first { item in (item as? PKToolPickerInkingItem)?.inkingTool.inkType == .pen })
        toolPicker.selectedToolItemIdentifier = pen.identifier
        XCTAssertEqual(try swatches().map(\.state), [.off, .off])

        // The eraser takes no color.
        let eraser = try XCTUnwrap(toolPicker.toolItems.first { item in item is PKToolPickerEraserItem })
        toolPicker.selectedToolItemIdentifier = eraser.identifier
        XCTAssertTrue(try swatches().allSatisfy { swatch in swatch.attributes.contains(.disabled) })
        PencilToolPalette.applyColor(.red, to: toolPicker)
        XCTAssertEqual(toolPicker.selectedToolItemIdentifier, eraser.identifier)

        let emptyList = PencilToolPalette.favoriteColorsMenu(for: toolPicker, palette: [])
        XCTAssertEqual((emptyList.children.first as? UIAction)?.title, "Add colors in Settings › Colors")
    }

    // MARK: Drawing on images

    func testPictureIsPreparedUprightAtCanvasWidth() throws {
        let photograph = try imageData(size: CGSize(width: 3000, height: 2000), color: .systemRed)
        let picture = try DrawingPictures.picture(from: photograph, canvasWidth: 760)
        XCTAssertEqual(picture.frame.width, 760)
        XCTAssertEqual(picture.frame.height, 760 * 2000 / 3000, accuracy: 0.5)
        let decoded = try XCTUnwrap(UIImage(data: picture.imageData)?.cgImage)
        XCTAssertLessThanOrEqual(decoded.width, 1520, "The picture is kept at the sharpness a saved drawing has.")
        XCTAssertTrue(picture.hasValidGeometry)
        XCTAssertThrowsError(try DrawingPictures.picture(from: Data("not an image".utf8), canvasWidth: 760))
    }

    func testDrawingOnAnImageSavesAnOrdinaryPNGThatCanBeEditedAgain() async throws {
        let picture = try DrawingPictures.picture(from: try imageData(size: CGSize(width: 1200, height: 800), color: .systemRed), canvasWidth: 760)
        let ink = PKDrawing(strokes: [stroke(through: [CGPoint(x: 100, y: 250), CGPoint(x: 300, y: 250), CGPoint(x: 500, y: 250), CGPoint(x: 660, y: 250)], width: 14)])
        let service = DrawingFileService()
        let content = DrawingContent(strokeData: ink.dataRepresentation(), canvasWidth: 760, background: .white, backgroundImage: picture)
        let fileData = try await service.fileData(for: content, format: .png)

        // Any image reader sees the picture with the ink over it.
        let decoded = try XCTUnwrap(UIImage(data: fileData)?.cgImage)
        XCTAssertEqual(Double(decoded.width) / Double(decoded.height), 1200.0 / 800.0, accuracy: 0.01, "The file has the picture's proportions.")
        let pictureColor = try color(of: decoded, atFractionX: 0.5, fractionY: 0.85)
        XCTAssertGreaterThan(pictureColor.red, 0.7); XCTAssertLessThan(pictureColor.green, 0.45)
        let inkColor = try color(of: decoded, atFractionX: 0.5, fractionY: 250.0 / picture.frame.height)
        XCTAssertLessThan(inkColor.red, 0.35, "The stroke covers the picture.")

        // Graphite reads the ink and the picture back.
        let reading = try DrawingMetadataReader.readMetadata(fileData, format: .png)
        let payload = try XCTUnwrap(reading.payload)
        XCTAssertEqual(payload.version, 2)
        XCTAssertEqual(try PKDrawing(data: payload.strokes).strokes.count, 1)
        XCTAssertEqual(payload.backgroundImage?.frame.width, 760)
        XCTAssertEqual(payload.backgroundImage?.imageData, picture.imageData)

        // The vector formats hold the picture too (`VectorDrawingPicturesTests` compares what they show).
        for format in [DrawingFormat.svg, .pdf] {
            let vectorData = try await service.fileData(for: content, format: format)
            let vectorPayload = try XCTUnwrap(DrawingMetadataReader.readMetadata(vectorData, format: format).payload)
            XCTAssertEqual(vectorPayload.backgroundImage, payload.backgroundImage)
            XCTAssertEqual(vectorPayload.version, 2)
        }
        // The draft kept while the app is in the background keeps the picture too.
        let draft = try await service.draftFileData(for: content)
        XCTAssertEqual(try DrawingMetadataReader.readMetadata(draft, format: .svg).payload?.backgroundImage, picture)
    }

    func testEditorShowsThePictureUnderTheInkAndOpensAtItsTop() async throws {
        // Narrower than the screen, so the editor zooms in to fit the width.
        let picture = try DrawingPictures.picture(from: try imageData(size: CGSize(width: 1200, height: 800), color: .systemRed), canvasWidth: 400)
        var request = DrawingEditorRequest(target: .drawingOnImage(imagePath: try VaultPath("Diagram.png"), notePath: nil),
                                           title: "Diagram.png", initialStrokeData: Data(), canvasWidth: 400, background: .white, format: .png)
        request.backgroundImage = picture
        let controller = try host(AnyView(DrawingEditor(request: request, save: { _, _ in },
            exportCopy: { _, _ in throw CocoaError(.featureUnsupported) }, preserveDraft: { _ in }, removeDraft: {})))
        try await waitUntil { !self.descendants(of: controller.view, matching: InfiniteCanvasView.self).isEmpty }
        let canvas = try XCTUnwrap(descendants(of: controller.view, matching: InfiniteCanvasView.self).first)
        try await waitUntil { canvas.zoomScale > 1 }

        // PencilKit paints an opaque canvas's paper over the picture.
        XCTAssertFalse(canvas.isOpaque)
        XCTAssertEqual(canvas.backgroundColor, .clear)
        let pictureView = try XCTUnwrap(descendants(of: canvas, matching: UIImageView.self).first { imageView in imageView.accessibilityLabel == "Image being drawn on" })
        XCTAssertEqual(pictureView.frame.minY, 0)
        XCTAssertEqual(pictureView.frame.width, canvas.bounds.width, accuracy: 1, "The picture fills the width.")
        XCTAssertEqual(canvas.contentOffset.y, -canvas.adjustedContentInset.top, accuracy: 0.5, "The top of the picture is below the navigation bar, not under it.")
        attachScreenshot(of: controller, named: "Drawing editor with a picture")
    }

    func testDrawingOnANotesImageKeepsTheOriginalAndRewritesTheEmbeds() async throws {
        let noteText = "# Lecture\n\n![[Diagram.png|300]]\n\nSee also ![](Diagram.png) again.\n"
        let (workspace, directory) = try await makeWorkspace(notes: ["Lecture.md": noteText])
        let originalImage = try imageData(size: CGSize(width: 900, height: 600), color: .systemGreen)
        try originalImage.write(to: directory.appendingPathComponent("Diagram.png"))
        let notePath = try VaultPath("Lecture.md"), imagePath = try VaultPath("Diagram.png")
        await workspace.open(notePath)
        let session = try XCTUnwrap(workspace.markdownSession)

        await workspace.beginDrawingOnImage(at: imagePath, fromNote: notePath)
        let request = try XCTUnwrap(workspace.drawingEditorRequest)
        guard case .drawingOnImage(let requestImage, let requestNote) = request.target else { return XCTFail("Not a drawing on an image") }
        XCTAssertEqual(requestImage, imagePath); XCTAssertEqual(requestNote, notePath)
        XCTAssertEqual(request.format, workspace.preferences.drawingFormat, "A drawing on an image takes the format new drawings take.")
        XCTAssertEqual(request.confirmationTitle, "Done")
        let picture = try XCTUnwrap(request.backgroundImage)
        XCTAssertEqual(picture.frame, CGRect(x: 0, y: 0, width: 760, height: 760 * 600 / 900.0))

        let ink = PKDrawing(strokes: [stroke(through: [CGPoint(x: 80, y: 120), CGPoint(x: 240, y: 140), CGPoint(x: 420, y: 110)])])
        try await workspace.saveDrawing(DrawingContent(strokeData: ink.dataRepresentation(), canvasWidth: 760, background: .white, backgroundImage: picture),
                                        format: .png, for: request)

        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("Diagram.png")), originalImage, "The original image is never changed.")
        let annotatedLocation = directory.appendingPathComponent("Diagram annotated.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: annotatedLocation.path))
        XCTAssertEqual(session.text, "# Lecture\n\n![[Diagram annotated.png|300]]\n\nSee also ![](Diagram%20annotated.png) again.\n",
                       "Each embed keeps its style and size.")
        XCTAssertNil(workspace.errorMessage)

        // The annotated file opens for editing with its ink and its picture.
        workspace.drawingEditorRequest = nil
        await workspace.beginEditingDrawing(at: try VaultPath("Diagram annotated.png"))
        let editingRequest = try XCTUnwrap(workspace.drawingEditorRequest)
        XCTAssertEqual(try PKDrawing(data: editingRequest.initialStrokeData).strokes.count, 1)
        XCTAssertNotNil(editingRequest.backgroundImage)
        // Asking to draw on it again edits the same drawing instead of stacking pictures.
        workspace.drawingEditorRequest = nil
        await workspace.beginDrawingOnImage(at: try VaultPath("Diagram annotated.png"), fromNote: notePath)
        guard case .existingDrawing = try XCTUnwrap(workspace.drawingEditorRequest).target else { return XCTFail("A drawing opens as itself") }
    }

    func testDrawingOnAStandaloneImageSavesBesideItAndOpensTheResult() async throws {
        let (workspace, directory) = try await makeWorkspace(notes: [:])
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Scans"), withIntermediateDirectories: true)
        try imageData(size: CGSize(width: 400, height: 400), color: .systemBlue).write(to: directory.appendingPathComponent("Scans/Page.jpg"))
        let imagePath = try VaultPath("Scans/Page.jpg")
        await workspace.beginDrawingOnImage(at: imagePath, fromNote: nil)
        let request = try XCTUnwrap(workspace.drawingEditorRequest)
        let ink = PKDrawing(strokes: [stroke(through: [CGPoint(x: 80, y: 120), CGPoint(x: 240, y: 140), CGPoint(x: 420, y: 110)])])
        try await workspace.saveDrawing(DrawingContent(strokeData: ink.dataRepresentation(), canvasWidth: 760, background: .white,
                                                       backgroundImage: request.backgroundImage), format: .png, for: request)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Scans/Page annotated.png").path))
        XCTAssertEqual(workspace.layout.activeTab.path, try VaultPath("Scans/Page annotated.png"), "The drawing opens in place of the image.")
    }

    // MARK: Apple Pencil double-tap

    func testPencilDoubleTapStartsADrawingAtTheCursorOrOnTheImageThere() async throws {
        let noteText = "First line.\n\n![[Photo.png]]\n\nLast line.\n"
        let (workspace, directory) = try await makeWorkspace(notes: ["Note.md": noteText])
        try imageData(size: CGSize(width: 600, height: 400), color: .systemOrange).write(to: directory.appendingPathComponent("Photo.png"))
        await workspace.open(try VaultPath("Note.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = .source
        let controller = try host(AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        try await waitUntil { !self.descendants(of: controller.view, matching: MarkdownTextView.self).isEmpty }
        let textView = try XCTUnwrap(descendants(of: controller.view, matching: MarkdownTextView.self).first)
        let coordinator = try XCTUnwrap(textView.delegate as? NativeMarkdownEditor.Coordinator)
        try await waitUntil { coordinator.actions.drawOnPencilDoubleTap != nil }

        // The iPadOS setting to ignore double-tap is honored.
        textView.selectedRange = NSRange(location: 5, length: 0)
        coordinator.handlePencilDoubleTap(hoverLocation: nil, in: textView, preferredTapAction: .ignore)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(workspace.drawingEditorRequest)

        // In plain text, a new drawing goes in at the cursor.
        coordinator.handlePencilDoubleTap(hoverLocation: nil, in: textView, preferredTapAction: .switchEraser)
        try await waitUntil { workspace.drawingEditorRequest != nil }
        guard case .newDrawing(_, let insertionRange) = try XCTUnwrap(workspace.drawingEditorRequest).target else { return XCTFail("Not a new drawing") }
        XCTAssertEqual(insertionRange.location, 5)

        // A squeeze of Apple Pencil Pro starts a drawing too, when iPadOS leaves the squeeze
        // to the app; set to anything else, the squeeze is the system's.
        workspace.drawingEditorRequest = nil
        coordinator.handlePencilSqueeze(hoverLocation: nil, in: textView, preferredSqueezeAction: .switchEraser)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(workspace.drawingEditorRequest)
        coordinator.handlePencilSqueeze(hoverLocation: nil, in: textView, preferredSqueezeAction: .showContextualPalette)
        try await waitUntil { workspace.drawingEditorRequest != nil }

        // On an image's line, the image is drawn on.
        workspace.drawingEditorRequest = nil
        let embedLocation = (noteText as NSString).range(of: "![[Photo.png]]").location + 4
        textView.selectedRange = NSRange(location: embedLocation, length: 0)
        session.selection = textView.selectedRange
        coordinator.handlePencilDoubleTap(hoverLocation: nil, in: textView, preferredTapAction: .switchEraser)
        try await waitUntil { workspace.drawingEditorRequest != nil }
        guard case .drawingOnImage(let imagePath, _) = try XCTUnwrap(workspace.drawingEditorRequest).target else { return XCTFail("Not a drawing on the image") }
        XCTAssertEqual(imagePath, try VaultPath("Photo.png"))

        // The setting turns it off.
        workspace.drawingEditorRequest = nil
        workspace.preferences.drawsOnPencilDoubleTap = false
        try await waitUntil { coordinator.actions.drawOnPencilDoubleTap == nil }
        coordinator.handlePencilDoubleTap(hoverLocation: nil, in: textView, preferredTapAction: .switchEraser)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(workspace.drawingEditorRequest)
        workspace.preferences.drawsOnPencilDoubleTap = true
    }

    // MARK: Helpers

    private func makeWorkspace(notes: [String: String]) async throws -> (WorkspaceModel, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PencilTools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryLocations.append(directory)
        for (name, text) in notes { try Data(text.utf8).write(to: directory.appendingPathComponent(name)) }
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        return (workspace, directory)
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

    private func circlePoints(center: CGPoint, radius: Double) -> [CGPoint] {
        (0...48).map { pointIndex in
            let angle = (15 + 350 * Double(pointIndex) / 48) * .pi / 180
            let wobble = 1.5 * sin(Double(pointIndex) * 0.9)
            return CGPoint(x: center.x + (radius + wobble) * cos(angle), y: center.y + (radius + wobble) * sin(angle))
        }
    }

    private func stroke(through locations: [CGPoint], color: UIColor = .black, width: CGFloat = 4) -> PKStroke {
        let points = locations.enumerated().map { pointIndex, location in
            PKStrokePoint(location: location, timeOffset: Double(pointIndex) / 60, size: CGSize(width: width, height: width),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    private func imageData(size: CGSize, color: UIColor) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return try XCTUnwrap(image.pngData())
    }

    private func color(of image: CGImage, atFractionX fractionX: Double, fractionY: Double) throws -> (red: Double, green: Double, blue: Double) {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let column = Double(image.width) * fractionX, rowFromTop = Double(image.height) * fractionY
        // Core Graphics counts rows from the bottom.
        context.draw(image, in: CGRect(x: -column, y: -(Double(image.height) - rowFromTop - 1), width: Double(image.width), height: Double(image.height)))
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    /// Strokes set in code arrive within one turn of the run loop; a real stroke's event
    /// ends its undo group.
    private func endEvent(of history: UndoManager) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(history.groupingLevel, 0)
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
        XCTAssertTrue(condition(), "The hosted workspace did not reach the expected state.")
    }
}
#endif
