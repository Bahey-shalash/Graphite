#if canImport(UIKit)
import UIKit
import GraphiteCore

/// The frame around what is being arranged, a picture on a drawing or on a PDF page, or
/// selected ink: drag inside it to move, drag a corner to resize in proportion, and, for a
/// picture, drag its rotate handle, above it or below it where there is no room above. The frame is the frame of what it
/// surrounds, in its superview, and its owner moves that with it.
///
/// A turned frame is a view turned by `rotation`; its owner gives and is given its
/// `unrotatedFrame`, as the picture it surrounds keeps an upright frame and an angle.
final class SelectionFrameView: UIView, UIGestureRecognizerDelegate {
    /// Called when a drag begins, before the frame changes.
    var frameChangeDidBegin: (() -> Void)?
    /// Called while the frame changes, with the new `unrotatedFrame`.
    var frameDidChange: ((CGRect) -> Void)?
    /// Called when a drag ends, with the final `unrotatedFrame`.
    var frameChangeDidEnd: ((CGRect) -> Void)?
    /// Called when a drag is cancelled, after the frame is back where it was.
    var frameChangeWasCancelled: (() -> Void)?
    /// Called while the rotate handle turns the frame, with the new `rotation`.
    var rotationDidChange: ((CGFloat) -> Void)?
    /// Called when the frame has been turned, by its handle or by an accessibility action,
    /// with the final `rotation`.
    var rotationChangeDidEnd: ((CGFloat) -> Void)?
    /// The smallest side the frame can be resized to, in the superview's points.
    var minimumSideLength: CGFloat = 32
    /// The region the frame's center has to stay in, so it cannot be lost off the page.
    var centerLimits: CGRect = .infinite
    /// Shown inside the frame while it is dragged, for an owner whose content moves only
    /// when the drag ends: faintly over content that stays where it was, or, at full
    /// strength, in place of content the owner hides for the drag.
    var dragPreview: UIImage? {
        didSet { previewView.image = dragPreview }
    }
    var dragPreviewOpacity: CGFloat = 0.55 {
        didSet { previewView.alpha = dragPreviewOpacity }
    }
    /// How far inside the frame the preview's edges are, for a frame that leaves a margin
    /// around what it surrounds.
    var dragPreviewInset: CGFloat = 0 {
        didSet { setNeedsLayout() }
    }
    /// How much larger than on screen the superview's points are drawn, as on a zoomed PDF
    /// page. The handles and the border are drawn that much smaller, to keep their size.
    var contentScale: CGFloat = 1 {
        didSet { if contentScale != oldValue { setNeedsLayout() } }
    }
    /// While a picture is cropped: the picture's frame, before it is turned, which the crop
    /// frame stays inside. A corner then resizes the frame freely rather than in proportion,
    /// the frame does not move or turn, and everything outside it is dimmed. The crop frame
    /// turns with the picture, about the picture's middle.
    var cropLimits: CGRect? {
        didSet {
            moveRecognizer.isEnabled = cropLimits == nil
            dimmingLayer.isHidden = cropLimits == nil
            updateRotationHandle()
            setNeedsLayout()
        }
    }
    /// Whether a rotate handle turns the frame, as for a picture. Off for selected ink.
    var allowsRotation = false {
        didSet { if allowsRotation != oldValue { updateRotationHandle() } }
    }
    /// How far the frame is turned about its middle, in radians, clockwise on screen.
    var rotation: CGFloat = 0 {
        didSet {
            guard rotation != oldValue else { return }
            transform = CGAffineTransform(rotationAngle: rotation)
            updateAccessibilityValue()
            setNeedsLayout()
        }
    }

