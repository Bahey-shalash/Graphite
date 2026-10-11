#if canImport(UIKit)
import UIKit
import GraphiteCore

/// The frame around what is being arranged, a picture on a drawing or on a PDF page, or
/// selected ink: drag inside it to move, drag a corner to resize in proportion, and, for a
/// picture, drag the handle above it to turn it. The frame is the frame of what it
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
    /// Called while the handle above the frame turns it, with the new `rotation`.
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
    /// Whether a handle above the frame turns it, as for a picture. Off for selected ink.
    var allowsRotation = false {
        didSet { if allowsRotation != oldValue { updateRotationHandle() } }
    }
    /// How far the frame is turned about its middle, in radians, clockwise on screen.
    var rotation: CGFloat = 0 {
        didSet { if rotation != oldValue { transform = CGAffineTransform(rotationAngle: rotation) } }
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
        }
    }

    /// The point the frame turns about: the middle of the picture while it is cropped, and
    /// otherwise the frame's own.
    private var rotationPivot: CGPoint {
        cropLimits.map { limits in CGPoint(x: limits.midX, y: limits.midY) } ?? center
    }

    private let previewView = UIImageView()
    private let dimmingLayer = CAShapeLayer()
    /// Far enough to dim everything around a crop frame on any screen.
    private static let dimmingReach: CGFloat = 20_000

    private enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
    private static let handleDiameter: CGFloat = 14
    private static let borderWidth: CGFloat = 1.5
    /// Handles are small to look at and large to touch.
    private static let handleTouchSide: CGFloat = 44
    private var handles: [Corner: UIView] = [:]
    private var frameWhenDragBegan: CGRect = .zero
    private(set) lazy var moveRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleMove(_:)))
    private(set) var resizeRecognizers: [UIPanGestureRecognizer] = []
    /// The move, resize and turn recognizers, for an owner whose scroll view must wait for them.
    var dragRecognizers: [UIPanGestureRecognizer] { [moveRecognizer] + resizeRecognizers + [rotationRecognizer] }

    // MARK: Turning

    /// The turning handle stands this far above the frame's top edge, on a short stem.
    private static let rotationStemLength: CGFloat = 26
    private static let rotationKnobDiameter: CGFloat = 24
    /// A turn with an accessibility action, in radians: 15°.
    private static let accessibilityTurnStep: CGFloat = .pi / 12
    private let rotationHandle = UIView(frame: CGRect(x: 0, y: 0, width: SelectionFrameView.handleTouchSide, height: SelectionFrameView.handleTouchSide))
    private let rotationStem = UIView()
    private(set) lazy var rotationRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
    private var rotationWhenDragBegan: CGFloat = 0
    /// Where the finger pointed from the frame's middle when the turn began, in radians.
    private var pointerAngleWhenDragBegan: CGFloat = 0
    /// Whether the turn is held at a quarter turn, so the snap is felt once as it happens.
    private var isHeldAtQuarterTurn = false
    private lazy var snapFeedback = UISelectionFeedbackGenerator()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        layer.borderColor = UIColor.label.withAlphaComponent(0.85).cgColor
        layer.borderWidth = Self.borderWidth
        previewView.contentMode = .scaleToFill
        // A preview smaller than the picture's pixels stays smooth (see `InfiniteCanvasView`).
        previewView.layer.minificationFilter = .trilinear
        previewView.alpha = dragPreviewOpacity
        previewView.isHidden = true
        previewView.isUserInteractionEnabled = false
        addSubview(previewView)
        dimmingLayer.fillRule = .evenOdd
        dimmingLayer.fillColor = UIColor.black.withAlphaComponent(0.45).cgColor
        dimmingLayer.isHidden = true
        layer.insertSublayer(dimmingLayer, at: 0)
        moveRecognizer.maximumNumberOfTouches = 1
        moveRecognizer.delegate = self
        addGestureRecognizer(moveRecognizer)
        for corner in Corner.allCases {
            let handle = UIView(frame: CGRect(x: 0, y: 0, width: Self.handleTouchSide, height: Self.handleTouchSide))
            handle.addSubview(Self.makeKnob(diameter: Self.handleDiameter))
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SelectionFrameView is created in code.") }

    /// A round knob centered in a handle's touch area.
    private static func makeKnob(diameter: CGFloat) -> UIView {
        let knob = UIView(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        knob.center = CGPoint(x: handleTouchSide / 2, y: handleTouchSide / 2)
        knob.backgroundColor = .systemBackground
        knob.layer.cornerRadius = diameter / 2
        knob.layer.borderColor = UIColor.label.withAlphaComponent(0.85).cgColor
        knob.layer.borderWidth = 1.5
        knob.isUserInteractionEnabled = false
        return knob
    }

    private func addRotationHandle() {
        rotationStem.backgroundColor = UIColor.label.withAlphaComponent(0.85)
        rotationStem.isUserInteractionEnabled = false
        addSubview(rotationStem)
        let knob = Self.makeKnob(diameter: Self.rotationKnobDiameter)
        let symbol = UIImageView(image: UIImage(systemName: "arrow.clockwise", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)))
        symbol.tintColor = .label
        symbol.center = CGPoint(x: Self.rotationKnobDiameter / 2, y: Self.rotationKnobDiameter / 2)
        knob.addSubview(symbol)
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
        accessibilityHint = showsRotationHandle ? "Drag to move. Drag a corner to resize. Drag the handle above to turn." : "Drag to move. Drag a corner to resize."
        accessibilityCustomActions = showsRotationHandle ? [
            UIAccessibilityCustomAction(name: "Turn Clockwise", target: self, selector: #selector(turnClockwiseByAccessibilityStep)),
            UIAccessibilityCustomAction(name: "Turn Counterclockwise", target: self, selector: #selector(turnCounterclockwiseByAccessibilityStep)),
        ] : nil
        setNeedsLayout()
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
        layer.borderWidth = Self.borderWidth * handleScale
        for handle in handles.values { handle.transform = CGAffineTransform(scaleX: handleScale, y: handleScale) }
        handles[.topLeft]?.center = CGPoint(x: bounds.minX, y: bounds.minY)
        handles[.topRight]?.center = CGPoint(x: bounds.maxX, y: bounds.minY)
        handles[.bottomLeft]?.center = CGPoint(x: bounds.minX, y: bounds.maxY)
        handles[.bottomRight]?.center = CGPoint(x: bounds.maxX, y: bounds.maxY)
        let stemLength = Self.rotationStemLength * handleScale
        rotationHandle.transform = CGAffineTransform(scaleX: handleScale, y: handleScale)
        rotationHandle.center = CGPoint(x: bounds.midX, y: bounds.minY - stemLength)
        rotationStem.frame = CGRect(x: bounds.midX - layer.borderWidth / 2, y: bounds.minY - stemLength, width: layer.borderWidth, height: stemLength)
    }

    /// The handles reach outside the frame they resize or turn.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point) || handles.values.contains { handle in handle.frame.contains(point) }
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

    @objc private func turnClockwiseByAccessibilityStep() -> Bool { turn(by: Self.accessibilityTurnStep) }
    @objc private func turnCounterclockwiseByAccessibilityStep() -> Bool { turn(by: -Self.accessibilityTurnStep) }

    private func turn(by angle: CGFloat) -> Bool {
        rotation = CGFloat(PictureRotation.normalized(Double(rotation + angle)))
        rotationDidChange?(rotation)
        rotationChangeDidEnd?(rotation)
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
