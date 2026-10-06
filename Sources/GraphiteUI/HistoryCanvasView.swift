#if canImport(UIKit)
import UIKit
import PencilKit
import GraphiteCore
import GraphiteApple

/// A PencilKit canvas whose undo history belongs to its document rather than to the canvas.
///
/// PencilKit records its own steps in the canvas's undo manager, aimed at the canvas: they
/// are lost when the canvas is released and would mix documents in a shared window history.
/// This canvas's undo manager records nothing. Its owner compares `recordedDrawing` with each
/// new drawing (`PencilDrawingChange`) and records the change in the document's history,
/// which undo and redo give back through `showDrawingFromHistory`.
class HistoryCanvasView: PKCanvasView {
    /// The drawing as of the last change the history knows, to tell what the next change
    /// removed and added.
    var recordedDrawing = PKDrawing()

    private static let discardingUndoManager: UndoManager = {
        let undoManager = UndoManager()
        undoManager.disableUndoRegistration()
        return undoManager
    }()
    override var undoManager: UndoManager? { Self.discardingUndoManager }

    /// PencilKit's lasso selection is a text input inside the canvas (for Writing Tools), and
    /// a view without an input view of its own uses its ancestor's. This empty one keeps the
    /// keyboard from covering the page when strokes are selected with a finger.
    private let emptyInputView = UIView()
    override var inputView: UIView? { emptyInputView }

    /// Whether the canvas or a view inside it, such as the lasso selection, is first responder.
    var containsFirstResponder: Bool { Self.containsFirstResponder(in: self) }

    private static func containsFirstResponder(in view: UIView) -> Bool {
        view.isFirstResponder || view.subviews.contains { subview in containsFirstResponder(in: subview) }
    }

    /// Shows a drawing the undo history produced. The canvas reports it like any change,
    /// so what depends on the drawing follows, but it is not recorded as a new step.
    func showDrawingFromHistory(_ drawing: PKDrawing) {
        endLassoSelection()
        // Graphite's own selection is positions in the drawing, which undo changes.
        if hasInkSelection { inkSelection.clearSelection() }
        recordedDrawing = drawing
        self.drawing = drawing
    }

    /// PencilKit keeps lasso-selected strokes in a view of their own, which would go on
    /// showing them where they were when the drawing changes under it. Changing the tool
    /// ends the selection.
    private func endLassoSelection() {
        guard let lassoTool = tool as? PKLassoTool else { return }
        tool = PKInkingTool(.pen)
        tool = lassoTool
    }

    /// Whether the canvas takes its tool from the floating palette.
    private(set) var followsToolPicker = false
    private var fixedTool: PencilToolSelection?

