import XCTest
@testable import GraphiteUI

/// Which touches on a page are a hand resting there while Apple Pencil writes.
final class PalmRejectionTests: XCTestCase {
    private let firstPencilTouch = ObjectIdentifier(NSObject())
    private let secondPencilTouch = ObjectIdentifier(NSObject())
    private let hover = ObjectIdentifier(NSObject())

    func testThePencilIsActiveOnTheScreenAndForAMomentAfterItLifts() {
        var activity = PencilActivityState()
        XCTAssertFalse(activity.isActive(at: 100), "Never seen: fingers scroll.")
        activity.pencilDidTouch(firstPencilTouch, at: 100)
        XCTAssertTrue(activity.isActive(at: 100.1))
        XCTAssertTrue(activity.isPencilTouching(at: 100.1))
        activity.pencilDidMove(at: 105)
        XCTAssertTrue(activity.isActive(at: 110), "A long stroke keeps it active.")
        activity.pencilDidLift(firstPencilTouch, at: 110)
        XCTAssertFalse(activity.isPencilTouching(at: 110.1))
        XCTAssertTrue(activity.isActive(at: 110 + PencilActivityState.lingeringSeconds), "A hand that stays after a word is still resting.")
        XCTAssertFalse(activity.isActive(at: 110 + PencilActivityState.lingeringSeconds + 0.01), "Then a finger scrolls again.")
    }

    func testEveryPencilTouchHasToLiftAndAMissedLiftDoesNotLastForever() {
        var activity = PencilActivityState()
        activity.pencilDidTouch(firstPencilTouch, at: 10)
        activity.pencilDidTouch(secondPencilTouch, at: 10.2)
        activity.pencilDidLift(firstPencilTouch, at: 11)
        XCTAssertTrue(activity.isPencilTouching(at: 12))
        // A touch whose lift was never seen is let go of after a while without news.
        XCTAssertTrue(activity.isActive(at: 11 + PencilActivityState.staleSeconds))
        XCTAssertFalse(activity.isActive(at: 11 + PencilActivityState.staleSeconds + 0.01))
        XCTAssertFalse(activity.isPencilTouching(at: 11 + PencilActivityState.staleSeconds + 0.01))
        // Lifting a touch twice, or one never seen, changes nothing else.
        activity.pencilDidLift(secondPencilTouch, at: 12)
        activity.pencilDidLift(secondPencilTouch, at: 12)
        XCTAssertFalse(activity.isPencilTouching(at: 12))
    }

    func testAPencilHoveringAboveThePageIsActiveAndAPointersHoverIsNot() {
        var activity = PencilActivityState()
        activity.hoverDidChange(hover, isHovering: false, at: 50)
        XCTAssertFalse(activity.isActive(at: 50), "A pointer's hover, at no height, makes fingers wait for nothing.")
        activity.hoverDidChange(hover, isHovering: true, at: 60)
        XCTAssertTrue(activity.isActive(at: 61), "The hand comes to rest before the Pencil touches.")
        activity.hoverDidChange(hover, isHovering: false, at: 62)
        XCTAssertTrue(activity.isActive(at: 62.5))
        XCTAssertFalse(activity.isActive(at: 62 + PencilActivityState.lingeringSeconds + 0.01))
    }

    func testAHandIsAnyFingerWhileThePencilIsActiveAndAPalmWhileWriting() {
        XCTAssertTrue(PalmRejection.isHandResting(majorRadius: 8, isWriting: true, pencilIsActive: true))
        XCTAssertTrue(PalmRejection.isHandResting(majorRadius: 8, isWriting: false, pencilIsActive: true))
        XCTAssertFalse(PalmRejection.isHandResting(majorRadius: 12, isWriting: true, pencilIsActive: false), "A fingertip scrolls.")
        XCTAssertTrue(PalmRejection.isHandResting(majorRadius: PalmRejection.palmMajorRadius, isWriting: true, pencilIsActive: false))
        XCTAssertFalse(PalmRejection.isHandResting(majorRadius: 60, isWriting: false, pencilIsActive: false), "While reading, a broad touch still scrolls.")
        XCTAssertFalse(PalmRejection.isHandResting(majorRadius: .nan, isWriting: true, pencilIsActive: false))
    }
}
