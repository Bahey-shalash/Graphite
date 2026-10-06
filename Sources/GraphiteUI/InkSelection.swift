import Foundation
import CoreGraphics

/// The geometry of Graphite's lasso: which strokes a loop takes, and how a moved or resized
/// selection frame carries its strokes along.
enum InkLasso {
    /// A stroke is taken when at least this much of it lies inside the loop, so a loop
    /// drawn around a word does not take the long line passing under it.
    static let minimumEnclosedFraction = 0.6
    /// A loop shorter than this, in screen points, is a tap.
    static let minimumLoopLength: CGFloat = 24
    /// A tap takes the stroke that passes within this distance of it, in screen points.
    static let tapReach: CGFloat = 14

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

/// Whether the canvases that follow the floating palette select ink with Graphite's lasso.
/// The palette's own lasso is PencilKit's, which can neither resize nor recolor what it
/// selects and tells nobody what that is; Graphite's is switched on from the palette's
/// accessory menu and off again by choosing any tool. It is not kept between launches.
@MainActor
enum PaletteInkSelection {
    static let didChange = Notification.Name("GraphitePaletteInkSelectionDidChange")
    static var isOn = false {
        didSet { if isOn != oldValue { NotificationCenter.default.post(name: didChange, object: nil) } }
    }
}

#if canImport(UIKit)
import UIKit
import PencilKit
import UniformTypeIdentifiers
import GraphiteCore

/// Graphite's lasso on one canvas. A loop drawn around strokes, or a tap on one, selects
/// them; the selection's frame moves and resizes them, and its menu cuts, copies,
/// duplicates, deletes and recolors them. Every change is one change of the canvas's
/// drawing, so it is one step of the document's history like any stroke.
///
/// The selection is the positions of its strokes in the canvas's drawing. While its frame
/// is dragged, the canvas shows the drawing without them and the frame shows their picture;
/// the strokes themselves move when the drag ends.
@MainActor
final class InkSelectionController: NSObject, UIGestureRecognizerDelegate, @preconcurrency UIEditMenuInteractionDelegate {
    private unowned let canvas: HistoryCanvasView
    private(set) var selectedStrokeIndices: [Int] = []
    /// Only one canvas has a selection at a time, as only one page is written on at a time.
    private static weak var controllerWithSelection: InkSelectionController?

