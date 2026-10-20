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
    var recordedDrawing = PKDrawing() {
        didSet { changeFollowsInkingStroke = false }
    }

    /// Whether the change since `recordedDrawing` comes from a stroke of an inking tool,
    /// which only adds a stroke after the others.
    private var changeFollowsInkingStroke = false

    /// The change from `recordedDrawing` to `drawing`, or nil when they show the same strokes.
    /// A stroke an inking tool just added after the others is recognized from its neighbour,
    /// without comparing every stroke of the drawing, so a pen-up costs the same on a full
    /// page as on an empty one (`FR-104`); any other change compares them all.
    func changeSinceRecorded(to drawing: PKDrawing) -> PencilDrawingChange? {
        if changeFollowsInkingStroke, let appendingChange = PencilDrawingChange(appendingLastStrokeOf: drawing, to: recordedDrawing) {
            return appendingChange
        }
        return PencilDrawingChange(from: recordedDrawing, to: drawing)
    }

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
    /// The palette followed, to draw with its tool again when `toolForDrawing` changes.
    private weak var followedToolPicker: PKToolPicker?
    /// Gives the canvas the palette's tool, as `toolForDrawing` makes it, whenever it changes.
    private var paletteToolFollower: PaletteToolFollower?

    /// The tool the canvas draws with for a tool chosen in the palette or the bar: the same
    /// one, except for the highlighter while it ignores tilt, and on a canvas zoomed to draw
    /// sharper (`PDFPageCanvasView`). While the highlighter ignores tilt, the canvas draws
    /// with an invisible stand-in and shows the stroke itself (`EvenHighlighter`): PencilKit's
    /// live stroke follows the Pencil's tilt, and changed at the lift into the even one.
    func toolForDrawing(_ chosenTool: PKTool) -> PKTool {
        isEvenHighlighterPreferenceOn = EvenHighlighterPreference.isOn()
        guard isEvenHighlighterPreferenceOn, let highlighter = chosenTool as? PKInkingTool, highlighter.inkType == .marker,
              highlighter.color.cgColor.alpha > 0 else {
            evenHighlighterColor = nil
            return chosenTool
        }
        evenHighlighterColor = highlighter.color
        return EvenHighlighter.invisibleStandIn(for: highlighter)
    }

    /// The tool at `scale` times its width: PencilKit draws a tool as wide on screen at any
    /// zoom of its canvas, so a canvas that keeps a stroke as wide in its drawing at any zoom
    /// draws with the chosen width times its zoom. PencilKit gives the pen, the pencil and
    /// the highlighter no more than their widest width.
    static func tool(_ tool: PKTool, scaledBy scale: CGFloat) -> PKTool {
        guard scale > 0, scale != 1 else { return tool }
        if let inkingTool = tool as? PKInkingTool {
            return PKInkingTool(inkingTool.inkType, color: inkingTool.color, width: inkingTool.width * scale, azimuth: inkingTool.azimuth)
        }
        if let eraserTool = tool as? PKEraserTool {
            return PKEraserTool(eraserTool.eraserType, width: eraserTool.width * scale)
        }
        return tool
    }

    /// The topmost of the canvas's own views under PencilKit's ink, such as the drawing
    /// editor's paper and pictures; nil when PencilKit's views are the canvas's first.
    var topViewUnderInk: UIView? { nil }

    /// The highlighter's color while the canvas draws with its invisible stand-in.
    private(set) var evenHighlighterColor: UIColor?
    /// The preference as the canvas's tool was last made, to make it again when it changes.
    private var isEvenHighlighterPreferenceOn = false
    private var evenHighlighterPreferenceObserver: NSObjectProtocol?

    /// Settings, or the highlighter's options on the bar, can change the preference while the
    /// canvas is shown: its tool is made again, so the stand-in is never left in use without it.
    private func followEvenHighlighterPreference() {
        guard evenHighlighterPreferenceObserver == nil else { return }
        evenHighlighterPreferenceObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, EvenHighlighterPreference.isOn() != self.isEvenHighlighterPreferenceOn else { return }
                self.retakeChosenTool()
            }
        }
    }

    /// Takes the chosen tool again, after what `toolForDrawing` returns has changed.
    func retakeChosenTool() {
        if let fixedTool {
            if fixedTool.kind.drawsInk { drawWith(fixedTool.tool) }
        } else if followsToolPicker, let followedToolPicker, let selectedTool = Self.selectedTool(of: followedToolPicker) {
            drawWith(selectedTool)
        }
    }

    /// Draws with the tool `toolForDrawing` makes of a chosen one.
    private func drawWith(_ chosenTool: PKTool) {
        prepareToDraw(with: chosenTool)
        tool = toolForDrawing(chosenTool)
    }

    /// Called before the canvas takes a chosen tool, by a canvas whose drawing scale depends
    /// on the tool (`PDFPageCanvasView`).
    func prepareToDraw(with chosenTool: PKTool) {}

    /// The tool chosen in the fixed bar or the palette, before `toolForDrawing` changes it;
    /// nil when the bar's choice draws no ink, or nothing is followed yet.
    var chosenTool: PKTool? {
        if let fixedTool { return fixedTool.kind.drawsInk ? fixedTool.tool : nil }
        guard followsToolPicker, let followedToolPicker else { return nil }
        return Self.selectedTool(of: followedToolPicker)
    }

    /// PencilKit began a stroke with the canvas's tool (`PKCanvasViewDelegate.canvasViewDidBeginUsingTool`).
    func toolUseDidBegin() {
        changeFollowsInkingStroke = tool is PKInkingTool
        PencilWritingTrace.strokeDidBegin(on: self)
    }

    private static func selectedTool(of toolPicker: PKToolPicker) -> PKTool? {
        toolPicker.selectedToolItem.tool
    }

    /// Gives the canvas its tool: the fixed tool bar's when there is one, else the floating
    /// palette's, whose changes the canvas then follows. Either can ask for Graphite's
    /// lasso instead of a tool to draw with.
    func takeTool(from toolPicker: PKToolPicker, fixedTool newFixedTool: PencilToolSelection?) {
        if let newFixedTool {
            if followsToolPicker { stopFollowing(toolPicker) }
            guard newFixedTool != fixedTool else { return }
            fixedTool = newFixedTool
            selectsInk = newFixedTool.kind == .lasso
            pointsWithLaser = newFixedTool.kind == .laser
            pointsToRead = newFixedTool.kind == .readAloud
            // The lasso, the laser and the Read Aloud pen are Graphite's own; PencilKit's tool
            // stays what it was and draws nothing.
            if newFixedTool.kind.drawsInk { drawWith(newFixedTool.tool) }
            isRulerActive = newFixedTool.isRulerActive
        } else if !followsToolPicker {
            fixedTool = nil
            followsToolPicker = true
            followedToolPicker = toolPicker
            let follower = PaletteToolFollower(canvas: self)
            toolPicker.addObserver(follower)
            paletteToolFollower = follower
            isRulerActive = toolPicker.isRulerActive
            // Observers hear only later changes; start with the tool already selected.
            retakeChosenTool()
            selectsInk = PaletteInkSelection.isOn
            pointsWithLaser = PaletteInkSelection.pointsWithLaser
            pointsToRead = PaletteInkSelection.pointsToRead
            paletteInkSelectionObserver = NotificationCenter.default.addObserver(forName: PaletteInkSelection.didChange, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.selectsInk = PaletteInkSelection.isOn
                    self?.pointsWithLaser = PaletteInkSelection.pointsWithLaser
                    self?.pointsToRead = PaletteInkSelection.pointsToRead
                }
            }
        }
    }

    /// Stops following the palette, before the canvas is released or takes the fixed bar's tool.
    func stopFollowing(_ toolPicker: PKToolPicker) {
        if let paletteToolFollower { toolPicker.removeObserver(paletteToolFollower) }
        paletteToolFollower = nil
        followedToolPicker = nil
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

    /// A hand's touches landed or moved on the page (`PalmRejectionRecognizer`): with finger
    /// drawing, a stroke the hand began is taken back. PencilKit's drawing never waits for
    /// palm rejection, so the stroke is looked at on the next turn of the main queue, once
    /// PencilKit has begun it. It is cancelled only when every touch the drawing recognizer
    /// follows is one of the hand's and Apple Pencil is not on the screen
    /// (`PalmRejection.isStrokeDrawnByHand`): a Pencil stroke is never cancelled, even when a
    /// Pencil touch was not seen by `PencilActivity`.
    func takeBackStroke(ofHand handTouches: [UITouch]) {
        guard drawingPolicy == .anyInput else { return }
        for handTouch in handTouches { pendingHandTouches.add(handTouch) }
        guard !isHandStrokeCheckScheduled else { return }
        isHandStrokeCheckScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.takeBackStrokeOfPendingHand() }
        }
    }

    /// The hand's touches waiting for the next look at the stroke, held weakly as UIKit owns them.
    private let pendingHandTouches = NSHashTable<UITouch>.weakObjects()
    private var isHandStrokeCheckScheduled = false

    private func takeBackStrokeOfPendingHand() {
        isHandStrokeCheckScheduled = false
        let handTouchLocations = pendingHandTouches.allObjects
            .filter { handTouch in handTouch.phase != .ended && handTouch.phase != .cancelled }
            .map { handTouch in handTouch.location(in: self) }
        pendingHandTouches.removeAllObjects()
        let recognizer = drawingGestureRecognizer
        let drawingTouchLocations = (0..<recognizer.numberOfTouches).map { touchIndex in recognizer.location(ofTouch: touchIndex, in: self) }
        guard drawingPolicy == .anyInput,
              PalmRejection.isStrokeDrawnByHand(drawingTouchLocations: drawingTouchLocations, handTouchLocations: handTouchLocations,
                                                isPencilTouching: PencilActivity.isPencilTouching(at: PencilActivity.now)) else { return }
        // Whether PencilKit has begun the stroke yet or not, starting over drops it.
        recognizer.isEnabled = false
        recognizer.isEnabled = true
    }

    /// True while something other than drawing has the canvas, as arranging pictures has.
    var isDrawingSuspended = false {
        didSet { if isDrawingSuspended != oldValue { applyDrawingEnabled() } }
    }

    private func applyDrawingEnabled() {
        isDrawingEnabled = !isDrawingSuspended && !selectsInk && !pointsWithLaser && !pointsToRead
    }

    // MARK: Pointing

    private var hasLaserPointer = false
    /// The laser pointer on this canvas (`LaserPointerController`).
    private(set) lazy var laserPointer: LaserPointerController = {
        hasLaserPointer = true
        return LaserPointerController(canvas: self)
    }()

    /// Whether the canvas points with the laser instead of drawing.
    var pointsWithLaser: Bool {
        get { hasLaserPointer && laserPointer.isActive }
        set {
            guard newValue != pointsWithLaser else { return }
            laserPointer.isActive = newValue
            applyDrawingEnabled()
        }
    }

    // MARK: Pointing at what to read

    private var hasReadAloudPen = false
    /// The Read Aloud pen on this canvas (`ReadAloudPenController`).
    private(set) lazy var readAloudPen: ReadAloudPenController = {
        hasReadAloudPen = true
        return ReadAloudPenController(canvas: self)
    }()

    /// Where the Read Aloud pen tapped, in the window; set by the canvas's owner where there
    /// is text to read. Without it the pen draws nothing and reads nothing.
    var readAloudPenTapped: ((CGPoint) -> Void)?

    /// Whether the canvas points at what to read instead of drawing.
    var pointsToRead: Bool {
        get { hasReadAloudPen && readAloudPen.isActive }
        set {
            guard newValue != pointsToRead else { return }
            readAloudPen.isActive = newValue
            applyDrawingEnabled()
        }
    }

    /// Scrolling and zooming move the lasso's selection with the drawing; its frame and a
    /// marked area are placed again, at the same size on screen.
    override func layoutSubviews() {
        super.layoutSubviews()
        if hasInkSelection { inkSelection.canvasDidChangeScale() }
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
    private enum ArrivingStroke: Equatable {
        /// It was held at its end while its shape showed over it, and becomes that very shape,
        /// given in the drawing's coordinates.
        case awaitsItsShape(RecognizedShape)
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
    /// change. A highlighter stroke just drawn takes one width when the highlighter ignores
    /// tilt (`EvenHighlighter`). With the shape tool on, or after a hold at the end of the
    /// stroke, a stroke just drawn is replaced by its shape. The canvas then shows what the
    /// stroke became.
    func drawingAfterShapeRecognition(shapeToolIsOn: Bool) -> PKDrawing {
        let reportedDrawing = drawing
        let expectation = arrivingStroke
        arrivingStroke = nil
        arrivingStrokeExpiry?.cancel()
        arrivingStrokeExpiry = nil
        if expectation == .isMadeByCanvas { return reportedDrawing }
        var shapeShownAtHold: RecognizedShape?
        if case .awaitsItsShape(let shape) = expectation { shapeShownAtHold = shape }
        let strokeWasHeld = shapeShownAtHold != nil
        if strokeWasHeld { removeShapePreview() }
        let evenDrawing = drawingWithEvenHighlighterStroke(reportedDrawing)
        let drawnDrawing = evenDrawing ?? reportedDrawing
        // One stroke more than before is, nearly always, a stroke just drawn. An even
        // highlighter stroke leaves its even footprint, so a shape dragged from a hold is even too.
        if drawnDrawing.strokes.count == recordedDrawing.strokes.count + 1, let newStroke = drawnDrawing.strokes.last {
            rememberFootprint(of: newStroke)
        }
        // A held stroke becomes the shape that was shown, not whatever a second recognition makes of it.
        let shapedDrawingOrNil: PKDrawing?
        if let shapeShownAtHold {
            shapedDrawingOrNil = PencilShapes.replacingNewStroke(in: drawnDrawing, previousDrawing: recordedDrawing, with: shapeShownAtHold)
        } else if shapeToolIsOn {
            shapedDrawingOrNil = PencilShapes.replacingNewStroke(in: drawnDrawing, previousDrawing: recordedDrawing)
        } else {
            shapedDrawingOrNil = nil
        }
        guard let shapedDrawing = shapedDrawingOrNil else {
            if let evenDrawing { showReplacingStrokeJustDrawn(evenDrawing) }
            return drawnDrawing
        }
        showReplacingStrokeJustDrawn(shapedDrawing)
        // Apple Pencil Pro taps when a stroke snaps to a shape; after a hold it already has.
        if !strokeWasHeld, let shapeBounds = shapedDrawing.strokes.last?.renderBounds {
            shapeFeedback.pathCompleted(at: CGPoint(x: shapeBounds.midX * zoomScale, y: shapeBounds.midY * zoomScale))
        }
        return shapedDrawing
    }

    private lazy var shapeFeedback = UICanvasFeedbackGenerator(view: self)

    /// The drawing with the marker stroke just drawn at one width, the tool's, when the
    /// highlighter ignores tilt; nil when there is no such stroke or the preference is off.
    /// A stroke of the invisible stand-in always takes the highlighter's ink.
    private func drawingWithEvenHighlighterStroke(_ reportedDrawing: PKDrawing) -> PKDrawing? {
        // Asked at every stroke: the comparison of the whole drawing waits until a
        // highlighter stroke has arrived to be looked at.
        guard let lastStroke = reportedDrawing.strokes.last, evenHighlighterInk != nil || EvenHighlighter.isInvisible(lastStroke.ink),
              reportedDrawing.strokes.count == recordedDrawing.strokes.count + 1,
              reportedDrawing.strokes.last?.ink.inkType == .marker,
              let change = changeSinceRecorded(to: reportedDrawing), let newStrokeIndex = change.appendedStrokeIndex,
              newStrokeIndex < reportedDrawing.strokes.count,
              let evenStroke = evenHighlighterStroke(reportedDrawing.strokes[newStrokeIndex]) else { return nil }
        var strokes = reportedDrawing.strokes
        strokes[newStrokeIndex] = evenStroke
        return PKDrawing(strokes: strokes)
    }

    /// The ink of the canvas's highlighter, while it is in use and ignores tilt: the real
    /// one, not its invisible stand-in's. Nil otherwise.
    private var evenHighlighterInk: PKInk? {
        guard zoomScale > 0, let inkingTool = tool as? PKInkingTool, inkingTool.inkType == .marker else { return nil }
        if EvenHighlighter.isInvisible(inkingTool.ink) {
            return PKInk(.marker, color: evenHighlighterColor ?? inkingTool.color.withAlphaComponent(1))
        }
        return EvenHighlighterPreference.isOn() ? inkingTool.ink : nil
    }

    /// The stroke at the width of the canvas's highlighter, in its ink, when it is a
    /// highlighter stroke and the highlighter ignores tilt; nil otherwise. A stroke of the
    /// invisible stand-in, as one that arrives after the tool changed, never stays invisible.
    private func evenHighlighterStroke(_ stroke: PKStroke) -> PKStroke? {
        let isInvisible = EvenHighlighter.isInvisible(stroke.ink)
        guard let ink = evenHighlighterInk ?? (isInvisible ? PKInk(.marker, color: evenHighlighterColor ?? stroke.ink.color.withAlphaComponent(1)) : nil),
              zoomScale > 0 else { return nil }
        // PencilKit draws a tool as wide on screen at any zoom of its canvas, so in the
        // drawing's points the stroke is the tool's width over the zoom.
        let toolWidth = (tool as? PKInkingTool).map { inkingTool in inkingTool.inkType == .marker ? inkingTool.width : nil } ?? nil
        let drawnWidth = Array(stroke.path).first.map { point in point.size.width * EvenHighlighter.chiselLengthPerPointSize * zoomScale } ?? 0
        return EvenHighlighter.evenStroke(stroke, width: (toolWidth ?? drawnWidth) / zoomScale, ink: ink)
    }

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
        /// `shape` is in the canvas's coordinates, as shown; `drawingShape` is the same shape in the drawing's.
        case overStroke(shape: RecognizedShape, drawingShape: RecognizedShape, heldPoint: CGPoint)
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
        if window != nil, evenStrokeFollower.view == nil { addGestureRecognizer(evenStrokeFollower) }
        if window != nil { followEvenHighlighterPreference() }
    }

    var isShowingShapePreview: Bool { shapePreviewLayer.superlayer != nil }

    /// The touch drawing a stroke has rested. The stroke runs through the points, in the
    /// canvas's own coordinates; when it is a shape, the shape is shown.
    func strokeTouchDidRest(afterStrokeThrough strokePoints: [CGPoint]) {
        // A shape being dragged stays: the stroke it came from is gone.
        if case .dragged = heldShape { return }
        guard zoomScale > 0, let inkingTool = tool as? PKInkingTool, let heldPoint = strokePoints.last,
              let drawingShape = ShapeRecognizer.recognizeHeldStroke(canvasPoints: strokePoints, zoomScale: Double(zoomScale)) else { return }
        let shape = drawingShape.transformed(scale: Double(zoomScale), rotation: 0, about: .zero)
        heldShape = .overStroke(shape: shape, drawingShape: drawingShape, heldPoint: heldPoint)
        // The shape shows instead of the highlighter's band, which comes back if the stroke goes on.
        removeEvenStrokeLayer()
        showShapePreview(shape, color: shownColor(of: inkingTool.ink), width: Self.footprint(of: inkingTool)?.size.width ?? inkingTool.width)
        // Apple Pencil Pro taps when the stroke snaps to its shape.
        shapeFeedback.pathCompleted(at: heldPoint)
    }

    /// The touch drawing a stroke moved to a point in the canvas's own coordinates.
    func strokeTouchDidMove(to point: CGPoint, leftRestingPlace: Bool) {
        switch heldShape {
        case .overStroke(let shape, _, let heldPoint):
            // A resting hand trembles; the shape follows only once the hand has left.
            guard leftRestingPlace else { return }
            guard let inkingTool = tool as? PKInkingTool, let footprint = Self.footprint(of: inkingTool) else {
                // The stroke goes on: PencilKit is still drawing it.
                heldShape = nil
                removeShapePreview()
                if !evenStrokePoints.isEmpty { showEvenStroke(predicted: []) }
                return
            }
            discardStrokeBeingDrawn()
            heldShape = .dragged(shape: shape, heldPoint: heldPoint, draggedPoint: point, ink: inkingTool.ink, footprint: footprint)
            showShapePreview(shape.dragging(from: heldPoint, to: point), color: shownColor(of: inkingTool.ink), width: footprint.size.width)
        case .dragged(let shape, let heldPoint, _, let ink, let footprint):
            heldShape = .dragged(shape: shape, heldPoint: heldPoint, draggedPoint: point, ink: ink, footprint: footprint)
            showShapePreview(shape.dragging(from: heldPoint, to: point), color: shownColor(of: ink), width: footprint.size.width)
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
        case .overStroke(_, let drawingShape, _):
            // The shape stays until PencilKit reports the stroke, which then becomes it.
            if wasCancelled { removeShapePreview() } else { expect(.awaitsItsShape(drawingShape)) }
        case .dragged(let shape, let heldPoint, let draggedPoint, let ink, let footprint):
            removeShapePreview()
            guard !wasCancelled, zoomScale > 0 else { return }
            // From the canvas's coordinates to the drawing's.
            let drawingShape = shape.dragging(from: heldPoint, to: draggedPoint).transformed(scale: 1 / Double(zoomScale), rotation: 0, about: .zero)
            let shapeStroke = PencilShapes.shapeStroke(drawingShape, ink: ink, footprint: footprint)
            expect(.isMadeByCanvas)
            coverUntilRendered()
            drawing = PKDrawing(strokes: drawing.strokes + [evenHighlighterStroke(shapeStroke) ?? shapeStroke])
        case nil:
            break
        }
    }

    /// Makes PencilKit drop the stroke it is drawing, as it does when a scroll takes over.
    /// Its recognizer stays off until the touch ends, so the rest of the touch draws nothing.
    private func discardStrokeBeingDrawn() {
        guard drawingGestureRecognizer.state == .began || drawingGestureRecognizer.state == .changed else { return }
        drawingGestureRecognizer.isEnabled = false
        drawingSwitchedOffTime = ProcessInfo.processInfo.systemUptime
    }

    /// When the canvas itself switched PencilKit's drawing recognizer off; nil while it is on.
    private var drawingSwitchedOffTime: TimeInterval?

    private func resumeDrawing() {
        guard drawingSwitchedOffTime != nil else { return }
        drawingSwitchedOffTime = nil
        drawingGestureRecognizer.isEnabled = true
    }

    /// Turns drawing back on when the canvas switched it off for a held shape over
    /// `seconds` ago and the end of that touch never came, as when the canvas left the
    /// window mid-stroke: the page would otherwise never draw again. True when it did.
    func resumeDrawingLeftOff(forLongerThan seconds: TimeInterval) -> Bool {
        guard let drawingSwitchedOffTime, ProcessInfo.processInfo.systemUptime - drawingSwitchedOffTime >= seconds,
              !PencilActivity.isPencilTouching(at: PencilActivity.now) else { return false }
        heldShape = nil
        removeShapePreview()
        resumeDrawing()
        return true
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

    /// The color ink is shown in: the highlighter's for its invisible stand-in.
    private func shownColor(of ink: PKInk) -> UIColor {
        EvenHighlighter.isInvisible(ink) ? (evenHighlighterColor ?? ink.color.withAlphaComponent(1)) : ink.color
    }

    // MARK: Replacing the stroke just drawn without a gap

    /// Shows the drawing the stroke just drawn became, its shape or its even form. PencilKit
    /// draws a drawing it is given anew, and showed neither the stroke nor what replaced it
    /// for about 30 milliseconds (two to four frames, seen in simulator recordings). The
    /// canvas as it was stays over it until PencilKit has drawn the new drawing.
    private func showReplacingStrokeJustDrawn(_ drawing: PKDrawing) {
        coverUntilRendered()
        showWithoutRecording(drawing)
    }

    /// The canvas as it was, shown in its place while PencilKit draws a new drawing.
    private var renderCover: UIView?
    private var renderCoverExpiry: DispatchWorkItem?
    /// The longest the canvas stays covered, should PencilKit not report the drawing drawn.
    private static let longestRenderCoverSeconds: TimeInterval = 0.5

    /// Lays a picture of the canvas over it, beside it in its superview, and hides the
    /// canvas's own content under it with an empty mask. The picture alone shows the canvas
    /// meanwhile: laid over the canvas still showing, it would darken every translucent
    /// stroke. A mask does not change what touches reach the canvas, so the next stroke
    /// begins as always.
    private func coverUntilRendered() {
        guard window != nil, renderCover == nil, let superview, let canvasAsItWas = snapshotView(afterScreenUpdates: false) else { return }
        canvasAsItWas.isUserInteractionEnabled = false
        canvasAsItWas.bounds = CGRect(origin: .zero, size: bounds.size)
        canvasAsItWas.center = center
        canvasAsItWas.transform = transform
        superview.insertSubview(canvasAsItWas, aboveSubview: self)
        renderCover = canvasAsItWas
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.mask = CALayer()
        CATransaction.commit()
        hideEvenStroke()
        let expiry = DispatchWorkItem { [weak self] in self?.removeRenderCover() }
        renderCoverExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.longestRenderCoverSeconds, execute: expiry)
    }

    /// PencilKit has drawn the canvas's drawing (`PKCanvasViewDelegate.canvasViewDidFinishRendering`).
    func drawingDidFinishRendering() {
        removeRenderCover()
    }

    private func removeRenderCover() {
        renderCoverExpiry?.cancel()
        renderCoverExpiry = nil
        guard let renderCover else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.mask = nil
        renderCover.removeFromSuperview()
        CATransaction.commit()
        self.renderCover = nil
    }

    var isCoveredWhileRendering: Bool { renderCover != nil }

    // MARK: The even highlighter's stroke while it is drawn

    /// Shows the stroke the invisible stand-in is drawing as the band its even form draws
    /// (`EvenHighlighter.bandPath`), in the highlighter's color, so nothing changes at the lift.
    private let evenStrokeLayer = CAShapeLayer()
    private var evenStrokePoints: [CGPoint] = []
    /// Whether PencilKit has begun drawing the stroke the layer shows: once it stops, as when
    /// palm rejection or a held shape takes the stroke back, the layer goes too.
    private var hasSeenEvenStrokeDrawn = false
    private var evenStrokeExpiry: DispatchWorkItem?

    private lazy var evenStrokeFollower: DrawnStrokeFollower = {
        let follower = DrawnStrokeFollower(target: nil, action: nil)
        follower.followsTouch = { [weak self] touch in
            guard let self, let inkingTool = self.tool as? PKInkingTool, EvenHighlighter.isInvisible(inkingTool.ink),
                  self.isDrawingEnabled, self.drawingGestureRecognizer.isEnabled else { return false }
            return self.drawingGestureRecognizer.allowedTouchTypes.contains(NSNumber(value: touch.type.rawValue))
        }
        follower.strokeDidBegin = { [weak self] point in self?.beginEvenStroke(at: point) }
        follower.strokeDidMove = { [weak self] points, predictedPoints in self?.extendEvenStroke(with: points, predicted: predictedPoints) }
        follower.strokeDidEnd = { [weak self] wasCancelled in self?.endEvenStroke(wasCancelled: wasCancelled) }
        return follower
    }()

    /// For tests, which cannot send touches: shows the band of a stroke being drawn through
    /// points in the canvas's own coordinates, as the stroke's touch would.
    func showEvenStrokeBeingDrawn(through points: [CGPoint]) {
        guard let firstPoint = points.first else { return }
        beginEvenStroke(at: firstPoint)
        evenStrokePoints += points.dropFirst()
        showEvenStroke(predicted: [])
    }

    var isShowingEvenStroke: Bool { evenStrokeLayer.superlayer != nil }

    private func beginEvenStroke(at point: CGPoint) {
        evenStrokeExpiry?.cancel()
        evenStrokePoints = [point]
        hasSeenEvenStrokeDrawn = false
        showEvenStroke(predicted: [])
    }

    private func extendEvenStroke(with points: [CGPoint], predicted predictedPoints: [CGPoint]) {
        guard !evenStrokePoints.isEmpty else { return }
        let drawingState = drawingGestureRecognizer.state
        if drawingState == .began || drawingState == .changed {
            hasSeenEvenStrokeDrawn = true
        } else if hasSeenEvenStrokeDrawn || !drawingGestureRecognizer.isEnabled {
            // PencilKit dropped the stroke.
            hideEvenStroke()
            return
        }
        evenStrokePoints += points
        showEvenStroke(predicted: predictedPoints)
    }

    private func endEvenStroke(wasCancelled: Bool) {
        guard !evenStrokePoints.isEmpty else { return }
        if wasCancelled {
            hideEvenStroke()
            return
        }
        // The band stays until the even stroke takes its place; should no stroke arrive, as
        // when PencilKit discarded it, it goes.
        showEvenStroke(predicted: [])
        let expiry = DispatchWorkItem { [weak self] in self?.hideEvenStroke() }
        evenStrokeExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.strokeArrivalTime, execute: expiry)
    }

    private func showEvenStroke(predicted predictedPoints: [CGPoint]) {
        guard let inkingTool = tool as? PKInkingTool, !isShowingShapePreview else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        evenStrokeLayer.path = EvenHighlighter.bandPath(through: evenStrokePoints + predictedPoints, width: inkingTool.width)
        evenStrokeLayer.fillColor = nil
        // The color the canvas draws the ink in, which PencilKit adapts to a dark canvas.
        evenStrokeLayer.strokeColor = PKInkingTool.convertColor(shownColor(of: inkingTool.ink), from: .light, to: traitCollection.userInterfaceStyle).cgColor
        evenStrokeLayer.lineWidth = inkingTool.width * EvenHighlighter.bandHeightPerWidth
        // PencilKit softens a marker's edges in the drawing's own points, so how strong the
        // band's middle is follows its width in the drawing, not on screen.
        evenStrokeLayer.opacity = Float(EvenHighlighter.bandOpacity(forWidth: inkingTool.width / max(zoomScale, 0.01)))
        evenStrokeLayer.lineCap = .butt
        evenStrokeLayer.lineJoin = .round
        // Under PencilKit's own views, as PencilKit draws a highlight: under the ink it
        // crosses, which stays as dark as it is.
        if evenStrokeLayer.superlayer == nil {
            if let topViewUnderInk { layer.insertSublayer(evenStrokeLayer, above: topViewUnderInk.layer) } else { layer.insertSublayer(evenStrokeLayer, at: 0) }
        }
        CATransaction.commit()
    }

    private func hideEvenStroke() {
        evenStrokeExpiry?.cancel()
        evenStrokeExpiry = nil
        evenStrokePoints = []
        removeEvenStrokeLayer()
    }

    private func removeEvenStrokeLayer() {
        guard evenStrokeLayer.superlayer != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        evenStrokeLayer.removeFromSuperlayer()
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

    /// ⌘V on the page: pastes ink as ink and an image as a picture (`LassoPasteboard`); nil
    /// where nothing can be pasted.
    var pasteFromPasteboard: (() -> Void)?

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) { return pasteFromPasteboard != nil && LassoPasteboard.hasContent }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        pasteFromPasteboard?()
    }
    /// The host never types; without this it would use the input view of a canvas around it.
    override var inputView: UIView? { nil }

    @discardableResult
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

/// Follows the floating palette for a canvas: gives it the palette's tool as
/// `toolForDrawing` makes it, in the same turn as the palette's choice changes, and the
/// palette's ruler. The canvas does not observe the palette itself: PencilKit would give
/// it the palette's tool as it is, too narrow on the page of a zoomed canvas, and gives it
/// again at moments no observer hears of (a canvas added as an observer takes it at once).
/// So the palette, like the fixed bar, puts the tool on the canvas only through
/// `toolForDrawing`, from the first stroke after a choice on.
@MainActor
private final class PaletteToolFollower: NSObject, PKToolPickerObserver {
    private weak var canvas: HistoryCanvasView?

    init(canvas: HistoryCanvasView) {
        self.canvas = canvas
    }

    func toolPickerSelectedToolItemDidChange(_ toolPicker: PKToolPicker) {
        canvas?.retakeChosenTool()
    }

    func toolPickerIsRulerActiveDidChange(_ toolPicker: PKToolPicker) {
        canvas?.isRulerActive = toolPicker.isRulerActive
    }
}
#endif
