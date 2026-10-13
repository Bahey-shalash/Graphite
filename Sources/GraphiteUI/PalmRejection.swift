import Foundation
import CoreGraphics

/// Whether a hand resting on a page while Apple Pencil writes is kept from scrolling,
/// zooming, tapping and selecting (Settings › Pencil Drawings › Palm Rejection).
enum PalmRejectionPreference {
    static let key = "GraphitePalmRejection"
    /// On unless turned off in Settings. Read as each touch lands, so a change applies to the
    /// next touch, without opening the page again.
    static func isOn(in defaults: UserDefaults = .standard) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
}

/// When Apple Pencil is on the screen, hovering over it, or has just left it, as Graphite's
/// pages have seen it. While it is, a hand on a page being written on is taken for one
/// resting there to write (`PalmRejection`).
///
/// Which touch and which hover is which is kept by the UIKit side (`PencilActivity`), which
/// holds them weakly and asks UIKit whether each is still going on before this is read.
struct PencilActivityState: Equatable {
    /// How long after the Pencil lifts, or stops hovering, a hand on the page is still taken
    /// for one resting while writing; a finger scrolls again after that.
    static let lingeringSeconds: TimeInterval = 0.6
    /// A touch or hover not heard from for this long is taken to have ended when it was last
    /// heard from. `PencilActivity` hears from every touch and hover still going on each time
    /// it is asked, so this only bounds an ending UIKit could not be asked about: fingers
    /// scroll again within a second of the Pencil's last report.
    static let staleSeconds: TimeInterval = 1

    /// When the Pencil's touch on the screen was last heard from; nil while it is off the
    /// screen. There is one Apple Pencil: a new touch replaces one whose lift was never seen.
    private var touchReportTime: TimeInterval?
    /// The last report of each hover going on, by the number of the recognizer reporting it.
    private var hoverReportTimes: [Int: TimeInterval] = [:]
    /// When the Pencil last lifted or stopped hovering, on the clock of touch timestamps
    /// (seconds since the system started).
    private var lastLeaveTime: TimeInterval = -.infinity

    /// Whether a touch is taken to be on the screen, even one not heard from for a while.
    var hasPencilTouch: Bool { touchReportTime != nil }
    /// The numbers of the hovers taken to be going on.
    var hoveringRecognizerNumbers: [Int] { Array(hoverReportTimes.keys) }

    mutating func pencilDidTouch(at time: TimeInterval) {
        touchReportTime = time
    }

    /// The touch moved, or UIKit says it is still on the screen.
    mutating func pencilDidMove(at time: TimeInterval) {
        if let touchReportTime, time > touchReportTime { self.touchReportTime = time }
    }

    mutating func pencilDidLift(at time: TimeInterval) {
        guard touchReportTime != nil else { return }
        touchReportTime = nil
        lastLeaveTime = max(lastLeaveTime, time)
    }

    /// The touch ended without being reported, as when its view left the window: it is taken
    /// to have lifted when it was last heard from, not now.
    mutating func pencilTouchWasLost() {
        guard let touchReportTime else { return }
        self.touchReportTime = nil
        lastLeaveTime = max(lastLeaveTime, touchReportTime)
    }

    /// A hover began or moved (`isHovering`), or ended. Only the end of a hover that began
    /// counts: a trackpad's pointer also hovers, and must not make fingers wait.
    mutating func hoverDidChange(_ recognizerNumber: Int, isHovering: Bool, at time: TimeInterval) {
        if isHovering {
            hoverReportTimes[recognizerNumber] = max(hoverReportTimes[recognizerNumber] ?? time, time)
        } else if hoverReportTimes.removeValue(forKey: recognizerNumber) != nil {
            lastLeaveTime = max(lastLeaveTime, time)
        }
    }

    /// The hover ended without being reported: it is taken to have ended when last heard from.
    mutating func hoverWasLost(_ recognizerNumber: Int) {
        guard let reportTime = hoverReportTimes.removeValue(forKey: recognizerNumber) else { return }
        lastLeaveTime = max(lastLeaveTime, reportTime)
    }

