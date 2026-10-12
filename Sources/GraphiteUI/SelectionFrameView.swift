#if canImport(UIKit)
import UIKit

/// The frame around what is being arranged, a picture on a drawing or on a PDF page, or
/// selected ink: drag inside it to move, drag a corner to resize in proportion. The view's
/// frame is the frame of what it surrounds, in its superview, and its owner moves that
/// with it.
final class SelectionFrameView: UIView, UIGestureRecognizerDelegate {
    /// Called when a drag begins, before the frame changes.
    var frameChangeDidBegin: (() -> Void)?
    /// Called while the frame changes, with the new frame in the superview's coordinates.
    var frameDidChange: ((CGRect) -> Void)?
    /// Called when a drag ends, with the final frame.
    var frameChangeDidEnd: ((CGRect) -> Void)?
    /// Called when a drag is cancelled, after the frame is back where it was.
    var frameChangeWasCancelled: (() -> Void)?
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
    /// While a picture is cropped: the picture's frame, which the crop frame stays inside.
    /// A corner then resizes the frame freely rather than in proportion, the frame does not
    /// move, and everything outside it is dimmed.
    var cropLimits: CGRect? {
        didSet {
            moveRecognizer.isEnabled = cropLimits == nil
            dimmingLayer.isHidden = cropLimits == nil
            setNeedsLayout()
        }
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
    /// The move and resize recognizers, for an owner whose scroll view must wait for them.
    var dragRecognizers: [UIPanGestureRecognizer] { [moveRecognizer] + resizeRecognizers }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        previewView.contentMode = .scaleToFill
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
        isAccessibilityElement = true
        accessibilityLabel = "Selected image"
        accessibilityHint = "Drag to move. Drag a corner to resize."
        accessibilityTraits = .allowsDirectInteraction
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
        let pageTraits = UITraitCollection(traitsFrom: [traitCollection, UITraitCollection(userInterfaceStyle: .light)])
        let accent = PlatformColor.graphiteAccent(hex: GraphitePreferences.storedAccentHex()) ?? .systemBlue
        let lineColor = accent.resolvedColor(with: pageTraits).cgColor
        outlineLayer.strokeColor = lineColor
        outlineHaloLayer.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        for knob in knobs {
            knob.backgroundColor = .white
            knob.layer.borderColor = lineColor
        }
        setNeedsLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SelectionFrameView is created in code.") }

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
        for handle in handles.values { handle.transform = CGAffineTransform(scaleX: handleScale, y: handleScale) }
        handles[.topLeft]?.center = CGPoint(x: bounds.minX, y: bounds.minY)
        handles[.topRight]?.center = CGPoint(x: bounds.maxX, y: bounds.minY)
        handles[.bottomLeft]?.center = CGPoint(x: bounds.minX, y: bounds.maxY)
        handles[.bottomRight]?.center = CGPoint(x: bounds.maxX, y: bounds.maxY)
    }

    /// The handles reach outside the frame they resize.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point) || handles.values.contains { handle in handle.frame.contains(point) }
    }

    /// A touch on a corner handle resizes; it must not also move the picture.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === moveRecognizer else { return true }
        return !handles.values.contains { handle in touch.view === handle }
    }

    @objc private func handleMove(_ recognizer: UIPanGestureRecognizer) {
        guard let superview else { return }
        if recognizer.state == .began { frameWhenDragBegan = frame }
        let translation = recognizer.translation(in: superview)
        frame = Self.moved(frameWhenDragBegan, by: translation, keepingCenterIn: centerLimits)
        report(recognizer.state)
    }

    @objc private func handleResize(_ recognizer: UIPanGestureRecognizer) {
        guard let superview, let corner = handles.first(where: { _, handle in handle === recognizer.view })?.key else { return }
        if recognizer.state == .began { frameWhenDragBegan = frame }
        let translation = recognizer.translation(in: superview)
        let pullsRight = corner == .topRight || corner == .bottomRight, pullsDown = corner == .bottomLeft || corner == .bottomRight
        if let cropLimits {
            frame = Self.cropped(frameWhenDragBegan, byDragging: translation, pullsRight: pullsRight, pullsDown: pullsDown,
                                 minimumSideLength: minimumSideLength, within: cropLimits)
        } else {
            frame = Self.resized(frameWhenDragBegan, byDragging: translation, pullsRight: pullsRight, pullsDown: pullsDown, minimumSideLength: minimumSideLength)
        }
        report(recognizer.state)
    }

    private func report(_ state: UIGestureRecognizer.State) {
        switch state {
        case .began:
            frameChangeDidBegin?()
            previewView.isHidden = dragPreview == nil
        case .changed:
            frameDidChange?(frame)
        case .ended:
            previewView.isHidden = true
            frameDidChange?(frame)
            frameChangeDidEnd?(frame)
        case .cancelled, .failed:
            previewView.isHidden = true
            frame = frameWhenDragBegan
            frameDidChange?(frame)
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
