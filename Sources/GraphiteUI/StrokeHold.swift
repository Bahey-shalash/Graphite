import Foundation
import CoreGraphics

/// Where a stroke in progress has come to rest, to tell a hold at its end: the Pencil kept
/// still on the page after drawing, which turns the stroke into its shape.
struct StrokeRest: Equatable {
    /// How long the Pencil stays still before the stroke becomes a shape.
    static let holdDuration: TimeInterval = 0.45
    /// How far the touch may wander and still be at rest, in screen points. A resting
    /// Pencil reports small movements, and a finger larger ones.
    static let restingRadius: CGFloat = 6
    /// A shorter stroke is a dot or a tap held down, not a shape.
    static let minimumStrokeLength: CGFloat = 24

    private(set) var restingPoint: CGPoint
    private(set) var strokeLength: CGFloat = 0
    private var lastPoint: CGPoint

    init(startingAt point: CGPoint) {
        restingPoint = point
        lastPoint = point
    }

    /// Follows the touch to a point. True when the touch left its resting place, which is
    /// then the new point: the wait for a hold starts again.
    mutating func move(to point: CGPoint) -> Bool {
        strokeLength += hypot(point.x - lastPoint.x, point.y - lastPoint.y)
        lastPoint = point
        guard hypot(point.x - restingPoint.x, point.y - restingPoint.y) > Self.restingRadius else { return false }
        restingPoint = point
        return true
    }

    var isLongEnoughForAShape: Bool { strokeLength >= Self.minimumStrokeLength }
}

/// The preference for holding the Pencil at the end of a stroke to make a shape.
enum StrokeHoldPreference {
    static let key = "GraphiteMakesShapesOnHold"
    /// On unless turned off in Settings.
    static func isOn(in defaults: UserDefaults = .standard) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
}

#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Watches the touch that draws a stroke on a canvas and reports when it rests. It never
/// recognizes, and neither prevents another recognizer nor is prevented by one, so PencilKit
/// draws as if it were not there.
final class StrokeHoldRecognizer: UIGestureRecognizer {
    /// Whether a touch that begins is one the canvas draws a stroke with.
    var tracksTouch: (UITouch) -> Bool = { _ in true }
    /// The touch has rested; the stroke so far, in the view's coordinates. Called again
    /// when the touch moves on and rests once more.
    var touchDidRest: ([CGPoint]) -> Void = { _ in }
    /// The touch moved, to a point in the view's coordinates. `leftRestingPlace` is true for
    /// the move that takes it away from where it rested or, before any rest, was heading.
    var touchDidMove: (_ point: CGPoint, _ leftRestingPlace: Bool) -> Void = { _, _ in }
    /// The touch lifted, or was cancelled.
    var touchDidEnd: (_ wasCancelled: Bool) -> Void = { _ in }

    private var trackedTouch: UITouch?
    private var rest: StrokeRest?
    private var strokePoints: [CGPoint] = []
    private var holdTimer: Timer?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, let touch = touches.first(where: tracksTouch) else { return }
        trackedTouch = touch
        rest = StrokeRest(startingAt: touch.location(in: nil))
        strokePoints = [touch.location(in: view)]
        scheduleHold()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        for coalescedTouch in event.coalescedTouches(for: trackedTouch) ?? [trackedTouch] {
            strokePoints.append(coalescedTouch.location(in: view))
        }
        let leftRestingPlace = rest?.move(to: trackedTouch.location(in: nil)) == true
        if leftRestingPlace { scheduleHold() }
        touchDidMove(trackedTouch.location(in: view), leftRestingPlace)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        endStroke(wasCancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        endStroke(wasCancelled: true)
    }

    override func reset() {
        super.reset()
        // A reset without the touch ending, as when the recognizer is disabled mid-stroke.
        if trackedTouch != nil { endStroke(wasCancelled: true) }
    }

    private func endStroke(wasCancelled: Bool) {
        holdTimer?.invalidate()
        holdTimer = nil
        trackedTouch = nil
        rest = nil
        strokePoints = []
        touchDidEnd(wasCancelled)
        if state == .possible { state = .failed }
    }

    private func scheduleHold() {
        holdTimer?.invalidate()
        let timer = Timer(timeInterval: StrokeRest.holdDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.touchHasRested() }
        }
        // Common modes: the timer also fires while a scroll view around the canvas tracks.
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    private func touchHasRested() {
        guard trackedTouch != nil, rest?.isLongEnoughForAShape == true else { return }
        touchDidRest(strokePoints)
    }
}
#endif
