import Foundation
import CoreGraphics
import GraphiteCore

/// The geometry of Graphite's lasso: which strokes and pictures a loop takes, and how a
/// moved or resized selection frame carries them along.
enum InkLasso {
    /// A stroke is taken when at least this much of it lies inside the loop, so a loop
    /// drawn around a word does not take the long line passing under it. A picture is
    /// taken when this much of its area does.
    static let minimumEnclosedFraction = 0.6
    /// A loop shorter than this, in screen points, is a tap.
    static let minimumLoopLength: CGFloat = 24
    /// A tap takes the stroke that passes within this distance of it, in screen points.
    static let tapReach: CGFloat = 14
    /// How many points along each side of a picture are tested against the loop.
    static let pictureSamplesPerSide = 6

    /// Whether the point is inside the closed loop through the points, by the even-odd rule.
    static func isPoint(_ point: CGPoint, insideLoop loop: [CGPoint]) -> Bool {
        guard loop.count >= 3, var previous = loop.last else { return false }
        var isInside = false
        for current in loop {
            if (current.y > point.y) != (previous.y > point.y),
               point.x < (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x {
                isInside.toggle()
            }
            previous = current
        }
        return isInside
    }

    /// The share of the points that lies inside the loop; zero for no points.
    static func enclosedFraction(of points: [CGPoint], inLoop loop: [CGPoint]) -> Double {
        guard !points.isEmpty else { return 0 }
        return Double(points.filter { point in isPoint(point, insideLoop: loop) }.count) / Double(points.count)
    }

    static func length(of loop: [CGPoint]) -> CGFloat {
        zip(loop, loop.dropFirst()).reduce(0) { total, pair in total + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y) }
    }

    /// The smallest upright rectangle around the points; null for none.
    static func bounds(of points: [CGPoint]) -> CGRect {
        points.reduce(CGRect.null) { bounds, point in bounds.union(CGRect(origin: point, size: .zero)) }
    }

    /// The loop of a rectangular lasso dragged from one corner to the opposite one.
    static func rectangleLoop(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        [start, CGPoint(x: end.x, y: start.y), end, CGPoint(x: start.x, y: end.y)]
    }

    /// Points spread evenly over a rectangle turned about its middle, to measure how much
    /// of a picture a loop encloses.
    static func samplePoints(ofRectangle rectangle: CGRect, turnedBy rotationRadians: Double) -> [CGPoint] {
        let middle = CGPoint(x: rectangle.midX, y: rectangle.midY)
        let count = pictureSamplesPerSide
        return (0..<count).flatMap { row in
            (0..<count).map { column in
                let point = CGPoint(x: rectangle.minX + rectangle.width * (CGFloat(column) + 0.5) / CGFloat(count),
                                    y: rectangle.minY + rectangle.height * (CGFloat(row) + 0.5) / CGFloat(count))
                return PictureRotation.point(point, turnedBy: rotationRadians, about: middle)
            }
        }
    }

    /// The transform that carries what `frame` surrounds to where `newFrame` surrounds it:
    /// scaled in proportion by the change in width, and moved.
    static func transform(from frame: CGRect, to newFrame: CGRect) -> CGAffineTransform {
        guard frame.width > 0, frame.height > 0 else { return .identity }
        let scale = newFrame.width / frame.width
        return CGAffineTransform(translationX: -frame.minX, y: -frame.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: newFrame.minX, y: newFrame.minY))
    }
}

