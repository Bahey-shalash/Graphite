import XCTest
import GraphiteCore
@testable import GraphiteUI

/// Heading jumps find the heading the outline lists (F511).
final class UiEditorHeadingJumpTests: XCTestCase {
    private let note = """
    ---
    # Summary
    title: A note
    ---
    ```
    # Summary
    ```
    ## Summary
    Text
    ## Notes
    First
    ## Notes
    Second
    """ as NSString

    func testFrontmatterCommentsAndCodeAreNotHeadings() {
        XCTAssertEqual(HeadingLocator.lineLocation(ofHeadingWithAnchor: "summary", in: note), note.range(of: "## Summary").location)
    }

    func testOccurrencePicksAmongHeadingsThatReadTheSame() {
        let firstNotes = note.range(of: "## Notes").location
        let secondNotes = note.range(of: "## Notes", range: NSRange(location: firstNotes + 1, length: note.length - firstNotes - 1)).location
        XCTAssertEqual(HeadingLocator.lineLocation(ofHeadingWithAnchor: "notes", in: note), firstNotes)
        XCTAssertEqual(HeadingLocator.lineLocation(ofHeadingWithAnchor: "notes", occurrence: 1, in: note), secondNotes)
        XCTAssertNil(HeadingLocator.lineLocation(ofHeadingWithAnchor: "notes", occurrence: 2, in: note))
    }

    // MARK: Keeping the heading at the top

    /// Restaurants.md on iPhone (2026-10-19): a base above the heading took seconds to load
    /// its rows, after the 1.5 seconds the jump used to hold the heading, and grew by
    /// thousands of points, leaving another base on screen.
    func testPinHoldsWhileABlockAboveIsStillLoading() {
        var pin = HeadingJumpPin(location: 2672, pinnedAtUptime: 100)
        XCTAssertTrue(pin.holds(atUptime: 100.1, isBlockAboveAwaitingHeight: true))
        XCTAssertTrue(pin.holds(atUptime: 105, isBlockAboveAwaitingHeight: true))
    }

    /// No layout pass runs while the base loads; the first one after it reports its height
    /// is the one that has to put the heading back.
    func testPinHoldsThroughThePassAfterTheBlockAboveReports() {
        var pin = HeadingJumpPin(location: 2672, pinnedAtUptime: 100)
        XCTAssertTrue(pin.holds(atUptime: 100.1, isBlockAboveAwaitingHeight: true))
        XCTAssertTrue(pin.holds(atUptime: 104.2, isBlockAboveAwaitingHeight: false))
        XCTAssertTrue(pin.holds(atUptime: 105.6, isBlockAboveAwaitingHeight: false))
        XCTAssertFalse(pin.holds(atUptime: 104.2 + HeadingJumpPin.settleSeconds, isBlockAboveAwaitingHeight: false))
    }

    func testPinHoldsForAMomentAfterTheHeadingLastMoved() {
        var pin = HeadingJumpPin(location: 892, pinnedAtUptime: 100)
        XCTAssertTrue(pin.holds(atUptime: 101, isBlockAboveAwaitingHeight: false))
        pin.recordMove(atUptime: 103)
        XCTAssertTrue(pin.holds(atUptime: 104, isBlockAboveAwaitingHeight: false))
        XCTAssertFalse(pin.holds(atUptime: 103 + HeadingJumpPin.settleSeconds, isBlockAboveAwaitingHeight: false))
    }

    /// A block that never reports its height cannot hold the view in place for good.
    func testPinEndsAfterTheLongestHoldWhateverTheBlocksAbove() {
        var pin = HeadingJumpPin(location: 892, pinnedAtUptime: 100)
        pin.recordMove(atUptime: 109.9)
        XCTAssertFalse(pin.holds(atUptime: 100 + HeadingJumpPin.longestHoldSeconds, isBlockAboveAwaitingHeight: true))
    }

    // MARK: Viewport coverage

    /// The jump to "Map" on iPhone: the pass after the jump found the viewport TextKit had
    /// laid out for the previous offset, starting at the base below the heading, so the map
    /// above it was never placed and stayed blank.
    func testViewportStartingBelowTheTopOfTheViewIsLaidOutAgain() {
        XCTAssertTrue(ViewportLayoutCoverage.leavesVisibleTextUncovered(laidOutTop: 2081.6, laidOutBottom: 6539, visibleTop: 1896.3, visibleBottom: 2568.3,
                                                                       startsAtDocumentStart: false, endsAtDocumentEnd: false))
    }

    func testViewportEndingAboveTheBottomOfTheViewIsLaidOutAgain() {
        XCTAssertTrue(ViewportLayoutCoverage.leavesVisibleTextUncovered(laidOutTop: 1800, laidOutBottom: 2300, visibleTop: 1896.3, visibleBottom: 2568.3,
                                                                       startsAtDocumentStart: false, endsAtDocumentEnd: false))
    }

    func testViewportCoveringTheViewIsLeftAlone() {
        XCTAssertFalse(ViewportLayoutCoverage.leavesVisibleTextUncovered(laidOutTop: 1880.4, laidOutBottom: 6539, visibleTop: 1896.3, visibleBottom: 2568.3,
                                                                        startsAtDocumentStart: false, endsAtDocumentEnd: false))
    }

    /// Nothing lies above the note's start or below its end, so a short note never asks
    /// for layout again.
    func testGapsAtTheNoteEdgesAreNotUncoveredText() {
        XCTAssertFalse(ViewportLayoutCoverage.leavesVisibleTextUncovered(laidOutTop: 40, laidOutBottom: 300, visibleTop: -86, visibleBottom: 586,
                                                                        startsAtDocumentStart: true, endsAtDocumentEnd: true))
    }
}
