#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass
import GraphiteCore

/// The laser pointer on one canvas: for pointing at a page while presenting or sharing the
/// screen. A glowing red dot follows the Pencil or finger and is gone when it lifts
/// (`LaserPointerStyle.dot`), or it draws neon lines (`.line`): a white core in a red glow,
/// broader where the Pencil presses harder, which stay after each lift so several can be
/// drawn, and all fade together a moment after the last lift. With Apple Pencil hover, the
/// dot shows while the Pencil hovers.
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
            // A line's own glowing end is where it points; the dot is for Dot.
            if style == .line {
                overlay.hideDot()
                overlay.beginTrail(at: point, width: recognizer.lineWidth)
            } else {
                overlay.showDot(at: point)
            }
        case .changed:
            if style == .line { overlay.extendTrail(to: point, width: recognizer.lineWidth) } else { overlay.showDot(at: point) }
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
            if recognizer.zOffset > 0 { overlay.showDot(at: recognizer.location(in: window), isHovering: true) }
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

    /// The width of a laser line's core where the touch is now, from how hard it presses.
    var lineWidth: CGFloat {
        guard let trackedTouch else { return LaserPointerOverlayView.coreWidth(forPressure: nil) }
        let pressure: CGFloat? = trackedTouch.maximumPossibleForce > 0 && trackedTouch.type == .pencil
            ? trackedTouch.force / trackedTouch.maximumPossibleForce : nil
        return LaserPointerOverlayView.coreWidth(forPressure: pressure)
    }
}

/// The layer over a window that the laser pointer draws in. It takes no touches.
///
/// Lines look like a neon tube: a white core in a soft, wide, saturated red glow, which reads
/// on a white page, where the red carries it, and on a dark slide, where the white core
/// does. With Increase Contrast the core gets a crisp red rim and the glow is stronger.
/// While lines show, the glow's brightness pulses gently, unless Reduce Motion is on.
@MainActor
final class LaserPointerOverlayView: UIView {
    /// The laser's red, as on white paper, which it is drawn over in any appearance.
    static let laserColor = UIColor(red: 1, green: 0.15, blue: 0.1, alpha: 1)
    static let dotDiameter: CGFloat = 14
    /// The white core's width with a finger, or a Pencil at middle pressure, in points.
    static let regularCoreWidth: CGFloat = 3
    static let coreWidthRange: ClosedRange<CGFloat> = 1.8...6
    /// How much broader the glow is than the core.
    static let glowWidthFactor: CGFloat = 3
    /// How long lines stay after the last lift before they fade, and how long the fade takes.
    static let idleDelay: TimeInterval = 1
    static let lineFadeDuration: TimeInterval = 0.35
    /// The glow pulses between this share of its brightness and full, once a cycle.
    static let pulseLowestOpacity: Float = 0.7
    static let pulseCycleDuration: CFTimeInterval = 1.6

    /// The core's width for a pressure from 0 to 1 (`force` over its maximum); nil, as for a
    /// finger, gives the regular width.
    static func coreWidth(forPressure pressure: CGFloat?) -> CGFloat {
        guard let pressure, pressure.isFinite else { return regularCoreWidth }
        let clampedPressure = min(max(pressure, 0), 1)
        return coreWidthRange.lowerBound + (coreWidthRange.upperBound - coreWidthRange.lowerBound) * clampedPressure
    }

    /// One line of the laser: its points with the core's width at each.
    struct LaserLine {
        var points: [CGPoint]
        var widths: [CGFloat]
    }