    /// The frame before it is turned, in the superview's coordinates. The frame on screen
    /// is this rectangle turned by `rotation` about its middle, or, while cropping, about
    /// the middle of `cropLimits`, the picture's. Set `rotation` and `cropLimits` first.
    var unrotatedFrame: CGRect {
        get {
            let unrotatedCenter = PictureRotation.point(center, turnedBy: -Double(rotation), about: rotationPivot)
            return CGRect(x: unrotatedCenter.x - bounds.width / 2, y: unrotatedCenter.y - bounds.height / 2, width: bounds.width, height: bounds.height)
        }
        set {
            let unrotatedCenter = CGPoint(x: newValue.midX, y: newValue.midY)
            bounds = CGRect(origin: .zero, size: newValue.size)
            center = PictureRotation.point(unrotatedCenter, turnedBy: Double(rotation), about: cropLimits.map { limits in CGPoint(x: limits.midX, y: limits.midY) } ?? unrotatedCenter)
            // Where the frame is on screen decides the rotate handle's side.
            setNeedsLayout()
        }
    }

    /// The point the frame turns about: the middle of the picture while it is cropped, and
    /// otherwise the frame's own.
    private var rotationPivot: CGPoint {
        cropLimits.map { limits in CGPoint(x: limits.midX, y: limits.midY) } ?? center
    }

    private let previewView = UIImageView()
    private let dimmingLayer = CAShapeLayer()
    /// The frame's line, over a wider white halo that keeps it visible on dark ink and
    /// pictures; see `applyColors`.
    private let outlineHaloLayer = CAShapeLayer()
    private let outlineLayer = CAShapeLayer()
    private var knobs: [UIView] = []
    /// Far enough to dim everything around a crop frame on any screen.
    private static let dimmingReach: CGFloat = 20_000

