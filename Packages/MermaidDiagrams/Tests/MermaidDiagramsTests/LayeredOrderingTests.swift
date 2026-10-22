import XCTest
@testable import MermaidDiagrams

final class LayeredOrderingTests: XCTestCase {
    private let unit = LayeredSize(across: 10, along: 10)

    private func graph(nodeCount: Int, ranks: [Int], edges: [(Int, Int)]) throws -> LayeredVertexGraph {
        try XCTUnwrap(LayeredVertexGraph(nodeSizes: Array(repeating: unit, count: nodeCount), nodeRanks: ranks,
                                         orientedEdges: edges.map { edge in (edge.0, edge.1, nil) }, maximumVertexCount: 100))
    }

    func testCrossingsAreCountedBetweenNeighbouringRanks() throws {
        var crossed = try graph(nodeCount: 4, ranks: [0, 0, 1, 1], edges: [(0, 3), (1, 2)])
        crossed.layers = [[0, 1], [2, 3]]
        XCTAssertEqual(LayeredOrdering.crossingCount(crossed), 1)
        crossed.layers = [[0, 1], [3, 2]]
        XCTAssertEqual(LayeredOrdering.crossingCount(crossed), 0)
    }

    func testEdgesSharingAnEndDoNotCross() throws {
        var fan = try graph(nodeCount: 4, ranks: [0, 1, 1, 1], edges: [(0, 1), (0, 2), (0, 3)])
        fan.layers = [[0], [1, 2, 3]]
        XCTAssertEqual(LayeredOrdering.crossingCount(fan), 0)
    }

    func testAnEdgeSpanningRanksPassesThroughAPointInEachRankBetween() throws {
        let long = try graph(nodeCount: 2, ranks: [0, 3], edges: [(0, 1)])
        XCTAssertEqual(long.vertexCount, 4)
        XCTAssertEqual(long.chains, [[0, 2, 3, 1]])
        XCTAssertTrue(long.isPassingPoint(2))
    }

    func testOrderingRemovesTheCrossingsOfAGraphThatCanBeDrawnWithoutAny() throws {
        // Two crossing pairs over three ranks; untangled, nothing crosses.
        var tangled = try graph(nodeCount: 6, ranks: [0, 0, 1, 1, 2, 2], edges: [(0, 3), (1, 2), (2, 5), (3, 4)])
        LayeredOrdering.order(&tangled)
        XCTAssertEqual(LayeredOrdering.crossingCount(tangled), 0)
        XCTAssertEqual(Set(tangled.layers.flatMap { layer in layer }), Set(0..<6))
    }

    func testTooManyPassingPointsAreRefused() {
        XCTAssertNil(LayeredVertexGraph(nodeSizes: [unit, unit], nodeRanks: [0, 50], orientedEdges: [(0, 1, nil)], maximumVertexCount: 20))
    }

    func testAPinnedNodeStaysFirstOrLastInItsRank() throws {
        var fan = try graph(nodeCount: 4, ranks: [0, 1, 1, 1], edges: [(0, 1), (0, 2), (0, 3)])
        fan.nodePlacements = [.free, .lastInRank, .free, .firstInRank]
        LayeredOrdering.order(&fan)
        XCTAssertEqual(fan.layers[1], [3, 2, 1])
    }
}
