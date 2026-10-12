import Foundation
import CoreGraphics

/// When Apple Pencil is on the screen, hovering over it, or has just left it, as Graphite's
/// pages have seen it. While it is, a hand on a page being written on is taken for one
/// resting there to write (`PalmRejection`).
struct PencilActivityState: Equatable {
    /// How long after the Pencil lifts, or stops hovering, a hand on the page is still taken
    /// for one resting while writing; a finger scrolls again after that.
    static let lingeringSeconds: TimeInterval = 0.6
    /// A touch or hover not heard from for this long is taken to have ended: an ending that
    /// was missed, as when its view went away, must not stop fingers scrolling for good.
    /// Each is timed on its own, so later strokes do not keep a lost one alive.
    static let staleSeconds: TimeInterval = 20

    private struct PencilTouch: Equatable {
        var touchIdentifier: ObjectIdentifier
        var lastReportTime: TimeInterval
    }

    /// There is one Apple Pencil: a new touch replaces one whose lift was never seen.
    private var pencilTouch: PencilTouch?
    /// The last report of each hover going on, by the recognizer that reports it.
    private var hoverReportTimes: [ObjectIdentifier: TimeInterval] = [:]
    /// When the Pencil last lifted or stopped hovering, on the clock of touch timestamps
    /// (seconds since the system started).
    private var lastLeaveTime: TimeInterval = -.infinity

    mutating func pencilDidTouch(_ touchIdentifier: ObjectIdentifier, at time: TimeInterval) {
        pencilTouch = PencilTouch(touchIdentifier: touchIdentifier, lastReportTime: time)
    }

    mutating func pencilDidMove(at time: TimeInterval) {
        if let pencilTouch, time > pencilTouch.lastReportTime { self.pencilTouch?.lastReportTime = time }
    }

    mutating func pencilDidLift(_ touchIdentifier: ObjectIdentifier, at time: TimeInterval) {
        guard pencilTouch?.touchIdentifier == touchIdentifier else { return }
        pencilTouch = nil
        lastLeaveTime = max(lastLeaveTime, time)
    }

    /// A hover began or moved (`isHovering`), or ended. Only the end of a hover that began
    /// counts: a trackpad's pointer also hovers, and must not make fingers wait.
    mutating func hoverDidChange(_ hoverSourceIdentifier: ObjectIdentifier, isHovering: Bool, at time: TimeInterval) {
        if isHovering {
            hoverReportTimes[hoverSourceIdentifier] = time
        } else if hoverReportTimes.removeValue(forKey: hoverSourceIdentifier) != nil {
            lastLeaveTime = max(lastLeaveTime, time)
        }
    }

    func isPencilTouching(at time: TimeInterval) -> Bool {
        guard let pencilTouch else { return false }
        return time - pencilTouch.lastReportTime <= Self.staleSeconds
    }

    func isActive(at time: TimeInterval) -> Bool {
        isPencilTouching(at: time)
            || hoverReportTimes.values.contains { reportTime in time - reportTime <= Self.staleSeconds }
            || time - lastLeaveTime <= Self.lingeringSeconds
    }
}

/// Which touches on a page are a hand rather than a finger meant to scroll, zoom, tap or
/// select. iPadOS rejects some palm touches itself; the rest reach the page as finger touches.
enum PalmRejection {
    /// A touch this broad, in points across its longest radius, is the side of a hand rather
    /// than a fingertip, which is about half as broad.
    static let palmMajorRadiusPoints: CGFloat = 34

    /// While a page is written on: any finger touch while Apple Pencil is active, and a touch
    /// as broad as a palm. While reading, a hand is a hand that scrolls.
    static func isHandResting(majorRadius: CGFloat, isWriting: Bool, isPencilActive: Bool) -> Bool {
        isWriting && (isPencilActive || (majorRadius.isFinite && majorRadius >= palmMajorRadiusPoints))
    }
}

