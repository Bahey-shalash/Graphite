#if os(iOS)
import XCTest
import UIKit
import UIKit.UIGestureRecognizerSubclass
@testable import GraphiteUI

/// Palm rejection driven by touch sequences of the kinds an iPad delivers, with stand-in
/// touches: whether any leaves the page convinced Apple Pencil is still down, so that every
/// finger is taken for a resting hand and the page neither scrolls nor zooms.
///
/// The ordinary endings (a lift, a cancel, an end reported only on the touch itself, a
/// finger while the Pencil is down) all let fingers scroll again. Only a touch object UIKit
/// leaves going on without ever changing it, or gives to a later finger, kept the page
/// stuck, and only with the previous `PencilActivity`. Whether an iPad does either is not
/// known: no stuck sequence was seen on a device.
@MainActor
final class PalmRejectionTouchTests: XCTestCase {
    private var view: UIView!
    private var pencilFollower: PencilActivityRecognizer!

    override func setUp() async throws {
        PencilActivity.forgetPencil()
        view = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        pencilFollower = PencilActivityRecognizer(target: nil, action: nil)
        view.addGestureRecognizer(pencilFollower)
    }

    override func tearDown() async throws {
        PencilActivity.forgetPencil()
    }

    private let event = UIEvent()

    private func pencilTouch() -> StandInTouch {
        StandInTouch(type: .pencil, phase: .began, timestamp: PencilActivity.now)
    }

    /// Whether a finger landing now is let go to scroll: palm rejection takes a finger only
    /// while the Pencil is active (`PalmRejection.isHandResting`).
    private func fingerScrolls() -> Bool {
        !PalmRejection.isHandResting(isPalmRejectionOn: true, isWriting: true, isPencilActive: PencilActivity.isActive(at: PencilActivity.now))
    }

    private func waitPastLingering(_ seconds: TimeInterval = PencilActivityState.lingeringSeconds + 0.1) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    func testAPencilTouchCancelledLetsFingersScrollAgain() async throws {
        let pencil = pencilTouch()
        pencilFollower.touchesBegan([pencil], with: event)
        XCTAssertFalse(fingerScrolls(), "A finger while the Pencil writes is a resting hand.")
        // The system takes the touch over, as for the palette, Scribble or a tab switch.
        pencil.standInPhase = .cancelled
        pencilFollower.touchesCancelled([pencil], with: event)
        try await waitPastLingering()
        XCTAssertTrue(fingerScrolls())
    }

    func testAPencilTouchWhoseEndGoesElsewhereLetsFingersScrollAgain() async throws {
        let pencil = pencilTouch()
        pencilFollower.touchesBegan([pencil], with: event)
        // Its end is delivered to another view after the page's view was rebuilt mid-stroke:
        // this recognizer only sees the touch end.
        pencil.standInPhase = .ended
        try await waitPastLingering()
        XCTAssertTrue(fingerScrolls())
    }

    func testAFingerWhileThePencilIsDownThenThePencilLifts() async throws {
        let pencil = pencilTouch()
        pencilFollower.touchesBegan([pencil], with: event)
        XCTAssertFalse(fingerScrolls(), "A finger landing while the Pencil writes is a resting hand.")
        pencil.standInTimestamp = PencilActivity.now
        pencil.standInPhase = .ended
        pencilFollower.touchesEnded([pencil], with: event)
        XCTAssertFalse(fingerScrolls(), "Just after the lift the hand is still resting.")
        try await waitPastLingering()
        XCTAssertTrue(fingerScrolls())
    }

    /// UIKit keeps the Pencil's touch object going without ever changing it again, and no
    /// end arrives. With the previous code the Pencil stayed down for as long as the object
    /// did, and every finger was a resting hand.
    func testAPencilTouchLeftGoingWithoutChangeStopsCountingAfterASecond() async throws {
        let pencil = pencilTouch()
        pencilFollower.touchesBegan([pencil], with: event)
        pencil.standInPhase = .stationary
        try await waitPastLingering(PencilActivityState.staleSeconds + PencilActivityState.lingeringSeconds + 0.2)
        XCTAssertTrue(fingerScrolls(), "A touch not changed for over a second is over.")
        withExtendedLifetime(pencil) {}
    }

    /// The Pencil's touch object given to a later finger, without its end reported. With the
    /// previous code the finger's own touch counted as the Pencil still on the screen.
    func testATouchObjectGivenToALaterFingerIsNotThePencil() async throws {
        let pencil = pencilTouch()
        pencilFollower.touchesBegan([pencil], with: event)
        try await waitPastLingering(PencilActivityState.lingeringSeconds + 0.2)
        pencil.standInType = .direct
        pencil.standInPhase = .began
        pencil.standInTimestamp = PencilActivity.now
        XCTAssertTrue(fingerScrolls(), "A finger's touch is not the Pencil.")
        withExtendedLifetime(pencil) {}
    }
}

/// A touch whose type, phase and time a test sets, as UIKit would.
final class StandInTouch: UITouch {
    var standInType: UITouch.TouchType
    var standInPhase: UITouch.Phase
    var standInTimestamp: TimeInterval

    init(type: UITouch.TouchType, phase: UITouch.Phase, timestamp: TimeInterval) {
        standInType = type
        standInPhase = phase
        standInTimestamp = timestamp
        super.init()
    }

    override var type: UITouch.TouchType { standInType }
    override var phase: UITouch.Phase { standInPhase }
    override var timestamp: TimeInterval { standInTimestamp }
    override func location(in view: UIView?) -> CGPoint { CGPoint(x: 100, y: 100) }
}
#endif
