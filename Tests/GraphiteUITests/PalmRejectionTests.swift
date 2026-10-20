import XCTest
@testable import GraphiteUI
import GraphiteTestSupport

/// Which touches on a page are a hand resting there while Apple Pencil writes.
final class PalmRejectionTests: XCTestCase {
    private let firstHover = 1
    private let secondHover = 2

    func testThePencilIsActiveOnTheScreenAndForAMomentAfterItLifts() {
        var activity = PencilActivityState()
        XCTAssertFalse(activity.isActive(at: 100), "Never seen: fingers scroll.")
        activity.pencilDidTouch(at: 100)
        XCTAssertTrue(activity.isActive(at: 100.1))
        XCTAssertTrue(activity.isPencilTouching(at: 100.1))
        activity.pencilDidMove(at: 100.9)
        activity.pencilDidMove(at: 101.8)
        XCTAssertTrue(activity.isActive(at: 102.5), "A stroke that keeps moving keeps it active.")
        activity.pencilDidLift(at: 102.5)
        XCTAssertFalse(activity.isPencilTouching(at: 102.6))
        XCTAssertTrue(activity.isActive(at: 102.5 + PencilActivityState.lingeringSeconds), "A hand that stays after a word is still resting.")
        XCTAssertFalse(activity.isActive(at: 102.5 + PencilActivityState.lingeringSeconds + 0.01), "Then a finger scrolls again.")
    }

    func testFingersScrollWithinASecondOfTheLiftOrTheEndOfTheHover() {
        XCTAssertLessThan(PencilActivityState.lingeringSeconds, 1)
        XCTAssertLessThanOrEqual(PencilActivityState.staleSeconds, 1)
        var activity = PencilActivityState()
        activity.hoverDidChange(firstHover, isHovering: true, at: 10)
        activity.hoverDidChange(firstHover, isHovering: false, at: 11)
        XCTAssertFalse(activity.isActive(at: 12), "Out of range for a second.")
        activity.pencilDidTouch(at: 20)
        activity.pencilDidLift(at: 21)
        XCTAssertFalse(activity.isActive(at: 22), "Lifted for a second.")
    }

    func testALostTouchEndsWhenItWasLastHeardFromNotTwentySecondsLater() {
        var activity = PencilActivityState()
        activity.pencilDidTouch(at: 10)
        activity.pencilDidMove(at: 10.4)
        // UIKit says the touch is gone, as when its view left the window mid-stroke.
        activity.pencilTouchWasLost()
        XCTAssertFalse(activity.hasPencilTouch)
        XCTAssertFalse(activity.isPencilTouching(at: 10.5))
        XCTAssertTrue(activity.isActive(at: 10.4 + PencilActivityState.lingeringSeconds))
        XCTAssertFalse(activity.isActive(at: 10.4 + PencilActivityState.lingeringSeconds + 0.01))
    }

    func testATouchNotHeardFromForASecondIsOver() {
        var activity = PencilActivityState()
        activity.pencilDidTouch(at: 10)
        XCTAssertTrue(activity.isActive(at: 10 + PencilActivityState.staleSeconds))
        XCTAssertFalse(activity.isActive(at: 10 + PencilActivityState.staleSeconds + 0.01))
        XCTAssertFalse(activity.isPencilTouching(at: 10 + PencilActivityState.staleSeconds + 0.01))
    }

    func testANewTouchReplacesOneWhoseLiftWasNeverSeen() {
        var activity = PencilActivityState()
        activity.pencilDidTouch(at: 40)
        activity.pencilDidTouch(at: 50)
        XCTAssertTrue(activity.isPencilTouching(at: 50.5))
        activity.pencilDidLift(at: 51)
        XCTAssertFalse(activity.isPencilTouching(at: 51))
        XCTAssertFalse(activity.isActive(at: 51 + PencilActivityState.lingeringSeconds + 0.01))
        activity.pencilDidLift(at: 52)
        XCTAssertFalse(activity.isActive(at: 52.1), "A lift with no touch on the screen changes nothing.")
    }

    func testAPencilHoveringAboveThePageIsActiveAndAPointersHoverIsNot() {
        var activity = PencilActivityState()
        activity.hoverDidChange(firstHover, isHovering: false, at: 50)
        XCTAssertFalse(activity.isActive(at: 50), "A pointer's hover, at no height, makes fingers wait for nothing.")
        activity.hoverDidChange(firstHover, isHovering: true, at: 60)
        XCTAssertTrue(activity.isActive(at: 60.5), "The hand comes to rest before the Pencil touches.")
        activity.hoverDidChange(firstHover, isHovering: false, at: 60.8)
        XCTAssertTrue(activity.isActive(at: 61.2))
        XCTAssertFalse(activity.isActive(at: 60.8 + PencilActivityState.lingeringSeconds + 0.01))
    }