    private lazy var loopRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleLoop(_:)))
    private lazy var tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    private lazy var selectionTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleSelectionTap(_:)))
    private lazy var selectionMenu = UIEditMenuInteraction(delegate: self)
    private lazy var pasteMenu = UIEditMenuInteraction(delegate: self)
    private let loopLayer = CAShapeLayer()
    private var loopPoints: [CGPoint] = []
    private var selectionView: SelectionFrameView?
    /// The drawing and the frame when a drag of the selection began.
    private var dragStart: (drawing: PKDrawing, frame: CGRect)?
    private var pastePoint: CGPoint = .zero

    /// The frame reaches this far beyond the ink, so its handles are clear of it.
    private static let frameMargin: CGFloat = 8
    private static let duplicateOffset = CGSize(width: 16, height: 16)
    /// The most pixels along one side of the picture shown while a selection is dragged.
    private static let maximumPreviewSideInPixels: CGFloat = 4_096

    init(canvas: HistoryCanvasView) {
        self.canvas = canvas
    }

    /// Whether the canvas selects instead of drawing. Switching it off ends the selection.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if isActive {
                installRecognizers()
            } else {
                clearSelection()
                removeLoop()
            }
            loopRecognizer.isEnabled = isActive
            tapRecognizer.isEnabled = isActive
        }
    }

    private func installRecognizers() {
        guard loopRecognizer.view == nil else { return }
        loopRecognizer.maximumNumberOfTouches = 1
        loopRecognizer.delegate = self
        tapRecognizer.delegate = self
        canvas.addGestureRecognizer(loopRecognizer)
        canvas.addGestureRecognizer(tapRecognizer)
        canvas.addInteraction(pasteMenu)
    }

    /// The lasso takes the touches the canvas would draw with: the Pencil, and a finger when
    /// fingers draw. A touch on the selection's frame moves or resizes it and starts no loop.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard canvas.drawingGestureRecognizer.allowedTouchTypes.contains(NSNumber(value: touch.type.rawValue)) else { return false }
        guard let selectionView, let touchedView = touch.view else { return true }
        return !touchedView.isDescendant(of: selectionView)
    }

    // MARK: Selecting

    @objc private func handleLoop(_ recognizer: UIPanGestureRecognizer) {
        let point = recognizer.location(in: canvas)
        switch recognizer.state {
        case .began:
            clearSelection()
            loopPoints = [point]
            showLoop()
        case .changed:
            loopPoints.append(point)
            showLoop()
        case .ended:
            loopPoints.append(point)
            let loop = loopPoints
            removeLoop()
            if InkLasso.length(of: loop) >= InkLasso.minimumLoopLength { selectStrokes(enclosedBy: loop) }
        default:
            removeLoop()
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let point = recognizer.location(in: canvas)
        if !selectedStrokeIndices.isEmpty {
            clearSelection()
        } else if !selectStroke(at: point), Self.strokesOnPasteboard() != nil {
            pastePoint = point
            pasteMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: "paste", sourcePoint: point))
        }
    }

    private func showLoop() {
        guard let firstPoint = loopPoints.first else { return }
        let path = CGMutablePath()
        path.move(to: firstPoint)
        for point in loopPoints.dropFirst() { path.addLine(to: point) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        loopLayer.path = path
        loopLayer.fillColor = nil
        loopLayer.strokeColor = UIColor.label.withAlphaComponent(0.7).cgColor
        loopLayer.lineWidth = 1.5 / max(screenPointsPerCanvasPoint, 0.01)
        loopLayer.lineDashPattern = [6, 4]
        loopLayer.zPosition = 1
        if loopLayer.superlayer == nil { canvas.layer.addSublayer(loopLayer) }
        CATransaction.commit()
    }

    private func removeLoop() {
        loopPoints = []
        loopLayer.removeFromSuperlayer()
    }

    /// Selects the strokes that lie mostly inside a loop given in the canvas's own coordinates.
    func selectStrokes(enclosedBy loop: [CGPoint]) {
        guard canvas.zoomScale > 0 else { return }
        let drawingLoop = loop.map { point in CGPoint(x: point.x / canvas.zoomScale, y: point.y / canvas.zoomScale) }
        let loopBounds = drawingLoop.reduce(CGRect.null) { bounds, point in bounds.union(CGRect(origin: point, size: .zero)) }
        let indices = canvas.drawing.strokes.enumerated().compactMap { strokeIndex, stroke -> Int? in
            guard stroke.renderBounds.intersects(loopBounds) else { return nil }
            let strokePoints = stroke.path.interpolatedPoints(by: .distance(8)).map { point in point.location.applying(stroke.transform) }
            return InkLasso.enclosedFraction(of: strokePoints, inLoop: drawingLoop) >= InkLasso.minimumEnclosedFraction ? strokeIndex : nil
        }
        select(indices)
    }

    /// Selects the topmost stroke passing near a point of the canvas; false when there is none.
    @discardableResult
    func selectStroke(at point: CGPoint) -> Bool {
        guard canvas.zoomScale > 0 else { return false }
        let drawingPoint = CGPoint(x: point.x / canvas.zoomScale, y: point.y / canvas.zoomScale)
        let reach = InkLasso.tapReach / max(screenPointsPerCanvasPoint, 0.01) / canvas.zoomScale
        let touchedIndex = canvas.drawing.strokes.enumerated().reversed().first { _, stroke in
            guard stroke.renderBounds.insetBy(dx: -reach, dy: -reach).contains(drawingPoint) else { return false }
            return stroke.path.interpolatedPoints(by: .distance(4)).contains { strokePoint in
                let location = strokePoint.location.applying(stroke.transform)
                return hypot(location.x - drawingPoint.x, location.y - drawingPoint.y) <= reach + strokePoint.size.width / 2
            }
        }?.offset
        select(touchedIndex.map { index in [index] } ?? [])
        return touchedIndex != nil
    }

    /// Selects the strokes at the positions in the canvas's drawing, and shows their menu.
    func select(_ strokeIndices: [Int]) {
        let strokeCount = canvas.drawing.strokes.count
        selectedStrokeIndices = strokeIndices.filter { index in (0..<strokeCount).contains(index) }.sorted()
        guard !selectedStrokeIndices.isEmpty else { return clearSelection() }
        if let other = Self.controllerWithSelection, other !== self { other.clearSelection() }
        Self.controllerWithSelection = self
        showSelectionFrame()
        presentSelectionMenu()
    }

    func clearSelection() {
        selectedStrokeIndices = []
        dragStart = nil
        selectionView?.removeFromSuperview()
        selectionView = nil
        if Self.controllerWithSelection === self { Self.controllerWithSelection = nil }
    }

    var selectedStrokes: [PKStroke] {
        let strokes = canvas.drawing.strokes
        return selectedStrokeIndices.filter { index in strokes.indices.contains(index) }.map { index in strokes[index] }
    }

    /// The selection's frame in the canvas's own coordinates; nil without a selection.
    var selectionFrame: CGRect? { selectionView?.frame }

    // MARK: The selection's frame

    /// How large a point of the canvas is on screen: a PDF page's canvas is scaled with its page.
    private var screenPointsPerCanvasPoint: CGFloat {
        canvas.convert(CGRect(x: 0, y: 0, width: 1, height: 1), to: nil).width
    }

    /// The room between the ink and the frame around it, in the canvas's own points.
    private var frameMargin: CGFloat { Self.frameMargin / max(screenPointsPerCanvasPoint, 0.01) }

    private func frame(around strokes: [PKStroke]) -> CGRect {
        let inkBounds = strokes.reduce(CGRect.null) { bounds, stroke in bounds.union(stroke.renderBounds) }
        return CGRect(x: inkBounds.minX * canvas.zoomScale, y: inkBounds.minY * canvas.zoomScale,
                      width: inkBounds.width * canvas.zoomScale, height: inkBounds.height * canvas.zoomScale).insetBy(dx: -frameMargin, dy: -frameMargin)
    }

    private func showSelectionFrame() {
        let selection = selectionView ?? makeSelectionView()
        selection.contentScale = screenPointsPerCanvasPoint
        selection.minimumSideLength = 24 / max(screenPointsPerCanvasPoint, 0.01) + 2 * frameMargin
        selection.dragPreviewInset = frameMargin
        selection.frame = frame(around: selectedStrokes)
        canvas.addSubview(selection)
    }

    private func makeSelectionView() -> SelectionFrameView {
        let selection = SelectionFrameView(frame: .zero)
        selection.accessibilityLabel = "Selected ink"
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
        guard let selectionView, !selectedStrokeIndices.isEmpty else { return }
        let drawing = canvas.drawing
        dragStart = (drawing, selectionView.frame)
        selectionView.dragPreview = picture(of: selectedStrokes, in: selectionView.frame.insetBy(dx: frameMargin, dy: frameMargin))
        let selected = Set(selectedStrokeIndices)
        canvas.showWithoutRecording(PKDrawing(strokes: drawing.strokes.enumerated().filter { index, _ in !selected.contains(index) }.map(\.element)))
    }

    private func selectionDragDidEnd(at frame: CGRect) {
        guard let dragStart else { return }
        self.dragStart = nil
        selectionView?.dragPreview = nil
        moveSelection(in: dragStart.drawing, from: dragStart.frame, to: frame)
    }

    private func selectionDragWasCancelled() {
        guard let dragStart else { return }
        self.dragStart = nil
        selectionView?.dragPreview = nil
        canvas.showWithoutRecording(dragStart.drawing)
    }

    /// Moves and resizes the selected strokes of a drawing so that the ink `frame` was
    /// around is inside `newFrame`, both selection frames in the canvas's own coordinates.
    func moveSelection(in drawing: PKDrawing, from frame: CGRect, to newFrame: CGRect) {
        guard canvas.zoomScale > 0 else { return }
        let toDrawing = CGAffineTransform(scaleX: 1 / canvas.zoomScale, y: 1 / canvas.zoomScale)
        // The frames keep the same margin around the ink, whatever its size.
        let targetBounds = newFrame.insetBy(dx: frameMargin, dy: frameMargin).applying(toDrawing)
        guard targetBounds.width > 0, targetBounds.height > 0 else { return }
        var transform = InkLasso.transform(from: frame.insetBy(dx: frameMargin, dy: frameMargin).applying(toDrawing),
                                          to: targetBounds)
        let strokes = drawing.strokes
        let selectedStrokes = selectedStrokeIndices.filter { index in strokes.indices.contains(index) }.map { index in strokes[index] }
        // PencilKit's render bounds include padding that does not scale with the stroke's
        // points. Correct against the rebuilt ink before committing one undoable change,
        // so the frame does not jump after a resize, particularly on a zoomed-out page.
        let maximumBoundsCorrectionAttempts = 3
        for _ in 0..<maximumBoundsCorrectionAttempts {
            let renderedBounds = selectedStrokes.reduce(CGRect.null) { bounds, stroke in
                bounds.union(Self.stroke(stroke, ink: stroke.ink, movedBy: transform).renderBounds)
            }
            guard !renderedBounds.isNull, renderedBounds.width > 0, renderedBounds.height > 0 else { return }
            if abs(renderedBounds.minX - targetBounds.minX) < 0.25 / canvas.zoomScale,
               abs(renderedBounds.minY - targetBounds.minY) < 0.25 / canvas.zoomScale,
               abs(renderedBounds.width - targetBounds.width) < 0.25 / canvas.zoomScale { break }
            transform = transform.concatenating(InkLasso.transform(from: renderedBounds, to: targetBounds))
        }
        replaceSelectedStrokes(in: drawing) { stroke in
            Self.stroke(stroke, ink: stroke.ink, movedBy: transform)
        }
    }

    /// The picture of strokes as the canvas shows them inside a frame of its own coordinates.
    private func picture(of strokes: [PKStroke], in frame: CGRect) -> UIImage? {
        guard canvas.zoomScale > 0, frame.width > 0, frame.height > 0 else { return nil }
        let drawingFrame = frame.applying(CGAffineTransform(scaleX: 1 / canvas.zoomScale, y: 1 / canvas.zoomScale))
        let screenScale = canvas.window?.screen.scale ?? canvas.traitCollection.displayScale
        let wantedScale = canvas.zoomScale * screenPointsPerCanvasPoint * screenScale
        let largestScale = Self.maximumPreviewSideInPixels / max(drawingFrame.width, drawingFrame.height)
        var picture: UIImage?
        // Inks are drawn as the canvas draws them, which depends on its appearance.
        canvas.traitCollection.performAsCurrent {
            picture = PKDrawing(strokes: strokes).image(from: drawingFrame, scale: min(wantedScale, largestScale))
        }
        return picture
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
    private func replaceSelectedStrokes(in drawing: PKDrawing, with change: (PKStroke) -> PKStroke) {
        var strokes = drawing.strokes
        for index in selectedStrokeIndices where strokes.indices.contains(index) { strokes[index] = change(strokes[index]) }
        canvas.setDrawingMadeByCanvas(PKDrawing(strokes: strokes))
        if !selectedStrokeIndices.isEmpty { showSelectionFrame() }
    }

    /// Gives the selected strokes a color, each keeping its own ink and opacity.
    func recolorSelection(_ color: UIColor) {
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
        replaceSelectedStrokes(in: canvas.drawing) { stroke in Self.stroke(stroke, ink: stroke.ink, movedBy: rotation) }
    }

    /// Smooths the tremor out of the selected strokes; their ends stay where they are.
    ///
    /// The document's history and its saved ink tell strokes apart by their creation time,
    /// point count and ends (`PDFStrokeFingerprint`), which smoothing keeps; a smoothed
    /// stroke is therefore given the time it was smoothed as its creation time, so it is
    /// recorded and saved as the new stroke it is.
    func smoothSelection() {
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

    func deleteSelection() {
        let selected = Set(selectedStrokeIndices)
        let remainingStrokes = canvas.drawing.strokes.enumerated().filter { index, _ in !selected.contains(index) }.map(\.element)
        clearSelection()
        canvas.setDrawingMadeByCanvas(PKDrawing(strokes: remainingStrokes))
    }

    /// Adds copies of the selected strokes a little down and to the right, and selects them.
    func duplicateSelection() {
        let offset = CGAffineTransform(translationX: Self.duplicateOffset.width / canvas.zoomScale, y: Self.duplicateOffset.height / canvas.zoomScale)
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
    /// other PencilKit canvases paste as ink, and as a picture for everything else.
    func copySelection() {
        let strokes = selectedStrokes
        guard !strokes.isEmpty else { return }
        let drawing = PKDrawing(strokes: strokes)
        var pasteboardItem: [String: Any] = [PKAppleDrawingTypeIdentifier as String: drawing.dataRepresentation()]
        var picture: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            picture = drawing.image(from: drawing.bounds.insetBy(dx: -4, dy: -4), scale: 2)
        }
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
        guard canvas.zoomScale > 0, let strokes = Self.strokesOnPasteboard() else { return }
        let inkBounds = strokes.reduce(CGRect.null) { bounds, stroke in bounds.union(stroke.renderBounds) }
        let offset = CGAffineTransform(translationX: point.x / canvas.zoomScale - inkBounds.midX, y: point.y / canvas.zoomScale - inkBounds.midY)
        add(strokes.map { stroke in Self.stroke(stroke, ink: stroke.ink, movedBy: offset) })
    }

    // MARK: Menus

    @objc private func handleSelectionTap(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended { presentSelectionMenu() }
    }

    private func presentSelectionMenu() {
        guard let selectionView, selectionView.window != nil else { return }
        selectionMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: "selection", sourcePoint: CGPoint(x: selectionView.bounds.midX, y: selectionView.bounds.minY)))
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        if interaction === pasteMenu {
            return UIMenu(children: [UIAction(title: "Paste", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in
                guard let self else { return }
                self.pasteInk(at: self.pastePoint)
            }])
        }
        return UIMenu(children: selectionMenuElements())
    }

    /// Cut, Copy, Duplicate, Straighten (for a line of writing that runs uphill or
    /// downhill), Smooth, Delete, and the colors of Settings › Colors.
    func selectionMenuElements(palette: [PaletteColor] = GraphitePreferences.storedColorPalette()) -> [UIMenuElement] {
        let colors = [PaletteColor(name: "black", hex: PencilInk.pen.defaultColorHex)] + palette
        let swatches = colors.compactMap { favorite -> UIAction? in
            guard let color = UIColor(graphiteHex: favorite.hex) else { return nil }
            let swatch = UIImage(systemName: "circle.fill")?.withTintColor(color, renderingMode: .alwaysOriginal)
            return UIAction(title: favorite.name, image: swatch) { [weak self] _ in self?.recolorSelection(color) }
        }
        var elements: [UIMenuElement] = [
            UIAction(title: "Cut", image: UIImage(systemName: "scissors")) { [weak self] _ in self?.cutSelection() },
            UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in self?.copySelection() },
            UIAction(title: "Duplicate", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in self?.duplicateSelection() },
        ]
        if selectionSlant != nil {
            elements.append(UIAction(title: "Straighten", image: UIImage(systemName: "level")) { [weak self] _ in self?.straightenSelection() })
        }
        elements += [
            UIAction(title: "Smooth", image: UIImage(systemName: "scribble.variable")) { [weak self] _ in self?.smoothSelection() },
            UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.deleteSelection() },
            UIMenu(title: "Color", image: UIImage(systemName: "paintpalette"), options: .displayAsPalette, children: swatches),
        ]
        return elements
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        if interaction === pasteMenu { return CGRect(origin: pastePoint, size: .zero) }
        return selectionView?.bounds ?? .null
    }
}
#endif
