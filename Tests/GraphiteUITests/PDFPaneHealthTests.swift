import XCTest
@testable import GraphiteUI

/// When finger gestures on a PDF that changed nothing mean the PDF stopped taking touches.
final class PDFPaneHealthTests: XCTestCase {
    private func gesture(fingers: Int = 1, movement: CGFloat = 120, answered: Bool = false, couldMove: Bool = true,
                         drawsWithFinger: Bool = false, secondsSincePencil: TimeInterval = 60) -> UnansweredGestureCount.Gesture {
        UnansweredGestureCount.Gesture(fingerCount: fingers, largestMovement: movement, wasAnswered: answered, couldMove: couldMove,
                                       drawsWithFinger: drawsWithFinger, secondsSincePencil: secondsSincePencil)
    }

    func testThreeUnansweredScrollsInARowMeanThePDFStopped() {
        var count = UnansweredGestureCount()
        XCTAssertFalse(count.add(gesture(), at: 10))
        XCTAssertFalse(count.add(gesture(fingers: 2), at: 12))
        XCTAssertTrue(count.add(gesture(), at: 14))
        XCTAssertTrue(count.unansweredTimes.isEmpty, "The count starts again.")
    }

    func testAnAnsweredGestureStartsTheCountAgain() {
        var count = UnansweredGestureCount()
        XCTAssertFalse(count.add(gesture(), at: 10))
        XCTAssertFalse(count.add(gesture(), at: 11))
        XCTAssertFalse(count.add(gesture(answered: true), at: 12))
        XCTAssertFalse(count.add(gesture(), at: 13))
        XCTAssertFalse(count.add(gesture(), at: 14))
        XCTAssertTrue(count.add(gesture(), at: 15))
    }

    func testGesturesFarApartAreNotInARow() {
        var count = UnansweredGestureCount()
        XCTAssertFalse(count.add(gesture(), at: 0))
        XCTAssertFalse(count.add(gesture(), at: 40))
        XCTAssertFalse(count.add(gesture(), at: 80))
    }

    /// A hand resting while writing, a tap, a page that cannot scroll, and one finger that
    /// draws never count.
    func testGesturesThePDFRightlyIgnoresNeverCount() {
        var count = UnansweredGestureCount()
        for time in 0..<10 {
            XCTAssertFalse(count.add(gesture(secondsSincePencil: 0.5), at: TimeInterval(time)), "A hand resting while the Pencil writes.")
            XCTAssertFalse(count.add(gesture(movement: 10), at: TimeInterval(time)), "A tap.")
            XCTAssertFalse(count.add(gesture(couldMove: false), at: TimeInterval(time)), "A page with nowhere to scroll.")
            XCTAssertFalse(count.add(gesture(drawsWithFinger: true), at: TimeInterval(time)), "A finger that draws.")
        }
        XCTAssertTrue(count.unansweredTimes.isEmpty)
        XCTAssertFalse(count.add(gesture(fingers: 2, drawsWithFinger: true), at: 20), "Two fingers scroll even with finger drawing.")
        XCTAssertEqual(count.unansweredTimes.count, 1)
    }

    /// A drag or a pinch that moved the pages and was put back where it began springs back:
    /// it answered nothing. One that stayed, or that only moved a little, was answered.
    func testAGestureWhoseResultWasPutBackWasUndone() {
        typealias Position = UnansweredGestureCount.PagePosition
        let start = Position(offset: CGPoint(x: 300, y: 1200), scale: 2.5)
        let dragged = Position(offset: CGPoint(x: 300, y: 1450), scale: 2.5)
        XCTAssertTrue(UnansweredGestureCount.wasUndone(from: start, movedTo: dragged, nowAt: start), "Dragged, then put back.")
        XCTAssertTrue(UnansweredGestureCount.wasUndone(from: start, movedTo: dragged, nowAt: Position(offset: CGPoint(x: 301, y: 1201), scale: 2.5)))
        XCTAssertFalse(UnansweredGestureCount.wasUndone(from: start, movedTo: dragged, nowAt: dragged), "Dragged, and it stayed.")
        let pinched = Position(offset: CGPoint(x: 600, y: 1800), scale: 3.5)
        XCTAssertTrue(UnansweredGestureCount.wasUndone(from: start, movedTo: pinched, nowAt: start), "Pinched, then put back.")
        XCTAssertFalse(UnansweredGestureCount.wasUndone(from: start, movedTo: pinched, nowAt: pinched))
        let nudged = Position(offset: CGPoint(x: 300, y: 1210), scale: 2.5)
        XCTAssertFalse(UnansweredGestureCount.wasUndone(from: start, movedTo: nudged, nowAt: start), "A nudge of a few points is not a result.")
    }
}
