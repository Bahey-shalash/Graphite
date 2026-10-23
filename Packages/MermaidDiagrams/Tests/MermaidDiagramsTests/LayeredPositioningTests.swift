import XCTest
@testable import MermaidDiagrams

final class LayeredPositioningTests: XCTestCase {
    func testTheFitOfAnOrderedSequenceIsTheSequence() {
        XCTAssertEqual(LayeredPositioning.nondecreasingFit([1, 2, 3], weights: [1, 1, 1]), [1, 2, 3])
    }

    func testViolatorsArePooledToTheirWeightedMean() {
        XCTAssertEqual(LayeredPositioning.nondecreasingFit([3, 1, 2], weights: [1, 1, 1]), [2, 2, 2])
        XCTAssertEqual(LayeredPositioning.nondecreasingFit([4, 0], weights: [3, 1]), [3, 3])
        XCTAssertEqual(LayeredPositioning.nondecreasingFit([0, 5, 1, 9], weights: [1, 1, 1, 1]), [0, 3, 3, 9])
    }

    func testTheRanksOfBorderPointsAreTheBorderGapFromTheirNeighbours() throws {
        let sizes = [LayeredSize(across: 0, along: 0), LayeredSize(across: 60, along: 40), LayeredSize(across: 0, along: 0)]
        var graph = try XCTUnwrap(LayeredVertexGraph(nodeSizes: sizes, nodeRanks: [0, 1, 2], orientedEdges: [(0, 1, nil), (1, 2, nil)], maximumVertexCount: 10))
        LayeredOrdering.order(&graph)
        XCTAssertEqual(LayeredPositioning.rankCenters(graph, rankGap: 48, borderGap: 20, startBorderRankCount: 1, endBorderRankCount: 1), [0, 40, 80])
        XCTAssertEqual(LayeredPositioning.rankCenters(graph, rankGap: 48), [0, 68, 136])
    }

    func testAnEdgeHeldOffItsSourcesCenterLinesUpItsTargetWithThatPoint() throws {
        let sizes = [LayeredSize(across: 120, along: 40), LayeredSize(across: 20, along: 20)]
        var graph = try XCTUnwrap(LayeredVertexGraph(nodeSizes: sizes, nodeRanks: [0, 1], orientedEdges: [(0, 1, nil)], maximumVertexCount: 10))
        graph.holdEnds(at: [LayeredChainEndOffsets(upper: 30, lower: 0)])
        LayeredOrdering.order(&graph)
        let centers = LayeredPositioning.acrossCenters(graph, spacing: LayeredSpacing(nodeSeparation: 40, edgeSeparation: 16, rankSeparation: 48))
        XCTAssertEqual(centers[1] - centers[0], 30, accuracy: LayeredPositioning.settledMovement)
    }
}
