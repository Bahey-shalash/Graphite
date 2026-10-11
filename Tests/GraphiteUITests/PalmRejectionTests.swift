import XCTest
@testable import GraphiteUI

/// Which touches on a page are a hand resting there while Apple Pencil writes.
final class PalmRejectionTests: XCTestCase {
    // Kept alive for the whole test, so no two of them can share an identifier.
    private let firstPencilTouch = NSObject()
    private let secondPencilTouch = NSObject()
    private let firstHoverRecognizer = NSObject()
    private let secondHoverRecognizer = NSObject()
    private var firstPencilTouchIdentifier: ObjectIdentifier { ObjectIdentifier(firstPencilTouch) }
    private var secondPencilTouchIdentifier: ObjectIdentifier { ObjectIdentifier(secondPencilTouch) }
    private var firstHoverIdentifier: ObjectIdentifier { ObjectIdentifier(firstHoverRecognizer) }
    private var secondHoverIdentifier: ObjectIdentifier { ObjectIdentifier(secondHoverRecognizer) }

    func testThePencilIsActiveOnTheScreenAndForAMomentAfterItLifts() {
        var activity = PencilActivityState()
        XCTAssertFalse(activity.isActive(at: 100), "Never seen: fingers scroll.")
        activity.pencilDidTouch(firstPencilTouchIdentifier, at: 100)
        XCTAssertTrue(activity.isActive(at: 100.1))
        XCTAssertTrue(activity.isPencilTouching(at: 100.1))
        activity.pencilDidMove(at: 105)
        XCTAssertTrue(activity.isActive(at: 110), "A long stroke keeps it active.")
        activity.pencilDidLift(firstPencilTouchIdentifier, at: 110)
        XCTAssertFalse(activity.isPencilTouching(at: 110.1))
        XCTAssertTrue(activity.isActive(at: 110 + PencilActivityState.lingeringSeconds), "A hand that stays after a word is still resting.")
        XCTAssertFalse(activity.isActive(at: 110 + PencilActivityState.lingeringSeconds + 0.01), "Then a finger scrolls again.")
    }

    func testALostLiftDoesNotKeepThePencilActiveAndANewTouchReplacesIt() {
        var activity = PencilActivityState()
        // A touch whose lift was never seen is let go of after a while without news.
        activity.pencilDidTouch(firstPencilTouchIdentifier, at: 10)
        XCTAssertTrue(activity.isActive(at: 10 + PencilActivityState.staleSeconds))
        XCTAssertFalse(activity.isActive(at: 10 + PencilActivityState.staleSeconds + 0.01))
        XCTAssertFalse(activity.isPencilTouching(at: 10 + PencilActivityState.staleSeconds + 0.01))

        // There is one Pencil: its next touch takes the lost one's place, and its lift ends both.
        activity.pencilDidTouch(secondPencilTouchIdentifier, at: 40)
        activity.pencilDidLift(firstPencilTouchIdentifier, at: 41)
        XCTAssertTrue(activity.isPencilTouching(at: 41), "The lift of a touch already replaced changes nothing.")
        activity.pencilDidLift(secondPencilTouchIdentifier, at: 42)
        XCTAssertFalse(activity.isPencilTouching(at: 42))
        XCTAssertFalse(activity.isActive(at: 42 + PencilActivityState.lingeringSeconds + 0.01))
    }

    func testAPencilHoveringAboveThePageIsActiveAndAPointersHoverIsNot() {
        var activity = PencilActivityState()
        activity.hoverDidChange(firstHoverIdentifier, isHovering: false, at: 50)
        XCTAssertFalse(activity.isActive(at: 50), "A pointer's hover, at no height, makes fingers wait for nothing.")
        activity.hoverDidChange(firstHoverIdentifier, isHovering: true, at: 60)
        XCTAssertTrue(activity.isActive(at: 61), "The hand comes to rest before the Pencil touches.")
        activity.hoverDidChange(firstHoverIdentifier, isHovering: false, at: 62)
        XCTAssertTrue(activity.isActive(at: 62.5))
        XCTAssertFalse(activity.isActive(at: 62 + PencilActivityState.lingeringSeconds + 0.01))
    }

    func testAHoverWhoseEndWasLostExpiresEvenWhileThePencilKeepsWriting() {
        var activity = PencilActivityState()
        // A page's hover recognizer went away while the Pencil hovered over it.
        activity.hoverDidChange(firstHoverIdentifier, isHovering: true, at: 0)
        // Later strokes and hovers elsewhere do not keep that hover alive.
        activity.hoverDidChange(secondHoverIdentifier, isHovering: true, at: 15)
        activity.hoverDidChange(secondHoverIdentifier, isHovering: false, at: 16)
        activity.pencilDidTouch(firstPencilTouchIdentifier, at: 25)
        activity.pencilDidLift(firstPencilTouchIdentifier, at: 26)
        XCTAssertTrue(activity.isActive(at: 26.5))
        XCTAssertFalse(activity.isActive(at: 26 + PencilActivityState.lingeringSeconds + 0.01),
                       "Fingers scroll a moment after the stroke, not twenty seconds after it.")
    }

    func testAHandIsAnyFingerWhileThePencilIsActiveAndAPalmWhileWriting() {
        XCTAssertTrue(PalmRejection.isHandResting(majorRadius: 8, isWriting: true, isPencilActive: true))
        XCTAssertFalse(PalmRejection.isHandResting(majorRadius: 12, isWriting: true, isPencilActive: false), "A fingertip scrolls.")
        XCTAssertTrue(PalmRejection.isHandResting(majorRadius: PalmRejection.palmMajorRadiusPoints, isWriting: true, isPencilActive: false))
        XCTAssertFalse(PalmRejection.isHandResting(majorRadius: .nan, isWriting: true, isPencilActive: false))
        // While reading, a hand scrolls, even with the Pencil hovering near the screen.
        XCTAssertFalse(PalmRejection.isHandResting(majorRadius: 8, isWriting: false, isPencilActive: true))
        XCTAssertFalse(PalmRejection.isHandResting(majorRadius: 60, isWriting: false, isPencilActive: false))
    }
}
