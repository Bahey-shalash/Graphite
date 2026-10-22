import XCTest
@testable import GraphiteCore

/// What stands out while a node is focused: it and its neighbors, the rest stepping back.
final class GraphEmphasisTests: XCTestCase {
    /// 0 – 1 – 2, 3 alone; 4 is the open note, linked to 2.
    private let neighbors: [Set<Int>] = [[1], [0, 2], [1, 4], [], [2]]

    func testTheFocusedNodeKeepsItsNeighborsBrightAndDimsTheRest() {
        let emphasis = GraphEmphasis(focusedIndex: 1, openIndex: 4, neighborIndexes: neighbors)
        XCTAssertFalse(emphasis.isDimmed(1))
        XCTAssertFalse(emphasis.isDimmed(0))
        XCTAssertFalse(emphasis.isDimmed(2))
        XCTAssertTrue(emphasis.isDimmed(3))
        XCTAssertTrue(emphasis.isFocusedLink(source: 0, target: 1))
        XCTAssertTrue(emphasis.isFocusedLink(source: 1, target: 2))
        XCTAssertFalse(emphasis.isFocusedLink(source: 2, target: 4))
    }

    func testWithoutAFocusNothingStepsBackAndNoLinkStandsOut() {
        let emphasis = GraphEmphasis(focusedIndex: nil, openIndex: 4, neighborIndexes: neighbors)
        XCTAssertFalse((0..<5).contains(where: emphasis.isDimmed))
        XCTAssertFalse(emphasis.isFocusedLink(source: 0, target: 1))
        XCTAssertTrue(emphasis.isAccented(4))
        XCTAssertFalse(emphasis.isAccented(0))
    }

    func testTheOpenNoteNeverStepsBackSoItCanAlwaysBeFound() {
        let emphasis = GraphEmphasis(focusedIndex: 0, openIndex: 4, neighborIndexes: neighbors)
        XCTAssertFalse(emphasis.isDimmed(4), "Not a neighbor of the focused node, and still bright.")
        XCTAssertTrue(emphasis.isAccented(4))
        XCTAssertTrue(emphasis.isDimmed(3))
    }

    func testNamesArePlacedOpenNoteFirstThenTheFocusedNodeThenItsNeighbors() {
        let emphasis = GraphEmphasis(focusedIndex: 1, openIndex: 4, neighborIndexes: neighbors)
        XCTAssertEqual((0..<5).map(emphasis.nameImportance(ofNodeAt:)), [1, 2, 1, 0, 3])
    }

    func testAFocusOutsideTheGraphHasNoNeighbors() {
        let emphasis = GraphEmphasis(focusedIndex: 9, openIndex: nil, neighborIndexes: neighbors)
        XCTAssertFalse(emphasis.isNeighborOfFocused(0))
        XCTAssertTrue(emphasis.isDimmed(0))
    }
}