    /// Gives the canvas its tool: the fixed tool bar's when there is one, else the floating
    /// palette's, whose changes the canvas then follows. Either can ask for Graphite's
    /// lasso instead of a tool to draw with.
    func takeTool(from toolPicker: PKToolPicker, fixedTool newFixedTool: PencilToolSelection?) {
        if let newFixedTool {
            if followsToolPicker { stopFollowing(toolPicker) }
            guard newFixedTool != fixedTool else { return }
            fixedTool = newFixedTool
            selectsInk = newFixedTool.kind == .lasso
            // The lasso is Graphite's own; PencilKit's tool stays what it was and draws nothing.
            if newFixedTool.kind != .lasso { tool = newFixedTool.tool }
            isRulerActive = newFixedTool.isRulerActive
        } else if !followsToolPicker {
            fixedTool = nil
            followsToolPicker = true
            toolPicker.addObserver(self)
            isRulerActive = toolPicker.isRulerActive
            // Observers hear only later changes; start with the tool already selected.
            if #available(iOS 26.0, *), let selectedTool = toolPicker.selectedToolItem.tool {
                tool = selectedTool
            } else {
                (self as PKToolPickerObserver).toolPickerSelectedToolItemDidChange?(toolPicker)
            }
            selectsInk = PaletteInkSelection.isOn
            paletteInkSelectionObserver = NotificationCenter.default.addObserver(forName: PaletteInkSelection.didChange, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.selectsInk = PaletteInkSelection.isOn }
            }
        }
    }

    /// Stops following the palette, before the canvas is released or takes the fixed bar's tool.
    func stopFollowing(_ toolPicker: PKToolPicker) {
        toolPicker.removeObserver(self)
        followsToolPicker = false
        if let paletteInkSelectionObserver { NotificationCenter.default.removeObserver(paletteInkSelectionObserver) }
        paletteInkSelectionObserver = nil
    }

    private var paletteInkSelectionObserver: NSObjectProtocol?

    // MARK: Selecting ink

    private var hasInkSelection = false
    /// Graphite's lasso on this canvas (`InkSelectionController`).
    private(set) lazy var inkSelection: InkSelectionController = {
        hasInkSelection = true
        return InkSelectionController(canvas: self)
    }()

    /// Whether the canvas selects ink with Graphite's lasso instead of drawing.
    var selectsInk: Bool {
        get { hasInkSelection && inkSelection.isActive }
        set {
            guard newValue != selectsInk else { return }
            inkSelection.isActive = newValue
            applyDrawingEnabled()
        }
    }

    /// True while something other than drawing has the canvas, as arranging pictures has.
    var isDrawingSuspended = false {
        didSet { if isDrawingSuspended != oldValue { applyDrawingEnabled() } }
    }

    private func applyDrawingEnabled() {
        isDrawingEnabled = !isDrawingSuspended && !selectsInk
    }

    /// Gives the canvas a drawing it made from its own, as when Graphite's lasso moves,
    /// recolors or adds strokes. The canvas reports it like a stroke just drawn, so its
    /// owner records the change, but no shape is looked for in it.
    func setDrawingMadeByCanvas(_ drawing: PKDrawing) {
        expect(.isMadeByCanvas)
        self.drawing = drawing
    }

    // MARK: Shapes

    /// True while the canvas shows a drawing its owner is not to record: the shape a stroke
    /// became, which the change being handled already includes, or the drawing without the
    /// strokes a selection is dragging.
    private(set) var isShowingWithoutRecording = false

    func showWithoutRecording(_ drawing: PKDrawing) {
        isShowingWithoutRecording = true
        self.drawing = drawing
        isShowingWithoutRecording = false
    }

    /// What is known about the stroke the canvas is about to report.
    private enum ArrivingStroke {
        /// It was held at its end while its shape showed over it, and becomes that shape.
        case awaitsItsShape
        /// The canvas made it itself, as a shape or with Graphite's lasso, and it stays as it is.
        case isMadeByCanvas
    }
    private var arrivingStroke: ArrivingStroke?
    private var arrivingStrokeExpiry: DispatchWorkItem?

    /// How long a stroke may take to arrive. One that never does, as one PencilKit
    /// discarded, leaves nothing waiting for the next stroke.
    private static let strokeArrivalTime: TimeInterval = 1

    private func expect(_ stroke: ArrivingStroke) {
        arrivingStroke = stroke
        arrivingStrokeExpiry?.cancel()
        let expiry = DispatchWorkItem { [weak self] in self?.arrivingStroke = nil }
        arrivingStrokeExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.strokeArrivalTime, execute: expiry)
    }

    /// The drawing to record for the change the canvas just reported, asked once for each
    /// change. With the shape tool on, or after a hold at the end of the stroke, a stroke
    /// just drawn is replaced by its shape, which the canvas then shows.
    func drawingAfterShapeRecognition(shapeToolIsOn: Bool) -> PKDrawing {
        let reportedDrawing = drawing
        let expectation = arrivingStroke
        arrivingStroke = nil
        arrivingStrokeExpiry?.cancel()
        arrivingStrokeExpiry = nil
        if expectation == .isMadeByCanvas { return reportedDrawing }
        let strokeWasHeld = expectation == .awaitsItsShape
        if strokeWasHeld { removeShapePreview() }
        // One stroke more than before is, nearly always, a stroke just drawn.
        if reportedDrawing.strokes.count == recordedDrawing.strokes.count + 1, let newStroke = reportedDrawing.strokes.last {
            rememberFootprint(of: newStroke)
        }
        guard shapeToolIsOn || strokeWasHeld,
              let shapedDrawing = PencilShapes.replacingNewStroke(in: reportedDrawing, previousDrawing: recordedDrawing) else { return reportedDrawing }
        showWithoutRecording(shapedDrawing)
        // Apple Pencil Pro taps when a stroke snaps to a shape; after a hold it already has.
        if !strokeWasHeld, let shapeBounds = shapedDrawing.strokes.last?.renderBounds {
            shapeFeedback.pathCompleted(at: CGPoint(x: shapeBounds.midX * zoomScale, y: shapeBounds.midY * zoomScale))
        }
        return shapedDrawing
    }

    private lazy var shapeFeedback = UICanvasFeedbackGenerator(view: self)

    // MARK: Footprints

    /// The footprint each tool left in its newest stroke, by ink and width, for every canvas.
    /// A shape made while the Pencil is still down has no stroke of its own to take it from.
    private static var footprintsByTool: [String: StrokeFootprint] = [:]

    private static func footprintKey(inkType: PKInk.InkType, width: CGFloat) -> String {
        "\(inkType.rawValue)|\((width * 100).rounded())"
    }

    private func rememberFootprint(of stroke: PKStroke) {
        guard let inkingTool = tool as? PKInkingTool, inkingTool.inkType == stroke.ink.inkType, let footprint = StrokeFootprint(averaging: stroke) else { return }
        Self.footprintsByTool[Self.footprintKey(inkType: inkingTool.inkType, width: inkingTool.width)] = footprint
    }

    /// Nil until a stroke has been drawn with the tool at its present width.
    static func footprint(of inkingTool: PKInkingTool) -> StrokeFootprint? {
        footprintsByTool[footprintKey(inkType: inkingTool.inkType, width: inkingTool.width)]
    }

    // MARK: Hold to make a shape

    /// Resting the Pencil at the end of a stroke turns the stroke into its shape, as in
    /// Apple Notes (`StrokeHoldPreference`), and moving it on from there stretches the shape.
    ///
    /// PencilKit gives no way to change a stroke while it is drawn, or to end it before the
    /// Pencil lifts; it can only be made to discard it, and even then it goes on showing the
    /// stroke until the lift. So the shape is shown over the stroke when the Pencil rests,
    /// and takes the stroke's place when PencilKit reports the stroke after the lift. When
    /// the Pencil moves on instead, PencilKit's stroke is discarded, so that it grows no
    /// tail, the shape follows the Pencil, and the canvas adds it as a stroke of its own at
    /// the lift. That stroke needs the tool's footprint: with a tool that has not drawn a
    /// stroke yet, moving on goes back to drawing the stroke.
    private enum HeldShape {
        case overStroke(shape: RecognizedShape, heldPoint: CGPoint)
        case dragged(shape: RecognizedShape, heldPoint: CGPoint, draggedPoint: CGPoint, ink: PKInk, footprint: StrokeFootprint)
    }
    private var heldShape: HeldShape?

    private lazy var strokeHoldRecognizer: StrokeHoldRecognizer = {
        let recognizer = StrokeHoldRecognizer(target: nil, action: nil)
        recognizer.tracksTouch = { [weak self] touch in
            guard let self, StrokeHoldPreference.isOn(), self.tool is PKInkingTool, self.isDrawingEnabled, self.drawingGestureRecognizer.isEnabled else { return false }
            return self.drawingGestureRecognizer.allowedTouchTypes.contains(NSNumber(value: touch.type.rawValue))
        }
        recognizer.touchDidRest = { [weak self] strokePoints in self?.strokeTouchDidRest(afterStrokeThrough: strokePoints) }
        recognizer.touchDidMove = { [weak self] point, leftRestingPlace in self?.strokeTouchDidMove(to: point, leftRestingPlace: leftRestingPlace) }
        recognizer.touchDidEnd = { [weak self] wasCancelled in self?.strokeTouchDidEnd(wasCancelled: wasCancelled) }
        return recognizer
    }()
    private let shapePreviewLayer = CAShapeLayer()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, strokeHoldRecognizer.view == nil { addGestureRecognizer(strokeHoldRecognizer) }
    }

    var isShowingShapePreview: Bool { shapePreviewLayer.superlayer != nil }

    /// The touch drawing a stroke has rested. The stroke runs through the points, in the
    /// canvas's own coordinates; when it is a shape, the shape is shown.
    func strokeTouchDidRest(afterStrokeThrough strokePoints: [CGPoint]) {
        // A shape being dragged stays: the stroke it came from is gone.
        if case .dragged = heldShape { return }
        guard let inkingTool = tool as? PKInkingTool, let heldPoint = strokePoints.last, let shape = ShapeRecognizer.recognize(strokePoints) else { return }
        heldShape = .overStroke(shape: shape, heldPoint: heldPoint)
        showShapePreview(shape, color: inkingTool.color, width: Self.footprint(of: inkingTool)?.size.width ?? inkingTool.width)
        // Apple Pencil Pro taps when the stroke snaps to its shape.
        shapeFeedback.pathCompleted(at: heldPoint)
    }

    /// The touch drawing a stroke moved to a point in the canvas's own coordinates.
    func strokeTouchDidMove(to point: CGPoint, leftRestingPlace: Bool) {
        switch heldShape {
        case .overStroke(let shape, let heldPoint):
            // A resting hand trembles; the shape follows only once the hand has left.
            guard leftRestingPlace else { return }
            guard let inkingTool = tool as? PKInkingTool, let footprint = Self.footprint(of: inkingTool) else {
                // The stroke goes on: PencilKit is still drawing it.
                heldShape = nil
                removeShapePreview()
                return
            }
            discardStrokeBeingDrawn()
            heldShape = .dragged(shape: shape, heldPoint: heldPoint, draggedPoint: point, ink: inkingTool.ink, footprint: footprint)
            showShapePreview(shape.dragging(from: heldPoint, to: point), color: inkingTool.color, width: footprint.size.width)
        case .dragged(let shape, let heldPoint, _, let ink, let footprint):
            heldShape = .dragged(shape: shape, heldPoint: heldPoint, draggedPoint: point, ink: ink, footprint: footprint)
            showShapePreview(shape.dragging(from: heldPoint, to: point), color: ink.color, width: footprint.size.width)
        case nil:
            break
        }
    }

    /// The touch drawing a stroke lifted, or was cancelled.
    func strokeTouchDidEnd(wasCancelled: Bool) {
        defer {
            heldShape = nil
            resumeDrawing()
        }
        switch heldShape {
        case .overStroke:
            // The shape stays until PencilKit reports the stroke, which then becomes it.
            if wasCancelled { removeShapePreview() } else { expect(.awaitsItsShape) }
        case .dragged(let shape, let heldPoint, let draggedPoint, let ink, let footprint):
            removeShapePreview()
            guard !wasCancelled, zoomScale > 0 else { return }
            // From the canvas's coordinates to the drawing's.
            let drawingShape = shape.dragging(from: heldPoint, to: draggedPoint).transformed(scale: 1 / Double(zoomScale), rotation: 0, about: .zero)
            expect(.isMadeByCanvas)
            drawing = PKDrawing(strokes: drawing.strokes + [PencilShapes.shapeStroke(drawingShape, ink: ink, footprint: footprint)])
        case nil:
            break
        }
    }

    /// Makes PencilKit drop the stroke it is drawing, as it does when a scroll takes over.
    /// Its recognizer stays off until the touch ends, so the rest of the touch draws nothing.
    private func discardStrokeBeingDrawn() {
        guard drawingGestureRecognizer.state == .began || drawingGestureRecognizer.state == .changed else { return }
        drawingGestureRecognizer.isEnabled = false
        hasSwitchedOffDrawing = true
    }

    /// True while the canvas itself has PencilKit's drawing recognizer switched off.
    private var hasSwitchedOffDrawing = false

    private func resumeDrawing() {
        guard hasSwitchedOffDrawing else { return }
        hasSwitchedOffDrawing = false
        drawingGestureRecognizer.isEnabled = true
    }

    /// Shows a shape, given in the canvas's own coordinates, in the ink's color.
    private func showShapePreview(_ shape: RecognizedShape, color: UIColor, width: CGFloat) {
        let outline = shape.outlinePoints(spacing: 3)
        guard let firstPoint = outline.first else { return }
        let path = CGMutablePath()
        path.move(to: firstPoint)
        for point in outline.dropFirst() { path.addLine(to: point) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapePreviewLayer.path = path
        shapePreviewLayer.fillColor = nil
        // The color the canvas draws the ink in, which PencilKit adapts to a dark canvas.
        shapePreviewLayer.strokeColor = PKInkingTool.convertColor(color, from: .light, to: traitCollection.userInterfaceStyle).cgColor
        shapePreviewLayer.lineWidth = max(width * zoomScale, 1)
        shapePreviewLayer.lineCap = .round
        shapePreviewLayer.lineJoin = .round
        // Above PencilKit's own views, which hold the stroke being drawn.
        shapePreviewLayer.zPosition = 1
        if shapePreviewLayer.superlayer == nil { layer.addSublayer(shapePreviewLayer) }
        CATransaction.commit()
    }

    private func removeShapePreview() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapePreviewLayer.removeFromSuperlayer()
        CATransaction.commit()
    }
}