    func testALostHoverEndsWhenLastHeardFromAndDoesNotOutliveLaterStrokes() {
        var activity = PencilActivityState()
        // A page's hover recognizer went away while the Pencil hovered over it.
        activity.hoverDidChange(firstHover, isHovering: true, at: 0)
        activity.hoverDidChange(secondHover, isHovering: true, at: 0.5)
        XCTAssertEqual(Set(activity.hoveringRecognizerNumbers), [firstHover, secondHover])
        activity.hoverWasLost(firstHover)
        activity.hoverDidChange(secondHover, isHovering: false, at: 0.7)
        XCTAssertEqual(activity.hoveringRecognizerNumbers, [])
        XCTAssertFalse(activity.isActive(at: 0.7 + PencilActivityState.lingeringSeconds + 0.01))
        // A hover nobody can be asked about any more is over a second after its last report.
        activity.hoverDidChange(firstHover, isHovering: true, at: 5)
        XCTAssertFalse(activity.isActive(at: 5 + PencilActivityState.staleSeconds + 0.01))
    }

    func testAHandIsAFingerOnlyWhilePalmRejectionIsOnThePageIsWrittenOnAndThePencilIsActive() {
        XCTAssertTrue(PalmRejection.isHandResting(isPalmRejectionOn: true, isWriting: true, isPencilActive: true))
        XCTAssertFalse(PalmRejection.isHandResting(isPalmRejectionOn: true, isWriting: true, isPencilActive: false),
                       "With no Pencil about, any touch scrolls, however broad.")
        XCTAssertFalse(PalmRejection.isHandResting(isPalmRejectionOn: true, isWriting: false, isPencilActive: true),
                       "While reading, a hand scrolls, even with the Pencil hovering near the screen.")
        XCTAssertFalse(PalmRejection.isHandResting(isPalmRejectionOn: false, isWriting: true, isPencilActive: true),
                       "Turned off in Settings.")
    }

    func testPalmRejectionIsOnUnlessTurnedOffAndIsReadAsItChanges() throws {
        let defaults = try IsolatedDeviceState.make(prefix: "PalmRejectionTests", for: self).preferences
        XCTAssertTrue(PalmRejectionPreference.isOn(in: defaults))
        defaults.set(false, forKey: PalmRejectionPreference.key)
        XCTAssertFalse(PalmRejectionPreference.isOn(in: defaults))
        defaults.set(true, forKey: PalmRejectionPreference.key)
        XCTAssertTrue(PalmRejectionPreference.isOn(in: defaults))
    }

    func testFingerDrawingTakesBackOnlyAStrokeEveryTouchOfWhichIsTheHands() {
        let palm = CGPoint(x: 400, y: 600)
        let pencilTip = CGPoint(x: 250, y: 420)
        XCTAssertTrue(PalmRejection.isStrokeDrawnByHand(drawingTouchLocations: [palm], handTouchLocations: [palm, CGPoint(x: 430, y: 640)],
                                                        isPencilTouching: false))
        XCTAssertTrue(PalmRejection.isStrokeDrawnByHand(drawingTouchLocations: [CGPoint(x: 400.2, y: 600.1)], handTouchLocations: [palm],
                                                        isPencilTouching: false), "The same touch, reported twice.")
        XCTAssertFalse(PalmRejection.isStrokeDrawnByHand(drawingTouchLocations: [pencilTip], handTouchLocations: [palm], isPencilTouching: false),
                       "The Pencil's stroke, though the Pencil's touch was not seen, is never cancelled.")
        XCTAssertFalse(PalmRejection.isStrokeDrawnByHand(drawingTouchLocations: [palm, pencilTip], handTouchLocations: [palm], isPencilTouching: false))
        XCTAssertFalse(PalmRejection.isStrokeDrawnByHand(drawingTouchLocations: [palm], handTouchLocations: [palm], isPencilTouching: true),
                       "Nothing is cancelled while the Pencil is on the screen.")
        XCTAssertFalse(PalmRejection.isStrokeDrawnByHand(drawingTouchLocations: [], handTouchLocations: [palm], isPencilTouching: false),
                       "No stroke being drawn.")
        XCTAssertFalse(PalmRejection.isStrokeDrawnByHand(drawingTouchLocations: [palm], handTouchLocations: [], isPencilTouching: false))
    }
}
