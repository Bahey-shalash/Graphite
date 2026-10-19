import XCTest
@testable import GraphiteUI

/// The two intervals that decide how long after the Pencil a hand on the page is still taken
/// for one resting there to write. The values are pinned as numbers, and the behaviour just
/// inside and just outside them: a change to either is a change to when fingers scroll again.
final class PencilActivityStateTimingTests: XCTestCase {
    func testThePencilStaysActiveForSixTenthsOfASecondAfterItLeavesAndNoLonger() {
        XCTAssertEqual(PencilActivityState.lingeringSeconds, 0.6)
        var activity = PencilActivityState()
        activity.pencilDidTouch(at: 100)
        activity.pencilDidLift(at: 100.5)
        XCTAssertTrue(activity.isActive(at: 101.09), "Just under 0.6 s after the lift is still active.")
        XCTAssertFalse(activity.isActive(at: 101.11), "Just over 0.6 s after the lift fingers scroll again.")
    }

    func testAHoverThatEndsLeavesTheSameSixTenthsOfASecond() {
        var activity = PencilActivityState()
        activity.hoverDidChange(7, isHovering: true, at: 10)
        activity.hoverDidChange(7, isHovering: false, at: 10.25)
        XCTAssertTrue(activity.isActive(at: 10.84))
        XCTAssertFalse(activity.isActive(at: 10.86))
    }

    func testAReportOlderThanOneSecondCountsAsEndedAtItsLastReport() {
        XCTAssertEqual(PencilActivityState.staleSeconds, 1)
        var activity = PencilActivityState()
        activity.pencilDidTouch(at: 50)
        XCTAssertTrue(activity.isPencilTouching(at: 51), "A report exactly one second old still counts.")
        XCTAssertFalse(activity.isPencilTouching(at: 51.01))
        // The touch whose lift was never seen is taken to have ended when it was last heard from.
        activity.pencilTouchWasLost()
        XCTAssertTrue(activity.isActive(at: 50.59))
        XCTAssertFalse(activity.isActive(at: 50.61))
    }

    func testAHoverNotHeardFromForOneSecondStopsCounting() {
        var activity = PencilActivityState()
        activity.hoverDidChange(3, isHovering: true, at: 20)
        XCTAssertTrue(activity.isActive(at: 21))
        XCTAssertFalse(activity.isActive(at: 21.01))
        activity.hoverWasLost(3)
        XCTAssertTrue(activity.isActive(at: 20.59), "A lost hover ended when it was last heard from.")
        XCTAssertFalse(activity.isActive(at: 20.61))
    }
}