/// Invisible first responder that keeps the tool picker on screen while canvases come and
/// go. Its undo manager is the document's own history, so the picker's Undo and Redo, ⌘Z,
/// and the system undo gestures act on that document only.
///
/// PencilKit makes its lasso selection first responder. The selection is a text input, so
/// it would bring up the typing suggestions, and the picker's Undo and Redo would lose the
/// document's history while strokes are selected. The host takes first responder back; the
/// selection stays, and its menu and dragging work without it.
final class PencilToolPickerHostView: UIView {
    weak var documentUndoManager: UndoManager?
    /// The canvases this host serves, asked when it loses first responder.
    var canvases: () -> [HistoryCanvasView] = { [] }
    /// False while the owner wants the host to give up first responder, as when its document
    /// is no longer the one being worked in.
    var takesFirstResponderBackFromSelections = true

    override var canBecomeFirstResponder: Bool { true }
    override var undoManager: UndoManager? { documentUndoManager ?? super.undoManager }
    /// The host never types; without this it would use the input view of a canvas around it.
    override var inputView: UIView? { nil }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        // The next first responder is known only after this call returns.
        if didResign, takesFirstResponderBackFromSelections {
            DispatchQueue.main.async { [weak self] in self?.takeFirstResponderBackFromSelection() }
        }
        return didResign
    }

    private func takeFirstResponderBackFromSelection() {
        guard takesFirstResponderBackFromSelections, window != nil, !isFirstResponder,
              canvases().contains(where: { canvas in canvas.containsFirstResponder }) else { return }
        becomeFirstResponder()
    }
}
#endif