/// Graphite's own tools that the canvases following the floating palette take instead of
/// drawing: its lasso and its laser pointer. The palette's own lasso is PencilKit's, which
/// can neither resize nor recolor what it selects and tells nobody what that is. Both are
/// switched on from the palette's accessory menu and off again by choosing any tool; only
/// one is on at a time. They are not kept between launches.
@MainActor
enum PaletteInkSelection {
    static let didChange = Notification.Name("GraphitePaletteInkSelectionDidChange")
    /// Graphite's lasso ("Select Ink").
    static var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            if isOn { pointsWithLaser = false }
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
    /// The laser pointer.
    static var pointsWithLaser = false {
        didSet {
            guard pointsWithLaser != oldValue else { return }
            if pointsWithLaser { isOn = false }
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}

#if canImport(UIKit)
import UIKit
import PencilKit
import UniformTypeIdentifiers
import GraphiteCore

/// Graphite's lasso on one canvas. A loop drawn around strokes and pictures, freehand or
/// as a rectangle (`LassoShape`), or a tap on a stroke, selects them; the selection's frame
/// moves and resizes them, and its menu cuts, copies, duplicates, deletes and recolors
/// them, or takes a picture of the area. Every change is one step of the document's
/// history, the ink's and the pictures' together.
///
/// A loop that encloses nothing selectable still marks an area, shown tinted, whose menu
/// takes a picture of it: of the page or the drawing with its pictures and ink, at print
/// resolution (`LassoAreaCapture`).
///
/// The selection is the positions of its strokes in the canvas's drawing and the names of
/// its pictures. While its frame is dragged, the canvas shows the drawing without them
/// and the frame shows their picture; they move when the drag ends.
@MainActor
final class InkSelectionController: NSObject, UIGestureRecognizerDelegate, @preconcurrency UIEditMenuInteractionDelegate {
    private unowned let canvas: HistoryCanvasView
    private(set) var selectedStrokeIndices: [Int] = []
    /// The pictures selected with the ink (`LassoCanvasContent`).
    private(set) var selectedPictureIdentifiers: [String] = []
    /// The loop the selection or the area was taken with, in the drawing's coordinates.
    /// A picture of the selection is of this area; nil once the selection has moved, as
    /// for a selection made with a tap.
    private(set) var lassoedLoop: [CGPoint]?
    /// True while an area is marked that holds nothing selectable.
    private(set) var isShowingLassoedArea = false
    /// Only one canvas has a selection at a time, as only one page is written on at a time.
    private static weak var controllerWithSelection: InkSelectionController?

    private lazy var loopRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleLoop(_:)))
    private lazy var tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    private lazy var selectionTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleSelectionTap(_:)))
    private lazy var selectionMenu = UIEditMenuInteraction(delegate: self)
    /// The menu of a tap beside the ink (Paste) and of a marked area.
    private lazy var canvasMenu = UIEditMenuInteraction(delegate: self)
    /// The loop's line, over a wider white halo, around a faint tint of the area.
    private let loopLayer = CAShapeLayer()
    private let loopHaloLayer = CAShapeLayer()
    /// The loop being drawn, in the canvas's coordinates.
    private var loopPoints: [CGPoint] = []
    /// Where a rectangular lasso began, in the canvas's coordinates.
    private var rectangleStart: CGPoint?
    private var selectionView: SelectionFrameView?
    /// The drawing, the pictures and the frame when a drag of the selection began.
    private var dragStart: (drawing: PKDrawing, pictures: [LassoPicture], frame: CGRect)?
    private var pastePoint: CGPoint = .zero
    /// The scale the frame and the loop were last drawn at, to redraw them after a zoom.
    private var shownScreenScale: CGFloat = 0
    private var zoomObserver: NSObjectProtocol?

    /// The frame reaches this far beyond the ink, so its handles are clear of it.
    private static let frameMargin: CGFloat = 8
    private static let duplicateOffset = CGSize(width: 16, height: 16)
    /// The most pixels along one side of the picture shown while a selection is dragged.
    private static let maximumPreviewSideInPixels: CGFloat = 4_096
    /// The loop's line and dashes, in screen points, at any zoom.
    private static let loopLineWidth: CGFloat = 1.5
    private static let increasedContrastLoopLineWidth: CGFloat = 2.5
    private static let loopDashPattern: [CGFloat] = [6, 4]
    private static let loopHaloWidth: CGFloat = 1

    init(canvas: HistoryCanvasView) {
        self.canvas = canvas
        super.init()
        loopLayer.zPosition = 2
        loopHaloLayer.zPosition = 1
        loopLayer.lineJoin = .round
        loopHaloLayer.lineJoin = .round
    }

    /// Whether the canvas selects instead of drawing. Switching it off ends the selection.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if isActive {
                installRecognizers()
            } else {
                clearSelection()
            }
            loopRecognizer.isEnabled = isActive
            tapRecognizer.isEnabled = isActive
        }
    }

    /// What the canvas offers besides its ink: its pictures, and what lies under the ink.
    fileprivate var content: LassoCanvasContent? { canvas as? LassoCanvasContent }

    private func installRecognizers() {
        guard loopRecognizer.view == nil else { return }
        loopRecognizer.maximumNumberOfTouches = 1
        loopRecognizer.delegate = self
        tapRecognizer.delegate = self
        canvas.addGestureRecognizer(loopRecognizer)
        canvas.addGestureRecognizer(tapRecognizer)
        canvas.addInteraction(canvasMenu)
        // A PDF view zooms its pages without laying out their canvases again; the frame's
        // handles and the loop's line are redrawn to keep their size on screen.
        zoomObserver = NotificationCenter.default.addObserver(forName: .PDFViewScaleChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.canvasDidChangeScale() }
        }
    }

    /// The lasso takes the touches the canvas would draw with: the Pencil, and a finger when
    /// fingers draw. A touch on the selection's frame moves or resizes it and starts no loop.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard canvas.drawingGestureRecognizer.allowedTouchTypes.contains(NSNumber(value: touch.type.rawValue)) else { return false }
        if let selectionView, let touchedView = touch.view, touchedView.isDescendant(of: selectionView) { return false }
        if gestureRecognizer === loopRecognizer { touchDownLocation = touch.location(in: canvas) }
        return true
    }

    /// Where the touch the loop recognizer was given came down, in the canvas's coordinates.
    private var touchDownLocation: CGPoint?

    // MARK: Coordinates

    /// How large a point of the canvas is on screen: a PDF page's canvas is scaled with its page.
    private var screenPointsPerCanvasPoint: CGFloat {
        max(canvas.convert(CGRect(x: 0, y: 0, width: 1, height: 1), to: nil).width, 0.01)
    }

    private var zoomScale: CGFloat { max(canvas.zoomScale, 0.0001) }

    private func drawingPoint(fromCanvas point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / zoomScale, y: point.y / zoomScale)
    }

    private func canvasRectangle(fromDrawing rectangle: CGRect) -> CGRect {
        CGRect(x: rectangle.minX * zoomScale, y: rectangle.minY * zoomScale, width: rectangle.width * zoomScale, height: rectangle.height * zoomScale)
    }

    private func drawingRectangle(fromCanvas rectangle: CGRect) -> CGRect {
        CGRect(x: rectangle.minX / zoomScale, y: rectangle.minY / zoomScale, width: rectangle.width / zoomScale, height: rectangle.height / zoomScale)
    }

    // MARK: Selecting

    @objc private func handleLoop(_ recognizer: UIPanGestureRecognizer) {
        let point = recognizer.location(in: canvas)
        switch recognizer.state {
        case .began:
            // The pan is recognized only after the touch has moved a little, and its
            // translation starts from there; the loop starts where the touch came down. A
            // rectangle began 15 points late, cutting off the corner it was dragged from.
            loopDidBegin(at: touchDownLocation ?? point, reaching: point)
            touchDownLocation = nil
        case .changed:
            loopDidMove(to: point)
        case .ended:
            loopDidEnd(at: point)
        default:
            loopWasCancelled()
        }
    }

    /// A loop, or a rectangle, begins where the touch came down, in the canvas's coordinates.
    func loopDidBegin(at start: CGPoint, reaching point: CGPoint) {
        clearSelection()
        if LassoShape.stored == .rectangle {
            rectangleStart = start
            loopPoints = InkLasso.rectangleLoop(from: start, to: point)
        } else {
            rectangleStart = nil
            loopPoints = [start, point]
        }
        showLoop(isFinished: false)
    }

    func loopDidMove(to point: CGPoint) {
        if let rectangleStart { loopPoints = InkLasso.rectangleLoop(from: rectangleStart, to: point) } else { loopPoints.append(point) }
        showLoop(isFinished: false)
    }

    /// Takes what the loop encloses, or marks its area.
    func loopDidEnd(at point: CGPoint) {
        loopDidMove(to: point)
        let loop = loopPoints
        let isRectangle = rectangleStart != nil
        rectangleStart = nil
        removeLoop()
        guard isLargeEnough(loop, isRectangle: isRectangle) else { return }
        selectContents(enclosedBy: loop)
    }

    func loopWasCancelled() {
        rectangleStart = nil
        removeLoop()
    }

    /// The loop's line and its halo while they are shown, for checking how they are drawn.
    var shownLoopLayers: (line: CAShapeLayer, halo: CAShapeLayer)? {
        loopLayer.superlayer == nil ? nil : (loopLayer, loopHaloLayer)
    }

    /// A loop shorter than a tap's reach on screen, or a box thinner than that, is a slip.
    private func isLargeEnough(_ loop: [CGPoint], isRectangle: Bool) -> Bool {
        let scale = screenPointsPerCanvasPoint
        if isRectangle {
            let bounds = InkLasso.bounds(of: loop)
            return min(bounds.width, bounds.height) * scale >= InkLasso.tapReach
        }
        return InkLasso.length(of: loop) * scale >= InkLasso.minimumLoopLength
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let point = recognizer.location(in: canvas)
        let hadSelection = !selectedStrokeIndices.isEmpty || !selectedPictureIdentifiers.isEmpty || isShowingLassoedArea
        // A tap on another stroke selects it at once; beside the ink it ends the selection.
        if selectStroke(at: point) { return }
        if !hadSelection, Self.strokesOnPasteboard() != nil {
            pastePoint = point
            canvasMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: MenuIdentifier.paste as NSString, sourcePoint: point))
        }
    }

    /// The loop as it is drawn, or the area it marked: a dashed line in the accent as it reads
    /// on white over a white halo, the same width and dashes on screen at any zoom, around a
    /// faint tint once the area is marked, or while a rectangle is dragged.
    private func showLoop(isFinished: Bool) {
        guard let firstPoint = loopPoints.first else { return }
        let path = CGMutablePath()
        path.move(to: firstPoint)
        for point in loopPoints.dropFirst() { path.addLine(to: point) }
        if isFinished || rectangleStart != nil { path.closeSubpath() }
        let canvasPointsPerScreenPoint = 1 / screenPointsPerCanvasPoint
        let lineColor = LassoColors.line(for: canvas.traitCollection)
        let lineWidth = canvas.traitCollection.accessibilityContrast == .high ? Self.increasedContrastLoopLineWidth : Self.loopLineWidth
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        loopLayer.path = path
        loopLayer.strokeColor = lineColor.cgColor
        loopLayer.fillColor = isFinished || rectangleStart != nil ? lineColor.withAlphaComponent(LassoColors.areaFillOpacity).cgColor : nil
        loopLayer.lineWidth = lineWidth * canvasPointsPerScreenPoint
        loopLayer.lineDashPattern = Self.loopDashPattern.map { length in NSNumber(value: Double(length * canvasPointsPerScreenPoint)) }
        loopHaloLayer.path = path
        loopHaloLayer.fillColor = nil
        loopHaloLayer.strokeColor = LassoColors.halo.cgColor
        loopHaloLayer.lineWidth = (lineWidth + 2 * Self.loopHaloWidth) * canvasPointsPerScreenPoint
        if loopHaloLayer.superlayer !== canvas.layer { canvas.layer.addSublayer(loopHaloLayer) }
        if loopLayer.superlayer !== canvas.layer { canvas.layer.addSublayer(loopLayer) }
        CATransaction.commit()
        shownScreenScale = screenPointsPerCanvasPoint
    }

    private func removeLoop() {
        loopPoints = []
        loopLayer.removeFromSuperlayer()
        loopHaloLayer.removeFromSuperlayer()
    }

    /// Selects the strokes and pictures that lie mostly inside a loop given in the canvas's
    /// own coordinates. A loop that takes nothing marks its area, whose menu takes a picture.
    func selectContents(enclosedBy loop: [CGPoint]) {
        let drawingLoop = loop.map(drawingPoint(fromCanvas:))
        let loopBounds = InkLasso.bounds(of: drawingLoop)
        guard !loopBounds.isNull else { return }
        let strokeIndices = canvas.drawing.strokes.enumerated().compactMap { strokeIndex, stroke -> Int? in
            guard stroke.renderBounds.intersects(loopBounds) else { return nil }
            return InkLasso.enclosedFraction(of: Self.samplePoints(of: stroke), inLoop: drawingLoop) >= InkLasso.minimumEnclosedFraction ? strokeIndex : nil
        }
        let pictureIdentifiers = (content?.lassoPictures() ?? []).compactMap { picture -> String? in
            guard picture.boundingFrame.intersects(loopBounds) else { return nil }
            let samples = InkLasso.samplePoints(ofRectangle: picture.frame, turnedBy: picture.rotationRadians)
            return InkLasso.enclosedFraction(of: samples, inLoop: drawingLoop) >= InkLasso.minimumEnclosedFraction ? picture.identifier : nil
        }
        if strokeIndices.isEmpty, pictureIdentifiers.isEmpty {
            markArea(drawingLoop)
        } else {
            select(strokeIndices, pictures: pictureIdentifiers)
            lassoedLoop = drawingLoop
        }
    }

    /// Where a stroke runs, in the drawing's coordinates. A dot, such as the dot of an "i",
    /// has a single point, from which PencilKit interpolates none; it is its own point then,
    /// or the middle of its ink, so a loop around it takes it.
    private static func samplePoints(of stroke: PKStroke) -> [CGPoint] {
        let interpolated = stroke.path.interpolatedPoints(by: .distance(4)).map { point in point.location.applying(stroke.transform) }
        if !interpolated.isEmpty { return interpolated }
        let controlPoints = stroke.path.map { point in point.location.applying(stroke.transform) }
        if !controlPoints.isEmpty { return controlPoints }
        return [CGPoint(x: stroke.renderBounds.midX, y: stroke.renderBounds.midY)]
    }

    /// Selects the topmost stroke passing near a point of the canvas; false when there is
    /// none, and the selection then ends.
    @discardableResult
    func selectStroke(at point: CGPoint) -> Bool {
        let drawingPoint = drawingPoint(fromCanvas: point)
        let reach = InkLasso.tapReach / screenPointsPerCanvasPoint / zoomScale
        let touchedIndex = canvas.drawing.strokes.enumerated().reversed().first { _, stroke in
            guard stroke.renderBounds.insetBy(dx: -reach, dy: -reach).contains(drawingPoint) else { return false }
            let points = stroke.path.interpolatedPoints(by: .distance(4)).map { strokePoint in
                (location: strokePoint.location.applying(stroke.transform), radius: strokePoint.size.width / 2)
            }
            // A dot has no interpolated points; its ink is where it is.
            guard !points.isEmpty else { return true }
            return points.contains { location, radius in hypot(location.x - drawingPoint.x, location.y - drawingPoint.y) <= reach + radius }
        }?.offset
        select(touchedIndex.map { index in [index] } ?? [])
        return touchedIndex != nil
    }

    /// Selects the strokes at the positions in the canvas's drawing and the named pictures,
    /// and shows their menu.
    func select(_ strokeIndices: [Int], pictures pictureIdentifiers: [String] = []) {
        removeArea()
        let strokeCount = canvas.drawing.strokes.count
        selectedStrokeIndices = Array(Set(strokeIndices.filter { index in (0..<strokeCount).contains(index) })).sorted()
        let existingPictures = Set((content?.lassoPictures() ?? []).map(\.identifier))
        selectedPictureIdentifiers = pictureIdentifiers.filter(existingPictures.contains)
        lassoedLoop = nil
        guard hasSelection else { return clearSelection() }
        takeSelectionFromOtherCanvases()
        showSelectionFrame()
        presentSelectionMenu()
    }

    /// Marks an area the lasso enclosed that holds nothing selectable, and offers its menu.
    private func markArea(_ drawingLoop: [CGPoint]) {
        clearSelection()
        takeSelectionFromOtherCanvases()
        lassoedLoop = drawingLoop
        isShowingLassoedArea = true
        loopPoints = drawingLoop.map { point in CGPoint(x: point.x * zoomScale, y: point.y * zoomScale) }
        showLoop(isFinished: true)
        let bounds = InkLasso.bounds(of: loopPoints)
        canvasMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: MenuIdentifier.area as NSString, sourcePoint: CGPoint(x: bounds.midX, y: bounds.minY)))
    }

    private func removeArea() {
        guard isShowingLassoedArea else { return }
        isShowingLassoedArea = false
        lassoedLoop = nil
        removeLoop()
    }

    private func takeSelectionFromOtherCanvases() {
        if let other = Self.controllerWithSelection, other !== self { other.clearSelection() }
        Self.controllerWithSelection = self
    }

    var hasSelection: Bool { !selectedStrokeIndices.isEmpty || !selectedPictureIdentifiers.isEmpty }

    func clearSelection() {
        if dragStart != nil { content?.setLassoPicturesHidden([]) }
        selectedStrokeIndices = []
        selectedPictureIdentifiers = []
        dragStart = nil
        selectionView?.removeFromSuperview()
        selectionView = nil
        removeArea()
        lassoedLoop = nil
        removeLoop()
        if Self.controllerWithSelection === self { Self.controllerWithSelection = nil }
    }

    var selectedStrokes: [PKStroke] {
        let strokes = canvas.drawing.strokes
        return selectedStrokeIndices.filter { index in strokes.indices.contains(index) }.map { index in strokes[index] }
    }

    var selectedPictures: [LassoPicture] {
        let selected = Set(selectedPictureIdentifiers)
        return (content?.lassoPictures() ?? []).filter { picture in selected.contains(picture.identifier) }
    }

    /// The selection's frame in the canvas's own coordinates; nil without a selection.
    var selectionFrame: CGRect? { selectionView?.frame }

    // MARK: The selection's frame

    /// The room between the selection and the frame around it, in the canvas's own points.
    private var frameMargin: CGFloat { Self.frameMargin / screenPointsPerCanvasPoint }

    /// The selected ink and pictures' extent, in the drawing's coordinates.
    private func contentBounds(strokes: [PKStroke], pictures: [LassoPicture]) -> CGRect {
        let inkBounds = strokes.reduce(CGRect.null) { bounds, stroke in bounds.union(stroke.renderBounds) }
        return pictures.reduce(inkBounds) { bounds, picture in bounds.union(picture.boundingFrame) }
    }

    private func frame(around strokes: [PKStroke], pictures: [LassoPicture]) -> CGRect {
        canvasRectangle(fromDrawing: contentBounds(strokes: strokes, pictures: pictures)).insetBy(dx: -frameMargin, dy: -frameMargin)
    }

    private func showSelectionFrame() {
        let selection = selectionView ?? makeSelectionView()
        selection.contentScale = screenPointsPerCanvasPoint
        selection.minimumSideLength = 24 / screenPointsPerCanvasPoint + 2 * frameMargin
        selection.dragPreviewInset = frameMargin
        selection.frame = frame(around: selectedStrokes, pictures: selectedPictures)
        selection.accessibilityLabel = selectionDescription
        selection.additionalAccessibilityActions = accessibilityActions()
        if selection.superview !== canvas { canvas.addSubview(selection) }
        shownScreenScale = screenPointsPerCanvasPoint
    }

    /// The canvas was zoomed or scrolled: the frame and a marked area are placed again, and
    /// drawn at the same size on screen, unless a drag is moving the frame.
    func canvasDidChangeScale() {
        guard hasSelection || isShowingLassoedArea, dragStart == nil else { return }
        let scale = screenPointsPerCanvasPoint
        if hasSelection, let selectionView {
            let expectedFrame = frame(around: selectedStrokes, pictures: selectedPictures)
            if abs(scale - shownScreenScale) > 0.001 || selectionView.frame != expectedFrame { showSelectionFrame() }
        }
        if isShowingLassoedArea, let lassoedLoop {
            let shownLoop = lassoedLoop.map { point in CGPoint(x: point.x * zoomScale, y: point.y * zoomScale) }
            if abs(scale - shownScreenScale) > 0.001 || shownLoop != loopPoints {
                loopPoints = shownLoop
                showLoop(isFinished: true)
            }
        }
    }

    private var selectionDescription: String {
        switch (selectedStrokeIndices.isEmpty, selectedPictureIdentifiers.isEmpty) {
        case (false, true): "Selected ink"
        case (true, false): selectedPictureIdentifiers.count == 1 ? "Selected image" : "Selected images"
        default: "Selected ink and images"
        }
    }

    private func makeSelectionView() -> SelectionFrameView {
        let selection = SelectionFrameView(frame: .zero)
        selection.dragPreviewOpacity = 1
        selection.frameChangeDidBegin = { [weak self] in self?.selectionDragDidBegin() }
        selection.frameChangeDidEnd = { [weak self] frame in self?.selectionDragDidEnd(at: frame) }
        selection.frameChangeWasCancelled = { [weak self] in self?.selectionDragWasCancelled() }
        selection.addGestureRecognizer(selectionTapRecognizer)
        selection.addInteraction(selectionMenu)
        // Dragging the selection must not scroll the page, or the drawing, with it.
        var ancestor: UIView? = canvas
        while let view = ancestor {
            if let scrollView = view as? UIScrollView {
                for recognizer in selection.dragRecognizers { scrollView.panGestureRecognizer.require(toFail: recognizer) }
            }
            ancestor = view.superview
        }
        selectionView = selection
        return selection
    }

    private func selectionDragDidBegin() {
        guard let selectionView, hasSelection else { return }
        let drawing = canvas.drawing
        let pictures = selectedPictures
        dragStart = (drawing, pictures, selectionView.frame)
        selectionView.dragPreview = picture(of: selectedStrokes, pictures: pictures, in: selectionView.frame.insetBy(dx: frameMargin, dy: frameMargin))
        let selected = Set(selectedStrokeIndices)
        if !selected.isEmpty {
            canvas.showWithoutRecording(PKDrawing(strokes: drawing.strokes.enumerated().filter { index, _ in !selected.contains(index) }.map(\.element)))
        }
        content?.setLassoPicturesHidden(Set(selectedPictureIdentifiers))
    }

    private func selectionDragDidEnd(at frame: CGRect) {
        guard let dragStart else { return }
        self.dragStart = nil
        selectionView?.dragPreview = nil
        content?.setLassoPicturesHidden([])
        moveSelection(in: dragStart.drawing, pictures: dragStart.pictures, from: dragStart.frame, to: frame)
    }

    private func selectionDragWasCancelled() {
        guard let dragStart else { return }
        self.dragStart = nil
        selectionView?.dragPreview = nil
        content?.setLassoPicturesHidden([])
        if !selectedStrokeIndices.isEmpty { canvas.showWithoutRecording(dragStart.drawing) }
    }

    /// Moves and resizes the selected strokes of a drawing so that the ink `frame` was
    /// around is inside `newFrame`, both selection frames in the canvas's own coordinates.
    func moveSelection(in drawing: PKDrawing, from frame: CGRect, to newFrame: CGRect) {
        moveSelection(in: drawing, pictures: selectedPictures, from: frame, to: newFrame)
    }

    /// Moves and resizes the selected strokes and pictures together, as one step of the
    /// history: the ink's change and the pictures' are made in the same turn of the run
    /// loop, which the history groups into one step.
    private func moveSelection(in drawing: PKDrawing, pictures: [LassoPicture], from frame: CGRect, to newFrame: CGRect) {
        let toDrawing = CGAffineTransform(scaleX: 1 / zoomScale, y: 1 / zoomScale)
        // The frames keep the same margin around the selection, whatever its size.
        let targetBounds = newFrame.insetBy(dx: frameMargin, dy: frameMargin).applying(toDrawing)
        guard targetBounds.width > 0, targetBounds.height > 0 else { return }
        var transform = InkLasso.transform(from: frame.insetBy(dx: frameMargin, dy: frameMargin).applying(toDrawing), to: targetBounds)
        let strokes = drawing.strokes
        let selectedStrokes = selectedStrokeIndices.filter { index in strokes.indices.contains(index) }.map { index in strokes[index] }
        // PencilKit's render bounds include padding that does not scale with the stroke's
        // points. Correct against the rebuilt ink before committing one undoable change,
        // so the frame does not jump after a resize, particularly on a zoomed-out page.
        let maximumBoundsCorrectionAttempts = 3
        let tolerance = 0.25 / zoomScale
        for _ in 0..<maximumBoundsCorrectionAttempts {
            let renderedInk = selectedStrokes.reduce(CGRect.null) { bounds, stroke in
                bounds.union(Self.stroke(stroke, ink: stroke.ink, movedBy: transform).renderBounds)
            }
            let renderedBounds = pictures.reduce(renderedInk) { bounds, picture in bounds.union(picture.boundingFrame.applying(transform)) }
            guard !renderedBounds.isNull, renderedBounds.width > 0, renderedBounds.height > 0 else { return }
            if abs(renderedBounds.minX - targetBounds.minX) < tolerance, abs(renderedBounds.minY - targetBounds.minY) < tolerance,
               abs(renderedBounds.width - targetBounds.width) < tolerance { break }
            transform = transform.concatenating(InkLasso.transform(from: renderedBounds, to: targetBounds))
        }
        if !selectedStrokes.isEmpty {
            replaceSelectedStrokes(in: drawing, showingFrame: false) { stroke in Self.stroke(stroke, ink: stroke.ink, movedBy: transform) }
        }
        if !pictures.isEmpty {
            // Each picture keeps its angle about its own middle, which the transform carries
            // along: it scales evenly and moves, but does not turn.
            let newFrames = Dictionary(uniqueKeysWithValues: pictures.map { picture in (picture.identifier, picture.frame.applying(transform)) })
            content?.moveLassoPictures(to: newFrames)
        }
        lassoedLoop = nil
        if hasSelection { showSelectionFrame() }
    }

    /// The picture of strokes and pictures as the canvas shows them inside a frame of its
    /// own coordinates.
    private func picture(of strokes: [PKStroke], pictures: [LassoPicture], in frame: CGRect) -> UIImage? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        let drawingFrame = drawingRectangle(fromCanvas: frame)
        let screenScale = canvas.window?.screen.scale ?? canvas.traitCollection.displayScale
        let wantedScale = zoomScale * screenPointsPerCanvasPoint * screenScale
        let largestScale = Self.maximumPreviewSideInPixels / max(drawingFrame.width, drawingFrame.height)
        let scale = min(wantedScale, largestScale)
        var inkPicture: UIImage?
        // Inks are drawn as the canvas draws them, which depends on its appearance.
        canvas.traitCollection.performAsCurrent {
            if !strokes.isEmpty { inkPicture = PKDrawing(strokes: strokes).image(from: drawingFrame, scale: scale) }
        }
        guard !pictures.isEmpty else { return inkPicture }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: drawingFrame.size, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            context.translateBy(x: -drawingFrame.minX, y: -drawingFrame.minY)
            for picture in pictures {
                guard let image = content?.lassoPictureImage(picture.identifier) else { continue }
                LassoAreaCapture.draw(image, in: picture.frame, turnedBy: picture.rotationRadians, context: context)
            }
            context.translateBy(x: drawingFrame.minX, y: drawingFrame.minY)
            inkPicture?.draw(in: CGRect(origin: .zero, size: drawingFrame.size))
        }
    }

    // MARK: Changing the selection

    /// A new stroke like another, in an ink of its own and moved or resized by a transform.
    ///
    /// It is built from its parts. PencilKit tells strokes apart by an identity of their own
    /// and keeps showing the version it already shows: a copy of a stroke with another ink
    /// or transform is the same stroke to it, and the canvas would not change. And the
    /// transform is applied to the points themselves, their sizes included: a stroke scaled
    /// through its `transform` is drawn broader on the canvas but comes back from the saved
    /// drawing at its old breadth.
    private static func stroke(_ stroke: PKStroke, ink: PKInk, movedBy transform: CGAffineTransform = .identity) -> PKStroke {
        let placement = stroke.transform.concatenating(transform)
        let sizeScale = abs(placement.a * placement.d - placement.b * placement.c).squareRoot()
        let points = stroke.path.map { point in
            PKStrokePoint(location: point.location.applying(placement), timeOffset: point.timeOffset,
                          size: CGSize(width: point.size.width * sizeScale, height: point.size.height * sizeScale),
                          opacity: point.opacity, force: point.force, azimuth: point.azimuth, altitude: point.altitude,
                          secondaryScale: point.secondaryScale)
        }
        // The pixel eraser's mask is in the stroke's own space and moves with it.
        let mask = stroke.mask.flatMap { mask -> UIBezierPath? in
            guard let placedMask = mask.copy() as? UIBezierPath else { return nil }
            placedMask.apply(placement)
            return placedMask
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate),
                        transform: .identity, mask: mask, randomSeed: stroke.randomSeed)
    }

    /// Replaces each selected stroke of a drawing and gives the canvas the result as one change.
    private func replaceSelectedStrokes(in drawing: PKDrawing, showingFrame: Bool = true, with change: (PKStroke) -> PKStroke) {
        var strokes = drawing.strokes
        for index in selectedStrokeIndices where strokes.indices.contains(index) { strokes[index] = change(strokes[index]) }
        canvas.setDrawingMadeByCanvas(PKDrawing(strokes: strokes))
        if showingFrame, hasSelection { showSelectionFrame() }
    }

    /// Gives the selected strokes a color, each keeping its own ink and opacity.
    func recolorSelection(_ color: UIColor) {
        guard !selectedStrokeIndices.isEmpty else { return }
        replaceSelectedStrokes(in: canvas.drawing) { stroke in
            Self.stroke(stroke, ink: PKInk(stroke.ink.inkType, color: color.withAlphaComponent(stroke.ink.color.cgColor.alpha)))
        }
    }

    /// The slant of the selected ink when it reads as one line of writing that runs uphill
    /// or downhill (`HandwritingTidying`), in the drawing's coordinates.
    var selectionSlant: CGFloat? {
        HandwritingTidying.slantOfLine(through: selectedStrokes.flatMap { stroke in
            stroke.path.map { point in point.location.applying(stroke.transform) }
        })
    }

    /// Turns the selected line of writing level about its middle.
    func straightenSelection() {
        guard let slant = selectionSlant else { return }
        let inkBounds = selectedStrokes.reduce(CGRect.null) { bounds, stroke in bounds.union(stroke.renderBounds) }
        guard !inkBounds.isNull else { return }
        let rotation = CGAffineTransform(translationX: inkBounds.midX, y: inkBounds.midY).rotated(by: -slant)
            .translatedBy(x: -inkBounds.midX, y: -inkBounds.midY)
        lassoedLoop = nil
        replaceSelectedStrokes(in: canvas.drawing) { stroke in Self.stroke(stroke, ink: stroke.ink, movedBy: rotation) }
    }

    /// Smooths the tremor out of the selected strokes; their ends stay where they are.
    ///
    /// The document's history and its saved ink tell strokes apart by their creation time,
    /// point count and ends (`PDFStrokeFingerprint`), which smoothing keeps; a smoothed
    /// stroke is therefore given the time it was smoothed as its creation time, so it is
    /// recorded and saved as the new stroke it is.
    func smoothSelection() {
        guard !selectedStrokeIndices.isEmpty else { return }
        let smoothingTime = Date()
        replaceSelectedStrokes(in: canvas.drawing) { stroke in
            let placedStroke = Self.stroke(stroke, ink: stroke.ink)
            let points = Array(placedStroke.path)
            let smoothedLocations = HandwritingTidying.smoothed(points.map(\.location))
            let smoothedPoints = zip(points, smoothedLocations).map { point, location in
                PKStrokePoint(location: location, timeOffset: point.timeOffset, size: point.size, opacity: point.opacity, force: point.force,
                              azimuth: point.azimuth, altitude: point.altitude, secondaryScale: point.secondaryScale)
            }
            guard smoothedLocations != points.map(\.location) else { return stroke }
            return PKStroke(ink: placedStroke.ink, path: PKStrokePath(controlPoints: smoothedPoints, creationDate: smoothingTime),
                            transform: .identity, mask: placedStroke.mask, randomSeed: placedStroke.randomSeed)
        }
    }

    /// Removes the selected strokes and pictures as one step of the history.
    func deleteSelection() {
        let selected = Set(selectedStrokeIndices)
        let pictureIdentifiers = selectedPictureIdentifiers
        let remainingStrokes = canvas.drawing.strokes.enumerated().filter { index, _ in !selected.contains(index) }.map(\.element)
        clearSelection()
        if !selected.isEmpty { canvas.setDrawingMadeByCanvas(PKDrawing(strokes: remainingStrokes)) }
        if !pictureIdentifiers.isEmpty { content?.deleteLassoPictures(pictureIdentifiers) }
    }

    /// Adds copies of the selected strokes a little down and to the right, and selects them.
    func duplicateSelection() {
        let offset = CGAffineTransform(translationX: Self.duplicateOffset.width / zoomScale, y: Self.duplicateOffset.height / zoomScale)
        add(selectedStrokes.map { stroke in Self.stroke(stroke, ink: stroke.ink, movedBy: offset) })
    }

    /// Adds strokes after all others and selects them.
    private func add(_ newStrokes: [PKStroke]) {
        guard !newStrokes.isEmpty else { return }
        let strokes = canvas.drawing.strokes
        canvas.setDrawingMadeByCanvas(PKDrawing(strokes: strokes + newStrokes))
        select(Array(strokes.count..<(strokes.count + newStrokes.count)))
    }

    /// Puts the selected strokes on the pasteboard as a PencilKit drawing, which Notes and
    /// other PencilKit canvases paste as ink, and as a picture for everything else. With
    /// pictures selected, only the picture of the whole selection goes: Graphite pastes
    /// ink as ink, and pictures pasted as ink would be lost.
    func copySelection() {
        let strokes = selectedStrokes
        let pictures = selectedPictures
        guard !strokes.isEmpty || !pictures.isEmpty else { return }
        let drawing = PKDrawing(strokes: strokes)
        var pasteboardItem: [String: Any] = [:]
        if pictures.isEmpty { pasteboardItem[PKAppleDrawingTypeIdentifier as String] = drawing.dataRepresentation() }
        let region = contentBounds(strokes: strokes, pictures: pictures).insetBy(dx: -4, dy: -4)
        let picture = LassoAreaCapture.image(of: region, drawing: drawing, content: pictures.isEmpty ? nil : SelectedPicturesContent(controller: self, pictures: pictures),
                                             screenPixelsPerPoint: 2)
        if let pictureData = picture?.pngData() { pasteboardItem[UTType.png.identifier] = pictureData }
        UIPasteboard.general.items = [pasteboardItem]
    }

    func cutSelection() {
        copySelection()
        deleteSelection()
    }

    private static func strokesOnPasteboard() -> [PKStroke]? {
        guard let drawingData = UIPasteboard.general.data(forPasteboardType: PKAppleDrawingTypeIdentifier as String),
              let drawing = try? PKDrawing(data: drawingData), !drawing.strokes.isEmpty else { return nil }
        return drawing.strokes
    }

    /// Adds the ink on the pasteboard with its middle at a point of the canvas, and selects it.
    func pasteInk(at point: CGPoint) {
        guard let strokes = Self.strokesOnPasteboard() else { return }
        let inkBounds = strokes.reduce(CGRect.null) { bounds, stroke in bounds.union(stroke.renderBounds) }
        let offset = CGAffineTransform(translationX: point.x / zoomScale - inkBounds.midX, y: point.y / zoomScale - inkBounds.midY)
        add(strokes.map { stroke in Self.stroke(stroke, ink: stroke.ink, movedBy: offset) })
    }

    // MARK: Pictures of an area

    /// The area a picture is taken of, in the drawing's coordinates: the lassoed area, or
    /// the selection with its margin when it was made with a tap or has moved.
    var captureRegion: CGRect? {
        let region: CGRect
        if let lassoedLoop {
            region = InkLasso.bounds(of: lassoedLoop)
        } else if hasSelection {
            let margin = Self.frameMargin / screenPointsPerCanvasPoint / zoomScale
            region = contentBounds(strokes: selectedStrokes, pictures: selectedPictures).insetBy(dx: -margin, dy: -margin)
        } else {
            return nil
        }
        // A loop drawn past the page's edge takes the page, not the gray around it.
        let keptRegion = content.map { content in region.intersection(content.lassoDrawingBounds) } ?? region
        return keptRegion.isNull || keptRegion.isEmpty ? nil : keptRegion
    }

    /// The picture of the area: what lies under the ink, the pictures and the ink, at print
    /// resolution or the screen's when that is finer.
    func captureImage() -> UIImage? {
        guard let captureRegion else { return nil }
        let screenScale = canvas.window?.screen.scale ?? canvas.traitCollection.displayScale
        return LassoAreaCapture.image(of: captureRegion, drawing: canvas.drawing, content: content,
                                      screenPixelsPerPoint: screenScale * screenPointsPerCanvasPoint * zoomScale)
    }

    /// Takes the picture of the area and offers it in the share sheet: Copy, Save Image,
    /// sharing, and Add to Note when there is a note to add it to.
    func takeScreenshot() {
        guard let captureRegion, let image = captureImage() else { return }
        let sourceRect = canvasRectangle(fromDrawing: captureRegion)
        let name = content?.lassoCaptureName ?? "Screenshot"
        let destination = content?.lassoNoteDestination
        // The marked area has done its work; a selection stays to be worked on.
        if isShowingLassoedArea { removeArea() }
        LassoAreaCapture.presentShareSheet(for: image, name: name, destination: destination, from: canvas, sourceRect: sourceRect)
    }

    // MARK: Menus

    private enum MenuIdentifier {
        static let selection = "selection"
        static let paste = "paste"
        static let area = "area"
    }

    @objc private func handleSelectionTap(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended { presentSelectionMenu() }
    }

    private func presentSelectionMenu() {
        guard let selectionView, selectionView.window != nil else { return }
        selectionMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: MenuIdentifier.selection as NSString,
                                                                    sourcePoint: CGPoint(x: selectionView.bounds.midX, y: selectionView.bounds.minY)))
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        if interaction === canvasMenu {
            if (configuration.identifier as? String) == MenuIdentifier.area { return UIMenu(children: areaMenuElements()) }
            return UIMenu(children: [UIAction(title: "Paste", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in
                guard let self else { return }
                self.pasteInk(at: self.pastePoint)
            }])
        }
        return UIMenu(children: selectionMenuElements())
    }

    /// The menu of an area that holds nothing selectable: its picture, and the ink on the
    /// pasteboard placed in its middle.
    func areaMenuElements() -> [UIMenuElement] {
        var elements: [UIMenuElement] = [takeScreenshotAction]
        if Self.strokesOnPasteboard() != nil, let lassoedLoop {
            let bounds = InkLasso.bounds(of: lassoedLoop)
            elements.append(UIAction(title: "Paste", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in
                guard let self else { return }
                self.removeArea()
                self.pasteInk(at: CGPoint(x: bounds.midX * self.zoomScale, y: bounds.midY * self.zoomScale))
            })
        }
        return elements
    }

    private var takeScreenshotAction: UIAction {
        UIAction(title: "Take Screenshot", image: UIImage(systemName: "camera.viewfinder")) { [weak self] _ in self?.takeScreenshot() }
    }

    /// Cut, Copy, Duplicate, Take Screenshot, Straighten (for a line of writing that runs
    /// uphill or downhill), Smooth, Delete, and the colors of Settings › Colors. With
    /// pictures selected, Cut and Duplicate are not offered: Graphite pastes ink, not
    /// pictures, and Copy puts a picture of the whole selection on the pasteboard.
    func selectionMenuElements(palette: [PaletteColor] = GraphitePreferences.storedColorPalette()) -> [UIMenuElement] {
        let hasInk = !selectedStrokeIndices.isEmpty
        let hasPictures = !selectedPictureIdentifiers.isEmpty
        var elements: [UIMenuElement] = []
        if !hasPictures {
            elements.append(UIAction(title: "Cut", image: UIImage(systemName: "scissors")) { [weak self] _ in self?.cutSelection() })
        }
        elements.append(UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in self?.copySelection() })
        if !hasPictures {
            elements.append(UIAction(title: "Duplicate", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in self?.duplicateSelection() })
        }
        // Early, where the compact menu shows it without paging.
        elements.append(takeScreenshotAction)
        if hasInk, selectionSlant != nil {
            elements.append(UIAction(title: "Straighten", image: UIImage(systemName: "level")) { [weak self] _ in self?.straightenSelection() })
        }
        if hasInk {
            elements.append(UIAction(title: "Smooth", image: UIImage(systemName: "scribble.variable")) { [weak self] _ in self?.smoothSelection() })
        }
        elements += [
            UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.deleteSelection() },
        ]
        if hasInk {
            let colors = [PaletteColor(name: "black", hex: PencilInk.pen.defaultColorHex)] + palette
            let swatches = colors.compactMap { favorite -> UIAction? in
                guard let color = UIColor(graphiteHex: favorite.hex) else { return nil }
                let swatch = UIImage(systemName: "circle.fill")?.withTintColor(color, renderingMode: .alwaysOriginal)
                return UIAction(title: favorite.name, image: swatch) { [weak self] _ in self?.recolorSelection(color) }
            }
            elements.append(UIMenu(title: "Color", image: UIImage(systemName: "paintpalette"), options: .displayAsPalette, children: swatches))
        }
        return elements
    }

    /// The menu's actions for VoiceOver, on the frame itself, where the menu is out of reach
    /// once VoiceOver moves on.
    private func accessibilityActions() -> [UIAccessibilityCustomAction] {
        selectionMenuElements().compactMap { element -> UIAccessibilityCustomAction? in
            guard let action = element as? UIAction else { return nil }
            return UIAccessibilityCustomAction(name: action.title) { [weak self] _ in
                guard let self else { return false }
                self.performMenuAction(named: action.title)
                return true
            }
        }
    }

    private func performMenuAction(named title: String) {
        switch title {
        case "Cut": cutSelection()
        case "Copy": copySelection()
        case "Duplicate": duplicateSelection()
        case "Straighten": straightenSelection()
        case "Smooth": smoothSelection()
        case "Take Screenshot": takeScreenshot()
        case "Delete": deleteSelection()
        default: break
        }
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        if interaction === canvasMenu {
            if (configuration.identifier as? String) == MenuIdentifier.area, let lassoedLoop {
                return canvasRectangle(fromDrawing: InkLasso.bounds(of: lassoedLoop))
            }
            return CGRect(origin: pastePoint, size: .zero)
        }
        return selectionView?.bounds ?? .null
    }
}