    func isPencilTouching(at time: TimeInterval) -> Bool {
        guard let touchReportTime else { return false }
        return time - touchReportTime <= Self.staleSeconds
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
    /// A finger touch is a hand resting on the page only while palm rejection is on, the page
    /// is written on, and Apple Pencil is active. Its breadth alone decides nothing: with no
    /// Pencil about, a broad touch is a thumb or a finger laid flat, and it scrolls.
    static func isHandResting(isPalmRejectionOn: Bool, isWriting: Bool, isPencilActive: Bool) -> Bool {
        isPalmRejectionOn && isWriting && isPencilActive
    }

    /// Two reports of one touch's location, in points (the drawing recognizer's and the
    /// touch's own), agree to within this; a Pencil tip is never this close to a hand's touch.
    static let sameTouchTolerancePoints: CGFloat = 0.5

    /// Whether a canvas's stroke is drawn by a hand, so finger drawing may take it back: every
    /// touch PencilKit's drawing recognizer follows is one of the hand's, and Apple Pencil is
    /// not on the screen. Anything else is left alone, so a Pencil stroke is never cancelled.
    static func isStrokeDrawnByHand(drawingTouchLocations: [CGPoint], handTouchLocations: [CGPoint], isPencilTouching: Bool) -> Bool {
        guard !isPencilTouching, !drawingTouchLocations.isEmpty else { return false }
        return drawingTouchLocations.allSatisfy { drawingLocation in
            handTouchLocations.contains { handLocation in
                hypot(drawingLocation.x - handLocation.x, drawingLocation.y - handLocation.y) <= sameTouchTolerancePoints
            }
        }
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
    /// The Pencil's touch on the screen, held weakly: UIKit frees a touch once it has ended,
    /// and another object can later take its address.
    private static weak var pencilTouch: UITouch?
    /// The recognizers that reported the Pencil hovering, by number, held weakly.
    private static var hoveringRecognizers: [Int: WeakHoverRecognizer] = [:]
    private static var lastHoverRecognizerNumber = 0

    private struct WeakHoverRecognizer {
        weak var recognizer: UIGestureRecognizer?
    }

    /// The clock of touch timestamps.
    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    static func isActive(at time: TimeInterval) -> Bool {
        forgetLostEndings()
        return state.isActive(at: time)
    }

    static func isPencilTouching(at time: TimeInterval) -> Bool {
        forgetLostEndings()
        return state.isPencilTouching(at: time)
    }

    /// A number no other hover recognizer has had, unlike an object's address.
    static func newHoverRecognizerNumber() -> Int {
        lastHoverRecognizerNumber += 1
        return lastHoverRecognizerNumber
    }

    /// UIKit can end a touch or a hover without telling the recognizer following it, as when
    /// its view leaves the window mid-stroke. Before the state is read, UIKit is asked about
    /// each: one still going on is heard from now, and one that ended, or whose object is gone,
    /// is taken to have ended when it was last heard from. So a lost ending keeps fingers
    /// waiting no longer than the lingering moment after the Pencil's last report.
    ///
    /// A touch still going on is heard from at its own timestamp, which UIKit advances only
    /// as the touch changes, not at the time of asking: a touch object UIKit kept going, or
    /// gave to a later finger touch, would otherwise keep the Pencil on the screen for good,
    /// and every finger on the page would be taken for a resting hand, so the page would
    /// neither scroll nor zoom.
    private static func forgetLostEndings() {
        let time = now
        if state.hasPencilTouch {
            if let pencilTouch, pencilTouch.type == .pencil, isOngoing(pencilTouch) {
                state.pencilDidMove(at: pencilTouch.timestamp)
            } else {
                state.pencilTouchWasLost()
                pencilTouch = nil
            }
        }
        for recognizerNumber in state.hoveringRecognizerNumbers {
            if let recognizer = hoveringRecognizers[recognizerNumber]?.recognizer, isHovering(recognizer) {
                state.hoverDidChange(recognizerNumber, isHovering: true, at: time)
            } else {
                state.hoverWasLost(recognizerNumber)
                hoveringRecognizers[recognizerNumber] = nil
            }
        }
    }

    /// Forgets the Pencil's touch and hovers, as if it had just left: for a page found to
    /// take no touches (`PDFPaneHealthMonitor`).
    static func forgetPencil() {
        if state.hasPencilTouch { state.pencilTouchWasLost() }
        pencilTouch = nil
        for recognizerNumber in state.hoveringRecognizerNumbers { state.hoverWasLost(recognizerNumber) }
        hoveringRecognizers.removeAll()
    }

    /// The Pencil's activity as the page sees it now, for a diagnostic record.
    static var diagnosticDescription: String {
        let time = now
        let touchDescription = pencilTouch.map { touch in "a touch of type \(touch.type.rawValue), phase \(touch.phase.rawValue), \(String(format: "%.1f", time - touch.timestamp)) s since it changed" } ?? "no touch held"
        return "active \(isActive(at: time)), touching \(isPencilTouching(at: time)), \(touchDescription), hovers \(state.hoveringRecognizerNumbers.count)"
    }

    private static func isOngoing(_ touch: UITouch) -> Bool {
        switch touch.phase {
        case .began, .moved, .stationary: true
        default: false
        }
    }

    /// A hover recognizer is between its beginning and its end only while its view is in a
    /// window: UIKit resets it, without an end, when the view leaves.
    private static func isHovering(_ recognizer: UIGestureRecognizer) -> Bool {
        recognizer.isEnabled && recognizer.view?.window != nil && (recognizer.state == .began || recognizer.state == .changed)
    }

    fileprivate static func pencilDidTouch(_ touch: UITouch) {
        pencilTouch = touch
        state.pencilDidTouch(at: touch.timestamp)
    }

    fileprivate static func pencilDidMove(_ touch: UITouch) {
        guard touch === pencilTouch else { return }
        state.pencilDidMove(at: touch.timestamp)
    }

    fileprivate static func pencilDidLift(_ touch: UITouch) {
        guard touch === pencilTouch else { return }
        pencilTouch = nil
        state.pencilDidLift(at: touch.timestamp)
    }

    /// The Pencil hovers (`isHovering`) over a page, or stopped hovering.
    static func hoverDidChange(_ hoverRecognizer: PencilHoverRecognizer, isHovering: Bool, at time: TimeInterval = now) {
        let recognizerNumber = hoverRecognizer.activityNumber
        hoveringRecognizers[recognizerNumber] = isHovering ? WeakHoverRecognizer(recognizer: hoverRecognizer) : nil
        state.hoverDidChange(recognizerNumber, isHovering: isHovering, at: time)
    }

    /// Adds to a page the recognizers that follow the Pencil and take a resting hand's
    /// touches. The owner makes the page's scrolling, zooming, tapping and selecting wait
    /// for palm rejection with the returned installation; PencilKit's drawing never waits.
    ///
    /// - Parameters:
    ///   - isWriting: Whether the page is written on, the only time a touch is a hand.
    ///   - handTouchesDidChange: Called with a hand's touches as they land and move, as when
    ///     finger drawing must take back the stroke the hand began.
    static func installRecognizers(in view: UIView, isWriting: @escaping @MainActor () -> Bool,
                                   handTouchesDidChange: @escaping @MainActor ([UITouch]) -> Void) -> PalmRejectionInstallation {
        let pencilFollower = PencilActivityRecognizer(target: nil, action: nil)
        view.addGestureRecognizer(pencilFollower)
        view.addGestureRecognizer(PencilHoverRecognizer(target: pencilFollower, action: #selector(PencilActivityRecognizer.hoverDidChange(_:))))
        let palmRejection = PalmRejectionRecognizer(target: nil, action: nil)
        palmRejection.isWriting = isWriting
        palmRejection.handTouchesDidChange = handTouchesDidChange
        view.addGestureRecognizer(palmRejection)
        return PalmRejectionInstallation(recognizer: palmRejection)
    }
}

/// A page's palm rejection recognizer, and the recognizers made to wait for it to fail.
@MainActor
final class PalmRejectionInstallation {
    let recognizer: PalmRejectionRecognizer
    /// Held weakly, so a recognizer made later at a freed one's address is still made to wait.
    private let waitingRecognizers = NSHashTable<UIGestureRecognizer>.weakObjects()

    init(recognizer: PalmRejectionRecognizer) {
        self.recognizer = recognizer
    }

    /// Makes recognizers wait for palm rejection to fail, each once. It fails at once for a
    /// finger while the Pencil is not active, so they do not wait for one.
    func makeWait(_ recognizers: [UIGestureRecognizer]) {
        for waitingRecognizer in recognizers where waitingRecognizer !== recognizer && !waitingRecognizers.contains(waitingRecognizer) {
            waitingRecognizers.add(waitingRecognizer)
            waitingRecognizer.require(toFail: recognizer)
        }
    }

    func isWaiting(_ waitingRecognizer: UIGestureRecognizer) -> Bool {
        waitingRecognizers.contains(waitingRecognizer)
    }
}

/// Follows Apple Pencil's touches on a page, and its hover over it, for `PencilActivity`. It
/// never recognizes and never fails, so it hears every Pencil touch of a sequence, including
/// one that begins while a hand still rests on the page. It never cancels, delays or
/// prevents a touch, so PencilKit draws as if it were not there.
final class PencilActivityRecognizer: UIGestureRecognizer {
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
        for touch in touches { PencilActivity.pencilDidTouch(touch) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { PencilActivity.pencilDidMove(touch) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { PencilActivity.pencilDidLift(touch) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { PencilActivity.pencilDidLift(touch) }
    }

    /// The Pencil hovers above the screen with a height; a trackpad's pointer hovers at none.
    @objc func hoverDidChange(_ hoverRecognizer: PencilHoverRecognizer) {
        switch hoverRecognizer.state {
        case .began, .changed: PencilActivity.hoverDidChange(hoverRecognizer, isHovering: hoverRecognizer.zOffset > 0)
        default: PencilActivity.hoverDidChange(hoverRecognizer, isHovering: false)
        }
    }
}

/// Follows a hover without competing with PencilKit's or PDFKit's own hover and pointer
/// handling.
final class PencilHoverRecognizer: UIHoverGestureRecognizer {
    /// Tells this recognizer's hover from another's in `PencilActivity`.
    let activityNumber = PencilActivity.newHoverRecognizerNumber()

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

/// Takes a hand's touches on a page (`PalmRejection.isHandResting`), so the scrolling,
/// zooming, tapping and selecting that wait for it to fail do not happen. Any other touch it
/// lets go at once, so nothing waits on it. It never takes Apple Pencil's touches, never
/// cancels or delays a touch, and prevents nothing but what waits for it.
final class PalmRejectionRecognizer: UIGestureRecognizer {
    var isWriting: @MainActor () -> Bool = { false }
    var handTouchesDidChange: @MainActor ([UITouch]) -> Void = { _ in }
    /// The hand's touches, held weakly as UIKit owns them.
    private let handTouches = NSHashTable<UITouch>.weakObjects()

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
        switch state {
        case .possible:
            let isPalmRejectionOn = PalmRejectionPreference.isOn()
            let isWritingOnPage = isWriting()
            let isHandResting = touches.contains { touch in
                PalmRejection.isHandResting(isPalmRejectionOn: isPalmRejectionOn, isWriting: isWritingOnPage,
                                            isPencilActive: PencilActivity.isActive(at: touch.timestamp))
            }
            guard isHandResting else {
                state = .failed
                return
            }
            for touch in touches { handTouches.add(touch) }
            state = .began
            handTouchesDidChange(handTouches.allObjects)
        case .began, .changed:
            // Once a hand rests, the touches that join it are taken with it until it lifts.
            for touch in touches { handTouches.add(touch) }
            state = .changed
            handTouchesDidChange(handTouches.allObjects)
        default:
            break
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .began || state == .changed else { return }
        state = .changed
        handTouchesDidChange(handTouches.allObjects)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, wasCancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, wasCancelled: true) }

    override func reset() {
        super.reset()
        handTouches.removeAllObjects()
    }

    /// The hand is taken until its last touch lifts. A touch whose end never reached this
    /// recognizer is let go as well, so the page's scrolling, which waits for this one, is
    /// never held after the hand has gone.
    private func finish(_ touches: Set<UITouch>, wasCancelled: Bool) {
        for touch in touches { handTouches.remove(touch) }
        for touch in handTouches.allObjects where touch.phase == .ended || touch.phase == .cancelled { handTouches.remove(touch) }
        guard handTouches.allObjects.isEmpty else { return }
        switch state {
        case .began, .changed: state = wasCancelled ? .cancelled : .ended
        case .possible: state = .failed
        default: break
        }
    }
}
#endif
