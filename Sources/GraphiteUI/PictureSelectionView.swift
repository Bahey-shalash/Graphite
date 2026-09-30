#if canImport(UIKit)
import UIKit

/// The frame around a picture being arranged, on a drawing or on a PDF page: drag inside
/// it to move the picture, drag a corner to resize it in proportion. The view's frame is
/// the picture's frame in its superview, and its owner moves the picture with it.
final class PictureSelectionView: UIView, UIGestureRecognizerDelegate {
    /// Called while the frame changes, with the new frame in the superview's coordinates.
    var frameDidChange: ((CGRect) -> Void)?
    /// Called when a drag ends, with the final frame.
    var frameChangeDidEnd: ((CGRect) -> Void)?
    /// The smallest side a picture can be resized to, in the superview's points.
    var minimumSideLength: CGFloat = 32
    /// The region the picture's center has to stay in, so it cannot be lost off the page.
    var centerLimits: CGRect = .infinite
    /// Shown faintly inside the frame while it is dragged, for an owner whose picture moves
    /// only when the drag ends.
    var dragPreview: UIImage? {
        didSet { previewView.image = dragPreview }
    }
    private let previewView = UIImageView()

    private enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
    private static let handleDiameter: CGFloat = 14
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
        layer.borderColor = UIColor.label.withAlphaComponent(0.85).cgColor
        layer.borderWidth = 1.5
        previewView.contentMode = .scaleToFill
        previewView.alpha = 0.55
        previewView.isHidden = true
        previewView.isUserInteractionEnabled = false
        addSubview(previewView)
        moveRecognizer.maximumNumberOfTouches = 1
        moveRecognizer.delegate = self
        addGestureRecognizer(moveRecognizer)
        for corner in Corner.allCases {
            let handle = UIView(frame: CGRect(x: 0, y: 0, width: Self.handleTouchSide, height: Self.handleTouchSide))
            let knob = UIView(frame: CGRect(x: 0, y: 0, width: Self.handleDiameter, height: Self.handleDiameter))
            knob.center = CGPoint(x: Self.handleTouchSide / 2, y: Self.handleTouchSide / 2)
            knob.backgroundColor = .systemBackground
            knob.layer.cornerRadius = Self.handleDiameter / 2
            knob.layer.borderColor = UIColor.label.withAlphaComponent(0.85).cgColor
            knob.layer.borderWidth = 1.5
            knob.isUserInteractionEnabled = false
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PictureSelectionView is created in code.") }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewView.frame = bounds
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
        frame = Self.resized(frameWhenDragBegan, byDragging: translation, pullsRight: pullsRight, pullsDown: pullsDown, minimumSideLength: minimumSideLength)
        report(recognizer.state)
    }

    private func report(_ state: UIGestureRecognizer.State) {
        switch state {
        case .began:
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