#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// The Pencil's activity for every page of the app. It is shared rather than given to each
/// page, as `PencilToolbox.shared` is: there is one Apple Pencil and one screen, and a Pencil
/// lifted from one page's canvas is just as near the hand resting on the next.
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
    /// The Pencil's touch ended without being reported, as when its view went away.
    fileprivate static func pencilDidLiftUnseen(_ touchIdentifier: ObjectIdentifier) { state.pencilDidLift(touchIdentifier, at: now) }
    fileprivate static func hoverDidChange(_ hoverRecognizer: UIHoverGestureRecognizer, isHovering: Bool) {
        state.hoverDidChange(ObjectIdentifier(hoverRecognizer), isHovering: isHovering, at: now)
    }

    /// Adds to a page the recognizers that follow the Pencil and take a resting hand's
    /// touches. The owner makes the page's scrolling, zooming, tapping and selecting wait
    /// for the returned recognizer to fail; PencilKit's drawing never waits for it.
    ///
    /// - Parameters:
    ///   - isWriting: Whether the page is written on, the only time a touch is a hand.
    ///   - handDidLand: Called when a hand's touch is taken, as when finger drawing must take
    ///     back the stroke the hand began.
    static func installRecognizers(in view: UIView, isWriting: @escaping @MainActor () -> Bool,
                                   handDidLand: @escaping @MainActor () -> Void) -> PalmRejectionRecognizer {
        let pencilFollower = PencilActivityRecognizer(target: nil, action: nil)
        view.addGestureRecognizer(pencilFollower)
        view.addGestureRecognizer(PencilHoverRecognizer(target: pencilFollower, action: #selector(PencilActivityRecognizer.hoverDidChange(_:))))
        let palmRejection = PalmRejectionRecognizer(target: nil, action: nil)
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
    private var trackedTouchIdentifiers: Set<ObjectIdentifier> = []

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            trackedTouchIdentifiers.insert(ObjectIdentifier(touch))
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
        for touchIdentifier in trackedTouchIdentifiers { PencilActivity.pencilDidLiftUnseen(touchIdentifier) }
        trackedTouchIdentifiers.removeAll()
    }

    private func lift(_ touches: Set<UITouch>) {
        for touch in touches {
            trackedTouchIdentifiers.remove(ObjectIdentifier(touch))
            PencilActivity.pencilDidLift(touch)
        }
        if trackedTouchIdentifiers.isEmpty, state == .possible { state = .failed }
    }

    /// The Pencil hovers above the screen with a height; a trackpad's pointer hovers at none.
    @objc func hoverDidChange(_ hoverRecognizer: UIHoverGestureRecognizer) {
        switch hoverRecognizer.state {
        case .began, .changed: PencilActivity.hoverDidChange(hoverRecognizer, isHovering: hoverRecognizer.zOffset > 0)
        default: PencilActivity.hoverDidChange(hoverRecognizer, isHovering: false)
        }
    }
}

/// Follows a hover without competing with PencilKit's or PDFKit's own hover and pointer
/// handling.
final class PencilHoverRecognizer: UIHoverGestureRecognizer {
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

/// Takes a hand's touches on a page (`PalmRejection.isHandResting`), so the scrolling,
/// zooming, tapping and selecting that wait for it to fail do not happen. Any other touch it
/// lets go at once, so nothing waits on it. It never takes Apple Pencil's touches, never
/// cancels or delays a touch, and prevents nothing but what waits for it.
final class PalmRejectionRecognizer: UIGestureRecognizer {
    var isWriting: @MainActor () -> Bool = { false }
    var handDidLand: @MainActor () -> Void = {}
    private var trackedTouchIdentifiers: Set<ObjectIdentifier> = []

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { trackedTouchIdentifiers.insert(ObjectIdentifier(touch)) }
        switch state {
        case .possible:
            let isWritingOnPage = isWriting()
            let isHandResting = touches.contains { touch in
                PalmRejection.isHandResting(majorRadius: touch.majorRadius, isWriting: isWritingOnPage,
                                            isPencilActive: PencilActivity.isActive(at: touch.timestamp))
            }
            if isHandResting {
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
        trackedTouchIdentifiers.removeAll()
    }

    /// The hand is taken until its last touch lifts.
    private func finish(_ touches: Set<UITouch>, wasCancelled: Bool) {
        for touch in touches { trackedTouchIdentifiers.remove(ObjectIdentifier(touch)) }
        guard trackedTouchIdentifiers.isEmpty else { return }
        switch state {
        case .began, .changed: state = wasCancelled ? .cancelled : .ended
        case .possible: state = .failed
        default: break
        }
    }
}
#endif
