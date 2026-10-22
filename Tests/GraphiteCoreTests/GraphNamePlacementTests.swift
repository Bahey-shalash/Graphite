import XCTest
@testable import GraphiteCore

/// Names in the graph never cover one another: the more important name stays and the one
/// that would cover it is left out at this zoom.
final class GraphNamePlacementTests: XCTestCase {
    private func candidate(_ nodeIndex: Int, x: Double, y: Double, width: Double = 60, importance: Int = 0, radius: Double = 4) -> GraphNamePlacement.Candidate {
        GraphNamePlacement.Candidate(nodeIndex: nodeIndex, frame: CGRect(x: x, y: y, width: width, height: 14), importance: importance, nodeRadius: radius)
    }

    func testANameThatWouldCoverOneAlreadyPlacedIsLeftOut() {
        let placed = GraphNamePlacement.placedNames([candidate(0, x: 0, y: 0), candidate(1, x: 40, y: 6), candidate(2, x: 200, y: 0)])
        XCTAssertEqual(placed, [0, 2])
    }

    func testTheMoreImportantNameStaysWhateverItsPlaceInTheList() {
        let placed = GraphNamePlacement.placedNames([candidate(0, x: 0, y: 0), candidate(1, x: 10, y: 0, importance: 3), candidate(2, x: 20, y: 4, importance: 1)])
        XCTAssertEqual(placed, [1], "The open note's name (3) wins over a neighbor's (1) and over the others (0).")
    }

    func testAmongEqualsTheLargerNodesNameIsPlacedFirstThenTheFirstNode() {
        XCTAssertEqual(GraphNamePlacement.placedNames([candidate(4, x: 0, y: 0, radius: 4), candidate(7, x: 5, y: 0, radius: 9)]), [7])
        XCTAssertEqual(GraphNamePlacement.placedNames([candidate(7, x: 0, y: 0), candidate(4, x: 5, y: 0)]), [4], "The same each frame, so names do not flicker.")
    }

    func testNamesThatOnlyTouchOrSitInOtherCellsAreAllKept() {
        let row = (0..<40).map { index in candidate(index, x: Double(index) * 60, y: 0) }
        XCTAssertEqual(GraphNamePlacement.placedNames(row).count, 40, "Side by side, touching names cover nothing.")
        let wide = candidate(0, x: -500, y: 300, width: 1_000)
        XCTAssertEqual(GraphNamePlacement.placedNames([wide, candidate(1, x: 380, y: 305)]), [0], "A wide name spans several cells and still keeps its room.")
    }

    func testANameWithoutAFinitePlaceIsLeftOut() {
        let lost = GraphNamePlacement.Candidate(nodeIndex: 3, frame: CGRect(x: Double.nan, y: 0, width: 10, height: 10), importance: 3, nodeRadius: 4)
        XCTAssertEqual(GraphNamePlacement.placedNames([lost, candidate(1, x: 0, y: 0)]), [1])
    }
}
