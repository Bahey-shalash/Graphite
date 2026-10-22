import XCTest
@testable import MermaidDiagrams

final class LayeredRankingTests: XCTestCase {
    private func edge(_ source: Int, _ target: Int, span: Int = 1) -> LayeredEdge {
        LayeredEdge(source: source, target: target, minimumRankSpan: span, labelSize: nil)
    }

    func testTheEdgeThatClosesACycleIsTheOneTurnedAround() {
        let edges = [edge(0, 1), edge(1, 2), edge(2, 0)]
        XCTAssertEqual(LayeredRanking.cycleClosingEdges(nodeCount: 3, edges: edges), [false, false, true])
    }

    func testAGraphWithoutCyclesHasNoEdgeTurned() {
        let edges = [edge(0, 1), edge(0, 2), edge(1, 3), edge(2, 3)]
        XCTAssertEqual(LayeredRanking.cycleClosingEdges(nodeCount: 4, edges: edges), [false, false, false, false])
    }

    func testAPureCycleIsStillBroken() {
        XCTAssertEqual(LayeredRanking.cycleClosingEdges(nodeCount: 2, edges: [edge(0, 1), edge(1, 0)]).filter { isReversed in isReversed }.count, 1)
    }

    func testANodeIsAsLowAsItsLongestPathAndAnEdgeSpansAtLeastItsMinimum() {
        let ranks = LayeredRanking.ranks(nodeCount: 4, orientedEdges: [(0, 1, 1), (1, 2, 1), (0, 2, 1), (2, 3, 3)])
        XCTAssertEqual(ranks, [0, 1, 2, 5])
    }

    func testASideBranchStartsNextToWhereItJoins() {
        // 0 → 1 → 2 → 3, and 4 → 3: node 4 sits right above 3, not at the top.
        let ranks = LayeredRanking.ranks(nodeCount: 5, orientedEdges: [(0, 1, 1), (1, 2, 1), (2, 3, 1), (4, 3, 1)])
        XCTAssertEqual(ranks, [0, 1, 2, 3, 2])
    }

    func testAChainOfThousandsOfNodesIsRankedWithoutExhaustingTheStack() {
        let nodeCount = 20_000
        let edges = (0..<(nodeCount - 1)).map { node in edge(node, node + 1) }
        XCTAssertFalse(LayeredRanking.cycleClosingEdges(nodeCount: nodeCount, edges: edges).contains(true))
        XCTAssertEqual(LayeredRanking.ranks(nodeCount: nodeCount, orientedEdges: edges.map { edge in (edge.source, edge.target, 1) }).last, nodeCount - 1)
    }

    func testBorderPointsTakeRanksBeforeAndAfterTheOtherNodes() {
        // 0 → 1 inside a box; 2 is a point of the border the flow starts from, 3 one of the border it ends at.
        let placements: [LayeredNodePlacement] = [.free, .free, .startBorder, .endBorder]
        let edges = [edge(0, 1), edge(2, 1), edge(0, 3)]
        XCTAssertEqual(LayeredRanking.reversedEdges(nodeCount: 4, edges: edges, placements: placements), [false, false, false])
        XCTAssertEqual(LayeredRanking.ranks(nodeCount: 4, orientedEdges: [(0, 1, 1), (2, 1, 1), (0, 3, 1)], placements: placements, span: 1), [1, 2, 0, 3])
        XCTAssertEqual(LayeredRanking.ranks(nodeCount: 4, orientedEdges: [(0, 1, 2), (2, 1, 2), (0, 3, 2)], placements: placements, span: 2), [2, 4, 0, 6])
    }

    func testAnEdgeOfABorderPointRunsFromTheStartBorderAndToTheEndBorderWhicheverWayItIsWritten() {
        let placements: [LayeredNodePlacement] = [.free, .free, .startBorder, .endBorder]
        let edges = [edge(0, 1), edge(1, 0), edge(1, 2), edge(3, 0)]
        XCTAssertEqual(LayeredRanking.reversedEdges(nodeCount: 4, edges: edges, placements: placements), [false, true, true, true])
    }
}
