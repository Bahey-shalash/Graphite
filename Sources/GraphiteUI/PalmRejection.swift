import Foundation
import CoreGraphics

/// When Apple Pencil is on the screen, hovering over it, or has just left it, as Graphite's
/// pages have seen it. While it is, a hand on the page is taken for one resting there to
/// write (`PalmRejection`).
struct PencilActivityState: Equatable {
    /// How long after the Pencil lifts, or stops hovering, a hand on the page is still taken
    /// for one resting while writing; a finger scrolls again after that.
    static let lingeringSeconds: TimeInterval = 0.6
    /// A Pencil reported on the screen or hovering, but not heard from for this long, is
    /// taken to have left: an ending that was missed must not stop fingers scrolling for good.
    static let staleSeconds: TimeInterval = 20

    private var touchingPencils: Set<ObjectIdentifier> = []
    private var hoveringSources: Set<ObjectIdentifier> = []
    /// When the Pencil last touched, moved, lifted, or began or ended a hover, on the clock
    /// of touch timestamps (seconds since the system started).
    private var lastReportTime: TimeInterval = -.infinity

    mutating func pencilDidTouch(_ touch: ObjectIdentifier, at time: TimeInterval) {
        touchingPencils.insert(touch)
        lastReportTime = max(lastReportTime, time)
    }

    mutating func pencilDidMove(at time: TimeInterval) {
        lastReportTime = max(lastReportTime, time)
    }

    mutating func pencilDidLift(_ touch: ObjectIdentifier, at time: TimeInterval) {
        touchingPencils.remove(touch)
        lastReportTime = max(lastReportTime, time)
    }

    /// A hover began or moved (`isHovering`), or ended. Only the end of a hover that began
    /// counts: a trackpad's pointer also hovers, and must not make fingers wait.
    mutating func hoverDidChange(_ source: ObjectIdentifier, isHovering: Bool, at time: TimeInterval) {
        if isHovering {
            hoveringSources.insert(source)
            lastReportTime = max(lastReportTime, time)
        } else if hoveringSources.remove(source) != nil {
            lastReportTime = max(lastReportTime, time)
        }
    }

    func isPencilTouching(at time: TimeInterval) -> Bool {
        !touchingPencils.isEmpty && time - lastReportTime <= Self.staleSeconds
    }

    func isActive(at time: TimeInterval) -> Bool {
        let isOnOrOverTheScreen = (!touchingPencils.isEmpty || !hoveringSources.isEmpty) && time - lastReportTime <= Self.staleSeconds
        return isOnOrOverTheScreen || time - lastReportTime <= Self.lingeringSeconds
    }
}

/// Which touches on a page are a hand rather than a finger meant to scroll, zoom, tap or
/// select. iPadOS rejects some palm touches itself; the rest reach the page as finger touches.
enum PalmRejection {
    /// A touch this broad, in points across its longest radius, is the side of a hand rather
    /// than a fingertip, which is about half as broad.
    static let palmMajorRadius: CGFloat = 34

    /// Any finger touch while Apple Pencil is active, and, while the page is written on, a
    /// touch as broad as a palm.
    static func isHandResting(majorRadius: CGFloat, isWriting: Bool, pencilIsActive: Bool) -> Bool {
        pencilIsActive || (isWriting && majorRadius.isFinite && majorRadius >= palmMajorRadius)
    }
}

#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// The Pencil's activity for every page of the app: one Pencil, one screen.
@MainActor
enum PencilActivity {
    private static var state = PencilActivityState()

    /// The clock of touch timestamps.
    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    static func isActive(at time: TimeInterval) -> Bool { state.isActive(at: time) }
    static func isPencilTouching(at time: TimeInterval) -> Bool { state.isPencilTouching(at: time) }

    fileprivate static func pencilDidTouch(_ touch: UITouch) { state.pencilDidTouch(ObjectIdentifier(touch), at: touch.timestamp) }
    fileprivate static func pencilDidMove(_ touch: UITouch) { state.pencilDidMove(at: touch.timestamp) }
    fileprivate static func pencilDidLift(_ touch: UITouch) { state.pencilDidLift(ObjectIdentifier(touch), at: touch.timestamp) }
    fileprivate static func hoverDidChange(_ hover: UIHoverGestureRecognizer, isHovering: Bool) {
        state.hoverDidChange(ObjectIdentifier(hover), isHovering: isHovering, at: now)
    }

