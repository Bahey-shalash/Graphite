#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// The laser pointer on one canvas: for pointing at a page while presenting or sharing the
/// screen. A glowing red dot follows the Pencil or finger and is gone when it lifts
/// (`LaserPointerStyle.dot`), or a red line follows it and fades a moment after it is
/// drawn (`.line`). With Apple Pencil hover, the dot shows while the Pencil hovers.
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
    /// How long each part of a line stays before it is gone, in seconds.
    static let trailLifetime: CFTimeInterval = 0.9
    static let trailWidth: CGFloat = 4

    private let dotLayer = CALayer()
    private let trailLayer = CAShapeLayer()
    /// The line's points with the time each was drawn; several lines fade at once.
    private(set) var trails: [[(point: CGPoint, time: CFTimeInterval)]] = []
    private var isDrawingTrail = false
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
        for glowingLayer in [dotLayer, trailLayer] as [CALayer] {
            glowingLayer.shadowColor = Self.laserColor.cgColor
            glowingLayer.shadowOpacity = 0.9
            glowingLayer.shadowRadius = 6
            glowingLayer.shadowOffset = .zero
        }
        dotLayer.bounds = CGRect(x: 0, y: 0, width: Self.dotDiameter, height: Self.dotDiameter)
        dotLayer.cornerRadius = Self.dotDiameter / 2
        dotLayer.backgroundColor = Self.laserColor.cgColor
        // A light rim sets the dot apart from red ink and dark pictures.
        dotLayer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        dotLayer.borderWidth = 1.5
        dotLayer.isHidden = true
        trailLayer.fillColor = nil
        trailLayer.strokeColor = Self.laserColor.cgColor
        trailLayer.lineWidth = Self.trailWidth
        trailLayer.lineCap = .round
        trailLayer.lineJoin = .round
        layer.addSublayer(trailLayer)
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
        trails.append([(point, CACurrentMediaTime())])
        isDrawingTrail = true
        startFading()
        redrawTrails()
    }

    func extendTrail(to point: CGPoint) {
        guard isDrawingTrail, !trails.isEmpty else { return }
        trails[trails.count - 1].append((point, CACurrentMediaTime()))
        redrawTrails()
    }

    func endTrail() {
        isDrawingTrail = false
    }

    private func startFading() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(fadeTrails))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Drops what is older than a line's lifetime, so a line shortens from its start and is
    /// gone a moment after it was drawn.
    @objc private func fadeTrails() {
        let now = CACurrentMediaTime()
        trails = trails.map { trail in trail.filter { sample in now - sample.time < Self.trailLifetime } }
        // The line being drawn keeps its newest point, where the dot is.
        trails = trails.enumerated().filter { trailIndex, trail in !trail.isEmpty || (isDrawingTrail && trailIndex == trails.count - 1) }.map(\.element)
        redrawTrails()
        if trails.isEmpty, !isDrawingTrail {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    private func redrawTrails() {
        let path = CGMutablePath()
        for trail in trails {
            guard let first = trail.first else { continue }
            path.move(to: first.point)
            for sample in trail.dropFirst() { path.addLine(to: sample.point) }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trailLayer.path = path
        CATransaction.commit()
    }
}
#endif