    private let dotLayer = CALayer()
    /// The glow and the core are drawn by two views, so the glow pulses alone.
    private let glowView = LaserLinesView(part: .glow)
    private let coreView = LaserLinesView(part: .core)
    /// Every line drawn since the lines last faded away: they stay after each lift.
    private(set) var lines: [LaserLine] = [] {
        didSet {
            // A line extended needs only the part around its new segment drawn again.
            var changedRegion: CGRect?
            if lines.count == oldValue.count, let line = lines.last, let previousLine = oldValue.last,
               line.points.count == previousLine.points.count + 1, let newPoint = line.points.last, let lastPoint = previousLine.points.last {
                let reach = (Self.coreWidthRange.upperBound * Self.glowWidthFactor) + 16
                changedRegion = CGRect(x: min(newPoint.x, lastPoint.x), y: min(newPoint.y, lastPoint.y),
                                       width: abs(newPoint.x - lastPoint.x), height: abs(newPoint.y - lastPoint.y)).insetBy(dx: -reach, dy: -reach)
            }
            glowView.show(lines, changedRegion: changedRegion)
            coreView.show(lines, changedRegion: changedRegion)
        }
    }
    private(set) var isDrawingLine = false
    private var idleFadeTask: Task<Void, Never>?
    /// Times the wait between the last lift and the fade; a test replaces it to end the wait at once.
    var idleClock: any ApplicationClock = LiveApplicationClock()
    /// True from the start of the fade until the lines are gone or a new line brings them back.
    private(set) var isFading = false

    /// The lines' current opacity, 1 until they fade.
    var linesOpacity: CGFloat {
        // While fading, as shown; otherwise as set, which a presentation not yet redrawn lags.
        guard isFading else { return glowView.alpha }
        return glowView.layer.presentation().map { CGFloat($0.opacity) } ?? glowView.alpha
    }

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
        for linesView in [glowView, coreView] {
            linesView.frame = bounds
            linesView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(linesView)
        }
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
        registerForTraitChanges([UITraitAccessibilityContrast.self]) { (overlay: LaserPointerOverlayView, _: UITraitCollection) in
            overlay.glowView.setNeedsDisplay()
            overlay.coreView.setNeedsDisplay()
        }
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

    /// A new line begins: the lines already shown stay, and a fade under way, or about to
    /// begin, is called off.
    func beginTrail(at point: CGPoint, width: CGFloat = LaserPointerOverlayView.regularCoreWidth) {
        cancelFade()
        isDrawingLine = true
        lines.append(LaserLine(points: [point], widths: [width]))
        startPulsing()
    }

    func extendTrail(to point: CGPoint, width: CGFloat = LaserPointerOverlayView.regularCoreWidth) {
        guard isDrawingLine, !lines.isEmpty else { return }
        lines[lines.count - 1].points.append(point)
        lines[lines.count - 1].widths.append(width)
    }

    /// The touch lifted: the line stays, and every line fades together once no new one has
    /// begun for a moment.
    func endTrail() {
        guard isDrawingLine else { return }
        isDrawingLine = false
        idleFadeTask?.cancel()
        let clock = idleClock
        idleFadeTask = Task { @MainActor [weak self] in
            do { try await clock.sleep(for: .seconds(Self.idleDelay)) } catch { return } // Cancelled by a new line: no fade.
            self?.fadeLines()
        }
    }

    private func cancelFade() {
        idleFadeTask?.cancel()
        idleFadeTask = nil
        guard isFading else { return }
        isFading = false
        // Back to full strength at once, from wherever the fade had got to.
        for linesView in [glowView, coreView] {
            // The fade is the only animation on these views' own layers; the pulse is inside.
            linesView.layer.removeAllAnimations()
            linesView.alpha = 1
        }
    }

    private func fadeLines() {
        idleFadeTask = nil
        guard !lines.isEmpty, !isDrawingLine else { return }
        isFading = true
        // A change of opacity only, which Reduce Motion leaves as it is.
        UIView.animate(withDuration: Self.lineFadeDuration, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            self.glowView.alpha = 0
            self.coreView.alpha = 0
        } completion: { [weak self] _ in
            guard let self, self.isFading else { return }
            self.isFading = false
            self.lines = []
            self.stopPulsing()
            self.glowView.alpha = 1
            self.coreView.alpha = 1
        }
    }