    /// Adds to a page the recognizers that follow the Pencil and take a resting hand's
    /// touches. The owner makes the page's scrolling, zooming, tapping and selecting wait
    /// for the returned recognizer to fail; PencilKit's drawing never waits for it.
    ///
    /// - Parameters:
    ///   - isWriting: Whether the page is written on, where a palm-sized touch is a hand.
    ///   - handDidLand: Called when a hand's touch is taken, as when finger drawing must take
    ///     back the stroke the hand began.
    static func installRecognizers(in view: UIView, isWriting: @escaping @MainActor () -> Bool,
                                   handDidLand: @escaping @MainActor () -> Void) -> PalmRejectionRecognizer {
        let pencilFollower = PencilActivityRecognizer()
        view.addGestureRecognizer(pencilFollower)
        let hover = UIHoverGestureRecognizer(target: pencilFollower, action: #selector(PencilActivityRecognizer.hoverDidChange(_:)))
        view.addGestureRecognizer(hover)
        let palmRejection = PalmRejectionRecognizer()
        palmRejection.isWriting = isWriting
        palmRejection.handDidLand = handDidLand
        view.addGestureRecognizer(palmRejection)
        return palmRejection
    }
}

/// Follows Apple Pencil's touches on a page, and its hover over it, for `PencilActivity`. It
/// never recognizes, and never cancels, delays or prevents a touch, so PencilKit draws as if
/// it were not there.
final class PencilActivityRecognizer: UIGestureRecognizer {
    private var trackedTouches: Set<ObjectIdentifier> = []

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            trackedTouches.insert(ObjectIdentifier(touch))
            PencilActivity.pencilDidTouch(touch)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { PencilActivity.pencilDidMove(touch) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }

    override func reset() {
        super.reset()
        // Reset without the touches ending, as when the view leaves the window mid-stroke:
        // the Pencil is taken to have lifted, so fingers scroll again.
        if !trackedTouches.isEmpty {
            PencilActivity.pencilsDidLiftUnseen(trackedTouches)
            trackedTouches.removeAll()
        }
    }

    private func lift(_ touches: Set<UITouch>) {
        for touch in touches {
            trackedTouches.remove(ObjectIdentifier(touch))
            PencilActivity.pencilDidLift(touch)
        }
        if trackedTouches.isEmpty, state == .possible { state = .failed }
    }

    /// The Pencil hovers above the screen with a height; a trackpad's pointer hovers at none.
    @objc func hoverDidChange(_ hover: UIHoverGestureRecognizer) {
        switch hover.state {
        case .began, .changed: PencilActivity.hoverDidChange(hover, isHovering: hover.zOffset > 0)
        default: PencilActivity.hoverDidChange(hover, isHovering: false)
        }
    }
}

extension PencilActivity {
    /// The Pencil's touches ended without being reported, as when their view went away.
    fileprivate static func pencilsDidLiftUnseen(_ touches: Set<ObjectIdentifier>) {
        for touch in touches { state.pencilDidLift(touch, at: now) }
    }
}

/// Takes a hand's touches on a page (`PalmRejection.isHandResting`), so the scrolling,
/// zooming, tapping and selecting that wait for it to fail do not happen. Any other touch it
/// lets go at once, so nothing waits on it. It never takes Apple Pencil's touches, never
/// cancels or delays a touch, and prevents nothing but what waits for it.
final class PalmRejectionRecognizer: UIGestureRecognizer {
    var isWriting: @MainActor () -> Bool = { false }
    var handDidLand: @MainActor () -> Void = {}
    private var trackedTouches: Set<ObjectIdentifier> = []

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { trackedTouches.insert(ObjectIdentifier(touch)) }
        switch state {
        case .possible:
            let isWritingOnPage = isWriting()
            let isHand = touches.contains { touch in
                PalmRejection.isHandResting(majorRadius: touch.majorRadius, isWriting: isWritingOnPage,
                                            pencilIsActive: PencilActivity.isActive(at: touch.timestamp))
            }
            if isHand {
                state = .began
                handDidLand()
            } else {
                state = .failed
            }
        case .began, .changed:
            state = .changed
        default:
            break
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .began || state == .changed { state = .changed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, wasCancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, wasCancelled: true) }

    override func reset() {
        super.reset()
        trackedTouches.removeAll()
    }

    /// The hand is taken until its last touch lifts.
    private func finish(_ touches: Set<UITouch>, wasCancelled: Bool) {
        for touch in touches { trackedTouches.remove(ObjectIdentifier(touch)) }
        guard trackedTouches.isEmpty else { return }
        switch state {
        case .began, .changed: state = wasCancelled ? .cancelled : .ended
        case .possible: state = .failed
        default: break
        }
    }
}
#endif
