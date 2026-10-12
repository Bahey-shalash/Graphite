#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Follows the touch that draws a stroke on a canvas, every sample of it, for a canvas that
/// shows the stroke itself (the even highlighter's band). It never recognizes, and neither
/// prevents another recognizer nor is prevented by one, so PencilKit draws as if it were not
/// there.
final class DrawnStrokeFollower: UIGestureRecognizer {
    /// Whether a touch that begins is one to follow.
    var followsTouch: (UITouch) -> Bool = { _ in false }
    /// The stroke began at a point in the view's coordinates.
    var strokeDidBegin: (CGPoint) -> Void = { _ in }
    /// The stroke went on through points, and UIKit predicts it goes on through others, in
    /// the view's coordinates. The predicted points are a guess, shown only until the next move.
    var strokeDidMove: (_ points: [CGPoint], _ predictedPoints: [CGPoint]) -> Void = { _, _ in }
    /// The touch lifted, or was cancelled.
    var strokeDidEnd: (_ wasCancelled: Bool) -> Void = { _ in }

    private weak var followedTouch: UITouch?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard followedTouch == nil, let touch = touches.first(where: followsTouch) else { return }
        followedTouch = touch
        strokeDidBegin(touch.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let followedTouch, touches.contains(followedTouch) else { return }
        let points = (event.coalescedTouches(for: followedTouch) ?? [followedTouch]).map { coalescedTouch in coalescedTouch.location(in: view) }
        let predictedPoints = (event.predictedTouches(for: followedTouch) ?? []).map { predictedTouch in predictedTouch.location(in: view) }
        strokeDidMove(points, predictedPoints)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let followedTouch, touches.contains(followedTouch) else { return }
        endStroke(wasCancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let followedTouch, touches.contains(followedTouch) else { return }
        endStroke(wasCancelled: true)
    }

    override func reset() {
        super.reset()
        // A reset without the touch ending, as when the view leaves the window mid-stroke.
        if followedTouch != nil { endStroke(wasCancelled: true) }
    }

    private func endStroke(wasCancelled: Bool) {
        followedTouch = nil
        // It stays possible rather than failing: a failed recognizer hears no more touches
        // until every touch has lifted, and a hand resting on the page keeps one down while
        // the Pencil draws the next stroke.
        strokeDidEnd(wasCancelled)
    }
}
#endif
