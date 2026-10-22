import XCTest
import GraphiteCore
@testable import GraphiteUI

/// What the graph's model shows first: a graph laid out from nothing once calm, a graph with
/// known places at those places.
@MainActor
final class GraphCanvasModelTests: XCTestCase {
    /// A chain of 40 notes with a branch every fifth note.
    private let graph: LinkGraph = {
        let names = (0..<40).map { number in "Note \(number).md" }
        let edges = (1..<40).map { number in GraphEdge(source: names[number], target: names[number % 5 == 0 ? 0 : number - 1]) }
        return LinkGraph(nodes: names.map { name in GraphNode(id: name, kind: .note) }, edges: edges)
    }()

    func testAGraphLaidOutFromNothingIsFirstShownCalm() async {
        let model = GraphCanvasModel()
        defer { model.stop() }
        await model.load(graph, forces: GraphLayout.Forces(), previousPositions: [:], groupIndexByIdentifier: [:])

        var calmed = GraphLayout(graph: graph)
        calmed.calm()
        XCTAssertEqual(model.positions, calmed.positions, "The first positions shown are the calmed layout's, not the spiral it starts from.")
        XCTAssertNotEqual(model.positions, GraphLayout(graph: graph).positions)
        XCTAssertFalse(model.isCalming)
    }

    func testAGraphWithKnownPlacesIsShownThereAtOnce() async {
        var settled = GraphLayout(graph: graph)
        settled.settle()
        let model = GraphCanvasModel()
        defer { model.stop() }
        await model.load(graph, forces: GraphLayout.Forces(), previousPositions: settled.positionsByIdentifier, groupIndexByIdentifier: [:])

        XCTAssertEqual(model.positions, settled.positions, "Where the person left the nodes, before any step.")
        XCTAssertEqual(model.positionsByIdentifier, settled.positionsByIdentifier)
    }
}
