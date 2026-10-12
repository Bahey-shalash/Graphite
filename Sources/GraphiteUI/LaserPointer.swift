#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// The laser pointer on one canvas: for pointing at a page while presenting or sharing the
/// screen. A glowing red dot follows the Pencil or finger and is gone when it lifts
/// (`LaserPointerStyle.dot`), or a red line follows it, at full strength while the Pencil
/// or finger is down, and fades as a whole once it lifts (`.line`). With Apple Pencil hover, the dot shows while the Pencil hovers.
///
/// It draws only in a layer over the window, so it never changes the document, takes no
/// step in its history and leaves nothing in the saved file. Being in the window, it is
/// mirrored with the screen and crosses from one PDF page to the next.
@MainActor
final class LaserPointerController: NSObject, UIGestureRecognizerDelegate {
    private unowned let canvas: HistoryCanvasView
    /// Begins as soon as a touch lands, with no distance to travel first.
    private lazy var touchRecognizer: LaserTouchRecognizer = {
        let recognizer = LaserTouchRecognizer(target: self, action: #selector(handleTouch(_:)))
        recognizer.delegate = self
        return recognizer
    }()
    private lazy var hoverRecognizer = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))

    init(canvas: HistoryCanvasView) {
        self.canvas = canvas
    }

    /// Whether the canvas points instead of drawing.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if isActive, touchRecognizer.view == nil {
                canvas.addGestureRecognizer(touchRecognizer)
                hoverRecognizer.delegate = self
                canvas.addGestureRecognizer(hoverRecognizer)
            }
            touchRecognizer.isEnabled = isActive
            hoverRecognizer.isEnabled = isActive
            if !isActive { overlay?.hideDot() }
        }
    }

    /// The laser takes the touches the canvas would draw with: the Pencil, and a finger
    /// when fingers draw. Other fingers scroll the page as they do while drawing.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        canvas.drawingGestureRecognizer.allowedTouchTypes.contains(NSNumber(value: touch.type.rawValue))
            && !CanvasToolTouches.isHandResting(touch)
    }

    private var overlay: LaserPointerOverlayView? {
        canvas.window.map(LaserPointerOverlayView.overlay(in:))
    }

    @objc private func handleTouch(_ recognizer: LaserTouchRecognizer) {
        guard let overlay, let window = canvas.window else { return }
        let point = recognizer.location(in: window)
        let style = LaserPointerStyle.stored
        switch recognizer.state {
        case .began:
            // Over anything shown since, such as a sheet's dimming.
            window.bringSubviewToFront(overlay)
            overlay.showDot(at: point)
            if style == .line { overlay.beginTrail(at: point) }
        case .changed:
            overlay.showDot(at: point)
            if style == .line { overlay.extendTrail(to: point) }
        default:
            overlay.hideDot()
            overlay.endTrail()
        }
    }

    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        // Only Apple Pencil hovers over the page; a pointer's hover is not pointing.
        guard let overlay, let window = canvas.window, touchRecognizer.state == .possible || touchRecognizer.state == .failed else { return }
        switch recognizer.state {
        case .began, .changed:
            if #available(iOS 16.1, *), recognizer.zOffset > 0 { overlay.showDot(at: recognizer.location(in: window), isHovering: true) }
        default:
            overlay.hideDot()
        }
    }
}

/// Which touches Graphite's own canvas tools, the lasso and the laser pointer, take. With
/// finger drawing, a finger is one of them, but a hand resting on the page while Apple
/// Pencil writes is not: by the same check as palm rejection (`PalmRejection.isHandResting`),
/// it shows no laser dot and draws no loop.
@MainActor
enum CanvasToolTouches {
    static func isHandResting(_ touch: UITouch) -> Bool {
        isHandResting(touchType: touch.type, isPalmRejectionOn: PalmRejectionPreference.isOn(),
                      isPencilActive: PencilActivity.isActive(at: touch.timestamp))
    }

    /// Only a finger can be a hand; the Pencil and a pointer never are.
    static func isHandResting(touchType: UITouch.TouchType, isPalmRejectionOn: Bool, isPencilActive: Bool) -> Bool {
        touchType == .direct && PalmRejection.isHandResting(isPalmRejectionOn: isPalmRejectionOn, isWriting: true, isPencilActive: isPencilActive)
    }
}

/// Follows one touch from the moment it lands until it lifts: began, changed with each
/// move, ended. A long press with no minimum duration ended as soon as the touch moved in
/// the simulator, which left a dot where the touch began and no line.
final class LaserTouchRecognizer: UIGestureRecognizer {
    private weak var trackedTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, let touch = touches.first else {
            for touch in touches where touch !== trackedTouch { ignore(touch, for: event) }
            return
        }
        trackedTouch = touch
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        state = .cancelled
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
    }

    override func location(in view: UIView?) -> CGPoint {
        trackedTouch?.location(in: view) ?? super.location(in: view)
    }
}