    private enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
    private static let handleDiameter: CGFloat = 14
    private static let borderWidth: CGFloat = 1.5
    private static let increasedContrastBorderWidth: CGFloat = 2.5
    /// How far the white halo reaches beyond each side of the line.
    private static let haloWidth: CGFloat = 1
    /// Handles are small to look at and large to touch.
    private static let handleTouchSide: CGFloat = 44
    private var handles: [Corner: UIView] = [:]
    private var frameWhenDragBegan: CGRect = .zero
    private(set) lazy var moveRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleMove(_:)))
    private(set) var resizeRecognizers: [UIPanGestureRecognizer] = []
    /// The move, resize and turn recognizers, for an owner whose scroll view must wait for them.
    var dragRecognizers: [UIPanGestureRecognizer] { [moveRecognizer] + resizeRecognizers + [rotationRecognizer] }

    // MARK: Turning

    /// The rotate handle stands this far above the frame's top edge, on a short stem, or
    /// below its bottom edge when it could not be reached above (`rotationHandleStandsBelow`).
    private static let rotationStemLength: CGFloat = 26
    private static let rotationKnobDiameter: CGFloat = 24
    /// A rotation with an accessibility action, in radians: 15°.
    private static let accessibilityRotationStep: CGFloat = .pi / 12
    private let rotationHandle = UIView(frame: CGRect(x: 0, y: 0, width: SelectionFrameView.handleTouchSide, height: SelectionFrameView.handleTouchSide))
    private let rotationStem = UIView()
    private let rotationSymbol = UIImageView(image: UIImage(systemName: "arrow.clockwise", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)))
    private(set) lazy var rotationRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
    private var rotationWhenDragBegan: CGFloat = 0
    /// Where the finger pointed from the frame's middle when the turn began, in radians.
    private var pointerAngleWhenDragBegan: CGFloat = 0
    /// Whether the turn is held at a quarter turn, so the snap is felt once as it happens.
    private var isHeldAtQuarterTurn = false
    private lazy var snapFeedback = UISelectionFeedbackGenerator()
    /// Whether the rotate handle stands below the frame: above it, it would be outside the
    /// view the frame is in or under its bars, where a touch cannot reach it, as for a
    /// picture at the top of a PDF's first page. Kept while the handle is dragged.
    private(set) var rotationHandleStandsBelow = false
    /// Lays the handle out again as the scroll view the frame is in scrolls, which moves
    /// the frame on screen without changing it.
    private var scrollObservation: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        previewView.contentMode = .scaleToFill
        // A preview smaller than the picture's pixels stays smooth (see `InfiniteCanvasView`).
        previewView.layer.minificationFilter = .trilinear
        previewView.alpha = dragPreviewOpacity
        previewView.isHidden = true
        previewView.isUserInteractionEnabled = false
        addSubview(previewView)
        for outline in [outlineHaloLayer, outlineLayer] {
            outline.fillColor = nil
            layer.addSublayer(outline)
        }
        dimmingLayer.fillRule = .evenOdd
        dimmingLayer.fillColor = UIColor.black.withAlphaComponent(0.45).cgColor
        dimmingLayer.isHidden = true
        layer.insertSublayer(dimmingLayer, at: 0)
        moveRecognizer.maximumNumberOfTouches = 1
        moveRecognizer.delegate = self
        addGestureRecognizer(moveRecognizer)
        for corner in Corner.allCases {
            let handle = UIView(frame: CGRect(x: 0, y: 0, width: Self.handleTouchSide, height: Self.handleTouchSide))
            let knob = Self.makeKnob(diameter: Self.handleDiameter)
            knobs.append(knob)
            handle.addSubview(knob)
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handleResize(_:)))
            recognizer.maximumNumberOfTouches = 1
            handle.addGestureRecognizer(recognizer)
            resizeRecognizers.append(recognizer)
            addSubview(handle)
            handles[corner] = handle
        }
        addRotationHandle()
        isAccessibilityElement = true
        accessibilityLabel = "Selected image"
        accessibilityTraits = .allowsDirectInteraction
        updateRotationHandle()
        applyColors()
        registerForTraitChanges([UITraitAccessibilityContrast.self]) { (frameView: SelectionFrameView, _: UITraitCollection) in
            frameView.applyColors()
        }
    }

    /// A round knob centered in a handle's touch area, its colors set by `applyColors`. A
    /// soft shadow sets it apart from a white page.
    private static func makeKnob(diameter: CGFloat) -> UIView {
        let knob = UIView(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        knob.center = CGPoint(x: handleTouchSide / 2, y: handleTouchSide / 2)
        knob.layer.cornerRadius = diameter / 2
        knob.layer.borderWidth = 1.5
        knob.layer.shadowColor = UIColor.black.cgColor
        knob.layer.shadowOpacity = 0.3
        knob.layer.shadowRadius = 1.5
        knob.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        knob.layer.shadowPath = UIBezierPath(ovalIn: knob.bounds).cgPath
        knob.isUserInteractionEnabled = false
        return knob
    }

    /// The frame is drawn over a PDF page or a drawing's paper, which keep their own colors
    /// in dark appearance, so it does not follow the appearance: its line is the accent as it
    /// reads on white, over a white halo that keeps it visible on dark ink and pictures, and
    /// its knobs are white, ringed in the accent. Following the appearance, it was white on
    /// a white page in dark appearance.
    private func applyColors() {
        let lineColor = LassoColors.line(for: traitCollection).cgColor
        outlineLayer.strokeColor = lineColor
        outlineHaloLayer.strokeColor = LassoColors.halo.cgColor
        for knob in knobs {
            knob.backgroundColor = .white
            knob.layer.borderColor = lineColor
        }
        rotationStem.backgroundColor = UIColor(cgColor: lineColor)
        rotationSymbol.tintColor = UIColor(cgColor: lineColor)
        setNeedsLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SelectionFrameView is created in code.") }

    /// The turning handle's knob, stem and arrow take their colors in `applyColors`.
    private func addRotationHandle() {
        rotationStem.isUserInteractionEnabled = false
        addSubview(rotationStem)
        let knob = Self.makeKnob(diameter: Self.rotationKnobDiameter)
        knobs.append(knob)
        rotationSymbol.center = CGPoint(x: Self.rotationKnobDiameter / 2, y: Self.rotationKnobDiameter / 2)
        knob.addSubview(rotationSymbol)
        rotationHandle.addSubview(knob)
        rotationRecognizer.maximumNumberOfTouches = 1
        rotationHandle.addGestureRecognizer(rotationRecognizer)
        addSubview(rotationHandle)
    }

    /// The turning handle shows for a picture, except while it is cropped.
    private func updateRotationHandle() {
        let showsRotationHandle = allowsRotation && cropLimits == nil
        rotationHandle.isHidden = !showsRotationHandle
        rotationStem.isHidden = !showsRotationHandle
        rotationRecognizer.isEnabled = showsRotationHandle
        accessibilityHint = showsRotationHandle ? "Drag to move. Drag a corner to resize. Drag the arrow handle to rotate." : "Drag to move. Drag a corner to resize."
        updateAccessibilityActions()
        updateAccessibilityValue()
        setNeedsLayout()
    }

    /// Actions VoiceOver offers on the frame besides rotating it, such as the selection
    /// menu's, which is out of reach once VoiceOver moves on.
    var additionalAccessibilityActions: [UIAccessibilityCustomAction] = [] {
        didSet { updateAccessibilityActions() }
    }

    private func updateAccessibilityActions() {
        let showsRotationHandle = allowsRotation && cropLimits == nil
        let rotationActions = showsRotationHandle ? [
            UIAccessibilityCustomAction(name: "Rotate Clockwise", target: self, selector: #selector(rotateClockwiseByAccessibilityStep)),
            UIAccessibilityCustomAction(name: "Rotate Counterclockwise", target: self, selector: #selector(rotateCounterclockwiseByAccessibilityStep)),
        ] : []
        let actions = rotationActions + additionalAccessibilityActions
        accessibilityCustomActions = actions.isEmpty ? nil : actions
    }

    /// The angle, for VoiceOver, where the frame can be rotated: what Rotate Clockwise and
    /// Rotate Counterclockwise change.
    private func updateAccessibilityValue() {
        guard allowsRotation, cropLimits == nil else {
            accessibilityValue = nil
            return
        }
        accessibilityValue = Self.describedRotation(rotation)
    }

    /// "Upright", or the angle in whole degrees and its direction, as VoiceOver reads it.
    static func describedRotation(_ rotation: CGFloat) -> String {
        let degrees = Int((Double(PictureRotation.normalized(Double(rotation))) * 180 / .pi).rounded())
        if degrees == 0 { return "Upright" }
        return degrees > 0 ? "Rotated \(degrees)° clockwise" : "Rotated \(-degrees)° counterclockwise"
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        scrollObservation = (superview as? UIScrollView)?.observe(\.contentOffset) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.setNeedsLayout() }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewView.frame = bounds.insetBy(dx: dragPreviewInset, dy: dragPreviewInset)
        if cropLimits != nil {
            let dimmedArea = UIBezierPath(rect: bounds.insetBy(dx: -Self.dimmingReach, dy: -Self.dimmingReach))
            dimmedArea.append(UIBezierPath(rect: bounds))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            dimmingLayer.path = dimmedArea.cgPath
            CATransaction.commit()
        }
        let handleScale = contentScale > 0 ? 1 / contentScale : 1
        let lineWidth = (traitCollection.accessibilityContrast == .high ? Self.increasedContrastBorderWidth : Self.borderWidth) * handleScale
        let outline = UIBezierPath(rect: bounds).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outlineLayer.path = outline
        outlineLayer.lineWidth = lineWidth
        outlineHaloLayer.path = outline
        outlineHaloLayer.lineWidth = lineWidth + 2 * Self.haloWidth * handleScale
        CATransaction.commit()
        // A handle's touch area reaches at most a quarter of the frame's shorter side into
        // it, so a small frame, around a word or a dot, keeps its middle for moving; the
        // area moves outward instead, and the knob stays on the corner.
        // A frame too small for four knobs to stand apart, around a dot or a short word, has
        // one, at its bottom-right corner, as Goodnotes does; four knobs touched each other.
        let showsOneHandle = min(bounds.width, bounds.height) < Self.handleTouchSide * handleScale && cropLimits == nil
        for (corner, handle) in handles { handle.isHidden = showsOneHandle && corner != .bottomRight }
        let halfTouchSide = Self.handleTouchSide / 2 * handleScale
        let inwardReach = min(halfTouchSide, min(bounds.width, bounds.height) / 4)
        let outwardShift = halfTouchSide - inwardReach
        for (corner, handle) in handles {
            let outwardX: CGFloat = corner == .topLeft || corner == .bottomLeft ? -1 : 1
            let outwardY: CGFloat = corner == .topLeft || corner == .topRight ? -1 : 1
            let cornerPoint = CGPoint(x: outwardX < 0 ? bounds.minX : bounds.maxX, y: outwardY < 0 ? bounds.minY : bounds.maxY)
            handle.transform = CGAffineTransform(scaleX: handleScale, y: handleScale)
            handle.center = CGPoint(x: cornerPoint.x + outwardX * outwardShift, y: cornerPoint.y + outwardY * outwardShift)
            let knobShift = handleScale > 0 ? outwardShift / handleScale : 0
            handle.subviews.first?.center = CGPoint(x: Self.handleTouchSide / 2 - outwardX * knobShift, y: Self.handleTouchSide / 2 - outwardY * knobShift)
            // A corner past the edge of the view the frame is in, as of ink at a PDF page's
            // edge, is cut off there and cannot be touched: the handle, knob and all, stands
            // just inside the edge instead, as the rotate handle moves below the frame.
            if let reachableCenter = reachableCenter(for: handle.center, scale: handleScale), reachableCenter != handle.center {
                handle.center = reachableCenter
                handle.subviews.first?.center = CGPoint(x: Self.handleTouchSide / 2, y: Self.handleTouchSide / 2)
            }
        }
        // On a frame too narrow for the rotate handle to stand between the corners'
        // handles, it stands beyond them, so neither covers the other.
        let standsBeyondCornerHandles = bounds.width < Self.handleTouchSide * 2 * handleScale
        let stemLength = (standsBeyondCornerHandles ? Self.handleTouchSide : Self.rotationStemLength) * handleScale
        let centerAbove = CGPoint(x: bounds.midX, y: bounds.minY - stemLength)
        let centerBelow = CGPoint(x: bounds.midX, y: bounds.maxY + stemLength)
        let isBeingRotated = rotationRecognizer.state == .began || rotationRecognizer.state == .changed
        if !isBeingRotated {
            rotationHandleStandsBelow = !canReachHandle(at: centerAbove, scale: handleScale) && canReachHandle(at: centerBelow, scale: handleScale)
        }
        rotationHandle.transform = CGAffineTransform(scaleX: handleScale, y: handleScale)
        rotationHandle.center = rotationHandleStandsBelow ? centerBelow : centerAbove
        rotationStem.frame = rotationHandleStandsBelow
            ? CGRect(x: bounds.midX - lineWidth / 2, y: bounds.maxY, width: lineWidth, height: stemLength)
            : CGRect(x: bounds.midX - lineWidth / 2, y: bounds.minY - stemLength, width: lineWidth, height: stemLength)
    }

    /// The nearest point to a handle's center, in this view, at which the whole handle is
    /// inside the part of the superview a touch reaches (see `canReachHandle`); nil when that
    /// part is too small to hold a handle, which then stays where it is.
    private func reachableCenter(for handleCenter: CGPoint, scale handleScale: CGFloat) -> CGPoint? {
        guard let superview else { return nil }
        let halfTouchSide = Self.handleTouchSide * handleScale / 2
        let reachableArea = superview.bounds.inset(by: superview.safeAreaInsets).insetBy(dx: halfTouchSide, dy: halfTouchSide)
        guard !reachableArea.isNull, reachableArea.width >= 0, reachableArea.height >= 0 else { return nil }
        let centerInSuperview = convert(handleCenter, to: superview)
        let clamped = CGPoint(x: min(max(centerInSuperview.x, reachableArea.minX), reachableArea.maxX),
                              y: min(max(centerInSuperview.y, reachableArea.minY), reachableArea.maxY))
        return clamped == centerInSuperview ? handleCenter : superview.convert(clamped, to: self)
    }

    /// Whether the rotate handle, centered at a point of this view, would be wholly inside
    /// the part of the superview a touch reaches: its bounds, which a scroll view moves as
    /// it scrolls, less its safe area, where bars cover it.
    private func canReachHandle(at handleCenter: CGPoint, scale handleScale: CGFloat) -> Bool {
        guard let superview else { return true }
        let reachableArea = superview.bounds.inset(by: superview.safeAreaInsets)
        let halfTouchSide = Self.handleTouchSide * handleScale / 2
        let centerInSuperview = convert(handleCenter, to: superview)
        return reachableArea.insetBy(dx: halfTouchSide, dy: halfTouchSide).contains(centerInSuperview)
    }

    /// The handles reach outside the frame they resize or turn.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point) || handles.values.contains { handle in !handle.isHidden && handle.frame.contains(point) }
            || (!rotationHandle.isHidden && rotationHandle.frame.contains(point))
    }

    /// A touch on a corner handle resizes, and one on the turning handle turns; neither
    /// must also move the picture.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === moveRecognizer else { return true }
        return !handles.values.contains { handle in touch.view === handle } && touch.view !== rotationHandle
    }

    @objc private func handleMove(_ recognizer: UIPanGestureRecognizer) {
        guard let superview else { return }
        if recognizer.state == .began { frameWhenDragBegan = unrotatedFrame }
        let translation = recognizer.translation(in: superview)
        // Moving never happens while cropping, so the frame turns about its own middle and
        // moves as it is shown.
        unrotatedFrame = Self.moved(frameWhenDragBegan, by: translation, keepingCenterIn: centerLimits)
        report(recognizer.state)
    }

    @objc private func handleResize(_ recognizer: UIPanGestureRecognizer) {
        guard let superview, let corner = handles.first(where: { _, handle in handle === recognizer.view })?.key else { return }
        if recognizer.state == .began { frameWhenDragBegan = unrotatedFrame }
        // The corners are the frame's own and turn with it, so the drag is measured along
        // the frame's sides.
        let translation = PictureRotation.vector(recognizer.translation(in: superview), turnedBy: -Double(rotation))
        let pullsRight = corner == .topRight || corner == .bottomRight, pullsDown = corner == .bottomLeft || corner == .bottomRight
        if let cropLimits {
            unrotatedFrame = Self.cropped(frameWhenDragBegan, byDragging: translation, pullsRight: pullsRight, pullsDown: pullsDown,
                                          minimumSideLength: minimumSideLength, within: cropLimits)
        } else {
            let resizedFrame = Self.resized(frameWhenDragBegan, byDragging: translation, pullsRight: pullsRight, pullsDown: pullsDown,
                                            minimumSideLength: minimumSideLength)
            // The corner opposite the dragged one stays where it is on screen: the resized
            // frame is turned about the middle the frame had.
            unrotatedFrame = PictureRotation.rectangle(resizedFrame, withMiddleTurnedBy: Double(rotation),
                                                       about: CGPoint(x: frameWhenDragBegan.midX, y: frameWhenDragBegan.midY))
        }
        report(recognizer.state)
    }

    /// Turns the frame about its middle as far as the finger has gone around it, and puts
    /// it exactly straight, or exactly a quarter turn, when it comes close.
    @objc private func handleRotation(_ recognizer: UIPanGestureRecognizer) {
        guard let superview else { return }
        let location = recognizer.location(in: superview)
        let pointerAngle = atan2(location.y - center.y, location.x - center.x)
        if recognizer.state == .began {
            frameWhenDragBegan = unrotatedFrame
            rotationWhenDragBegan = rotation
            pointerAngleWhenDragBegan = pointerAngle
            isHeldAtQuarterTurn = PictureRotation.isNearQuarterTurn(Double(rotation))
            snapFeedback.prepare()
        }
        let freeAngle = PictureRotation.normalized(Double(rotationWhenDragBegan + pointerAngle - pointerAngleWhenDragBegan))
        let isAtQuarterTurn = PictureRotation.isNearQuarterTurn(freeAngle)
        if isAtQuarterTurn, !isHeldAtQuarterTurn { snapFeedback.selectionChanged() }
        isHeldAtQuarterTurn = isAtQuarterTurn
        rotation = CGFloat(PictureRotation.snapped(freeAngle))
        switch recognizer.state {
        case .began:
            frameChangeDidBegin?()
            previewView.isHidden = dragPreview == nil
        case .changed:
            rotationDidChange?(rotation)
        case .ended:
            previewView.isHidden = true
            rotationDidChange?(rotation)
            rotationChangeDidEnd?(rotation)
        case .cancelled, .failed:
            previewView.isHidden = true
            rotation = rotationWhenDragBegan
            rotationDidChange?(rotation)
            frameChangeWasCancelled?()
        default: break
        }
    }

    @objc private func rotateClockwiseByAccessibilityStep() -> Bool { rotate(by: Self.accessibilityRotationStep) }
    @objc private func rotateCounterclockwiseByAccessibilityStep() -> Bool { rotate(by: -Self.accessibilityRotationStep) }

    private func rotate(by angle: CGFloat) -> Bool {
        rotation = CGFloat(PictureRotation.normalized(Double(rotation + angle)))
        rotationDidChange?(rotation)
        rotationChangeDidEnd?(rotation)
        // VoiceOver says the new angle, as a slider says its new value.
        UIAccessibility.post(notification: .announcement, argument: Self.describedRotation(rotation))
        return true
    }

    private func report(_ state: UIGestureRecognizer.State) {
        switch state {
        case .began:
            frameChangeDidBegin?()
            previewView.isHidden = dragPreview == nil
        case .changed:
            frameDidChange?(unrotatedFrame)
        case .ended:
            previewView.isHidden = true
            frameDidChange?(unrotatedFrame)
            frameChangeDidEnd?(unrotatedFrame)
        case .cancelled, .failed:
            previewView.isHidden = true
            unrotatedFrame = frameWhenDragBegan
            frameDidChange?(unrotatedFrame)
            frameChangeWasCancelled?()
        default: break
        }
    }

    static func moved(_ frame: CGRect, by translation: CGPoint, keepingCenterIn limits: CGRect) -> CGRect {
        var center = CGPoint(x: frame.midX + translation.x, y: frame.midY + translation.y)
        if !limits.isInfinite, !limits.isNull {
            center.x = min(max(center.x, limits.minX), limits.maxX)
            center.y = min(max(center.y, limits.minY), limits.maxY)
        }
        return CGRect(x: center.x - frame.width / 2, y: center.y - frame.height / 2, width: frame.width, height: frame.height)
    }

    /// The frame with the dragged corner moved, the opposite corner kept, and the frame kept
    /// inside the limits and no smaller than the minimum side.
    static func cropped(_ frame: CGRect, byDragging translation: CGPoint, pullsRight: Bool, pullsDown: Bool,
                        minimumSideLength: CGFloat, within limits: CGRect) -> CGRect {
        let side = min(minimumSideLength, limits.width, limits.height)
        var minimumX = frame.minX, maximumX = frame.maxX, minimumY = frame.minY, maximumY = frame.maxY
        if pullsRight {
            maximumX = min(max(frame.maxX + translation.x, minimumX + side), limits.maxX)
        } else {
            minimumX = max(min(frame.minX + translation.x, maximumX - side), limits.minX)
        }
        if pullsDown {
            maximumY = min(max(frame.maxY + translation.y, minimumY + side), limits.maxY)
        } else {
            minimumY = max(min(frame.minY + translation.y, maximumY - side), limits.minY)
        }
        return CGRect(x: minimumX, y: minimumY, width: maximumX - minimumX, height: maximumY - minimumY)
    }

    /// The frame scaled in proportion about the corner opposite the dragged one.
    static func resized(_ frame: CGRect, byDragging translation: CGPoint, pullsRight: Bool, pullsDown: Bool, minimumSideLength: CGFloat) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return frame }
        let widthChange = pullsRight ? translation.x : -translation.x, heightChange = pullsDown ? translation.y : -translation.y
        // The larger of the two pulls decides, so a drag along either side resizes.
        let scaleFromWidth = (frame.width + widthChange) / frame.width, scaleFromHeight = (frame.height + heightChange) / frame.height
        let smallestScale = minimumSideLength / min(frame.width, frame.height)
        let scale = max(max(scaleFromWidth, scaleFromHeight), smallestScale)
        let width = frame.width * scale, height = frame.height * scale
        return CGRect(x: pullsRight ? frame.minX : frame.maxX - width, y: pullsDown ? frame.minY : frame.maxY - height, width: width, height: height)
    }
}
#endif
