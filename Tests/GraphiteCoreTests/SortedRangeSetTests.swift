import XCTest
@testable import GraphiteCore

final class SortedRangeSetTests: XCTestCase {
    private func range(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }

    func testAnEmptySetIntersectsNothing() {
        let set = SortedRangeSet([])
        XCTAssertTrue(set.isEmpty)
        XCTAssertFalse(set.intersects(range(0, 10)))
    }

    func testEmptyRangesAreLeftOut() {
        let set = SortedRangeSet([range(3, 0), range(8, 0)])
        XCTAssertTrue(set.isEmpty)
        XCTAssertFalse(set.intersects(range(0, 10)))
    }

    func testTouchingRangesMergeButTouchingQueriesDoNotIntersect() {
        let set = SortedRangeSet([range(5, 5), range(0, 5)])
        XCTAssertEqual(set.intervals, [range(0, 10)])
        XCTAssertFalse(set.intersects(range(10, 3)), "A query starting where the set ends shares no position.")
        XCTAssertFalse(SortedRangeSet([range(5, 5)]).intersects(range(2, 3)), "A query ending where the set starts shares no position.")
        XCTAssertTrue(set.intersects(range(9, 3)))
    }

    func testNestedRangesMergeIntoTheOuterOne() {
        let set = SortedRangeSet([range(2, 3), range(0, 10), range(4, 1)])
        XCTAssertEqual(set.intervals, [range(0, 10)])
        XCTAssertTrue(set.intersects(range(3, 1)))
    }

    func testDisjointRangesKeepTheirGaps() {
        let set = SortedRangeSet([range(20, 5), range(0, 5), range(10, 5)])
        XCTAssertEqual(set.intervals, [range(0, 5), range(10, 5), range(20, 5)])
        XCTAssertFalse(set.intersects(range(5, 5)))
        XCTAssertFalse(set.intersects(range(15, 5)))
        XCTAssertFalse(set.intersects(range(25, 100)))
        XCTAssertTrue(set.intersects(range(14, 7)))
        XCTAssertTrue(set.intersects(range(0, 100)))
    }

    func testZeroLengthQueriesIntersectNothingEvenInsideARange() {
        let set = SortedRangeSet([range(0, 10)])
        XCTAssertFalse(set.intersects(range(5, 0)))
        XCTAssertFalse(set.intersects(range(0, 0)))
    }

    func testInsertingMergesWithEveryRangeItOverlapsOrTouches() {
        var set = SortedRangeSet()
        set.insert(range(20, 5))
        set.insert(range(0, 5))
        set.insert(range(10, 2))
        XCTAssertEqual(set.intervals, [range(0, 5), range(10, 2), range(20, 5)])
        set.insert(range(5, 15))
        XCTAssertEqual(set.intervals, [range(0, 25)])
        set.insert(range(30, 0))
        XCTAssertEqual(set.intervals, [range(0, 25)])
    }

    func testInsertingInAnyOrderGivesTheSameSetAsBuildingAtOnce() {
        let ranges = [range(7, 3), range(1, 2), range(30, 4), range(2, 6), range(12, 1), range(34, 1), range(20, 0), range(14, 5)]
        var inserted = SortedRangeSet()
        for insertedRange in ranges.reversed() { inserted.insert(insertedRange) }
        XCTAssertEqual(inserted.intervals, SortedRangeSet(ranges).intervals)
        for location in 0..<40 {
            let query = range(location, 1)
            XCTAssertEqual(inserted.intersects(query), ranges.contains { stored in NSIntersectionRange(stored, query).length > 0 }, "at \(location)")
        }
    }
}