    /// The glow breathes gently while lines show; not with Reduce Motion.
    private func startPulsing() {
        guard !UIAccessibility.isReduceMotionEnabled, glowView.pulseLayer.animation(forKey: "pulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = Self.pulseLowestOpacity
        pulse.duration = Self.pulseCycleDuration / 2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // The pulse multiplies with the fade's opacity through the view's own layer, so it
        // runs on the glow's drawing layer.
        glowView.pulseLayer.add(pulse, forKey: "pulse")
    }

    private func stopPulsing() {
        glowView.pulseLayer.removeAnimation(forKey: "pulse")
    }

    var isPulsing: Bool { glowView.pulseLayer.animation(forKey: "pulse") != nil }
}

/// Draws the laser's lines: their red glow, or their white core, each segment as wide as
/// the core is at its points.
@MainActor
private final class LaserLinesView: UIView {
    enum Part { case glow, core }
    let part: Part
    private(set) var lines: [LaserPointerOverlayView.LaserLine] = []

    func show(_ newLines: [LaserPointerOverlayView.LaserLine], changedRegion: CGRect?) {
        lines = newLines
        if let changedRegion { contentView.setNeedsDisplay(changedRegion) } else { contentView.setNeedsDisplay() }
    }
    /// The view that draws, inside this one, whose opacity the glow's pulse changes.
    private let contentView: LaserLinesDrawingView
    var pulseLayer: CALayer { contentView.layer }

    init(part: Part) {
        self.part = part
        contentView = LaserLinesDrawingView(part: part)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        contentView.frame = bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.linesSource = { [weak self] in self?.lines ?? [] }
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("LaserLinesView is created in code.") }

    override func setNeedsDisplay() {
        super.setNeedsDisplay()
        contentView.setNeedsDisplay()
    }
}

@MainActor
private final class LaserLinesDrawingView: UIView {
    let part: LaserLinesView.Part
    var linesSource: () -> [LaserPointerOverlayView.LaserLine] = { [] }

    init(part: LaserLinesView.Part) {
        self.part = part
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("LaserLinesDrawingView is created in code.") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let lines = linesSource()
        let increasedContrast = traitCollection.accessibilityContrast == .high
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch part {
        case .glow:
            // One soft, wide glow for all the lines together, so overlapping segments do not
            // pile up into darker beads.
            let glowFactor = LaserPointerOverlayView.glowWidthFactor
            context.setShadow(offset: .zero, blur: 12, color: LaserPointerOverlayView.laserColor.withAlphaComponent(increasedContrast ? 1 : 0.9).cgColor)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            // A saturated tube about twice the core, blurred out to about three times it.
            context.setStrokeColor(LaserPointerOverlayView.laserColor.withAlphaComponent(increasedContrast ? 1 : 0.88).cgColor)
            stroke(lines, in: context) { width in width * glowFactor * 0.75 }
            context.endTransparencyLayer()
        case .core:
            if increasedContrast {
                // A crisp red rim sets the white core apart on any page.
                context.setStrokeColor(LaserPointerOverlayView.laserColor.cgColor)
                stroke(lines, in: context) { width in width + 2 }
            }
            context.setStrokeColor(UIColor.white.cgColor)
            stroke(lines, in: context) { width in width }
        }
    }

    /// Each segment at the mean width of its ends; a line of one point is a round spot.
    private func stroke(_ lines: [LaserPointerOverlayView.LaserLine], in context: CGContext, width: (CGFloat) -> CGFloat) {
        for line in lines {
            guard let first = line.points.first else { continue }
            if line.points.count == 1 {
                let spotWidth = width(line.widths.first ?? LaserPointerOverlayView.regularCoreWidth)
                context.setLineWidth(spotWidth)
                context.move(to: first)
                context.addLine(to: first)
                context.strokePath()
                continue
            }
            for index in 1..<line.points.count {
                context.setLineWidth(width((line.widths[index - 1] + line.widths[index]) / 2))
                context.move(to: line.points[index - 1])
                context.addLine(to: line.points[index])
                context.strokePath()
            }
        }
    }
}
#endif