/// The layer over a window that the laser pointer draws in. It takes no touches.
@MainActor
final class LaserPointerOverlayView: UIView {
    /// The laser's red, as on white paper, which it is drawn over in any appearance.
    static let laserColor = UIColor(red: 1, green: 0.15, blue: 0.1, alpha: 1)
    static let dotDiameter: CGFloat = 14
    /// How long a line takes to fade once the Pencil or finger lifts, in seconds.
    static let lineFadeDuration: CFTimeInterval = 0.75
    static let trailWidth: CGFloat = 4

    /// One line of the laser: at full strength while it is drawn, then, from the lift, the
    /// whole line fades at once.
    @MainActor
    final class LaserLine {
        fileprivate let layer = CAShapeLayer()
        private(set) var points: [CGPoint]
        /// When the touch drawing the line lifted; nil while it is drawn.
        fileprivate(set) var fadeStartTime: CFTimeInterval?
        var opacity: Float { layer.opacity }

        fileprivate init(startingAt point: CGPoint) {
            points = [point]
            layer.fillColor = nil
            layer.strokeColor = LaserPointerOverlayView.laserColor.cgColor
            layer.lineWidth = LaserPointerOverlayView.trailWidth
            layer.lineCap = .round
            layer.lineJoin = .round
            layer.shadowColor = LaserPointerOverlayView.laserColor.cgColor
            layer.shadowOpacity = 0.9
            layer.shadowRadius = 6
            layer.shadowOffset = .zero
            redraw()
        }

        fileprivate func append(_ point: CGPoint) {
            points.append(point)
            redraw()
        }

        private func redraw() {
            let path = CGMutablePath()
            if let first = points.first {
                path.move(to: first)
                // A touch that has not moved yet shows as a round spot of the line's width.
                if points.count == 1 { path.addLine(to: first) }
                for point in points.dropFirst() { path.addLine(to: point) }
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.path = path
            CATransaction.commit()
        }
    }

    private let dotLayer = CALayer()
    /// The line being drawn, and lines still fading; a line begun while others fade is a new
    /// one, and they go on fading.
    private(set) var lines: [LaserLine] = []
    private var lineBeingDrawn: LaserLine?
    private var displayLink: CADisplayLink?

    static func overlay(in window: UIWindow) -> LaserPointerOverlayView {
        if let existing = window.subviews.compactMap({ subview in subview as? LaserPointerOverlayView }).first { return existing }
        let overlay = LaserPointerOverlayView(frame: window.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(overlay)
        return overlay
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
        dotLayer.shadowColor = Self.laserColor.cgColor
        dotLayer.shadowOpacity = 0.9
        dotLayer.shadowRadius = 6
        dotLayer.shadowOffset = .zero
        dotLayer.bounds = CGRect(x: 0, y: 0, width: Self.dotDiameter, height: Self.dotDiameter)
        dotLayer.cornerRadius = Self.dotDiameter / 2
        dotLayer.backgroundColor = Self.laserColor.cgColor
        // A light rim sets the dot apart from red ink and dark pictures.
        dotLayer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        dotLayer.borderWidth = 1.5
        dotLayer.isHidden = true
        dotLayer.zPosition = 1
        layer.addSublayer(dotLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("LaserPointerOverlayView is created in code.") }

    var isShowingDot: Bool { !dotLayer.isHidden }
    var dotCenter: CGPoint { dotLayer.position }

    func showDot(at point: CGPoint, isHovering: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dotLayer.position = point
        // Hovering, it is fainter: it shows where the Pencil would point.
        dotLayer.opacity = isHovering ? 0.5 : 1
        dotLayer.isHidden = false
        CATransaction.commit()
    }

    func hideDot() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dotLayer.isHidden = true
        CATransaction.commit()
    }

    func beginTrail(at point: CGPoint) {
        // A line still being drawn, as when a touch was lost, starts fading now.
        endTrail()
        let line = LaserLine(startingAt: point)
        lines.append(line)
        lineBeingDrawn = line
        layer.insertSublayer(line.layer, below: dotLayer)
    }

    func extendTrail(to point: CGPoint) {
        lineBeingDrawn?.append(point)
    }

    /// The touch lifted: the whole line fades together.
    func endTrail() {
        guard let line = lineBeingDrawn else { return }
        lineBeingDrawn = nil
        line.fadeStartTime = CACurrentMediaTime()
        startFading()
    }

    private func startFading() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(fadeLines))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Fades each lifted line as a whole, and removes it once it is gone. Fading is a change
    /// of opacity only, which Reduce Motion leaves as it is.
    @objc private func fadeLines() {
        let now = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for line in lines {
            guard let fadeStartTime = line.fadeStartTime else { continue }
            let progress = (now - fadeStartTime) / Self.lineFadeDuration
            line.layer.opacity = Float(max(0, 1 - progress))
        }
        CATransaction.commit()
        let goneLines = lines.filter { line in line.fadeStartTime != nil && line.layer.opacity <= 0 }
        for line in goneLines { line.layer.removeFromSuperlayer() }
        lines.removeAll { line in goneLines.contains { gone in gone === line } }
        if !lines.contains(where: { line in line.fadeStartTime != nil }) {
            displayLink?.invalidate()
            displayLink = nil
        }
    }
}
#endif