/// The selected pictures alone, for the picture Copy puts on the pasteboard.
@MainActor
private final class SelectedPicturesContent: LassoCanvasContent {
    private weak var controller: InkSelectionController?
    private let pictures: [LassoPicture]
    private let images: [String: UIImage]

    init(controller: InkSelectionController, pictures: [LassoPicture]) {
        self.controller = controller
        self.pictures = pictures
        let canvasContent = controller.content
        images = Dictionary(uniqueKeysWithValues: pictures.compactMap { picture in
            canvasContent?.lassoPictureImage(picture.identifier).map { image in (picture.identifier, image) }
        })
    }

    func lassoPictures() -> [LassoPicture] { pictures }
    func lassoPictureImage(_ identifier: String) -> UIImage? { images[identifier] }
    func moveLassoPictures(to frames: [String: CGRect]) {}
    func deleteLassoPictures(_ identifiers: [String]) {}
    func setLassoPicturesHidden(_ identifiers: Set<String>) {}
    func drawContentUnderInk(in context: CGContext, region: CGRect) {
        for picture in pictures {
            guard let image = images[picture.identifier] else { continue }
            LassoAreaCapture.draw(image, in: picture.frame, turnedBy: picture.rotationRadians, context: context)
        }
    }
    var lassoDisplayQuarterTurns: Int { controller?.content?.lassoDisplayQuarterTurns ?? 0 }
    var lassoDrawingBounds: CGRect { .infinite }
    var lassoCaptureName: String { "Selection" }
    var lassoNoteDestination: LassoNoteDestination? { nil }
}
#endif
