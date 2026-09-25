import XCTest
@testable import GraphiteCore

final class LinkGraphTests: XCTestCase {
    private func path(_ text: String) -> VaultPath {
        guard let path = try? VaultPath(text) else { preconditionFailure("Invalid test path \(text)") }
        return path
    }

    /// Lecture ↔ Sampling, Lecture → Figure.png, Sampling → "Missing note", Orphan alone,
    /// Lecture tagged #course/signals and #Course/signals.
    private func sampleGraph() -> LinkGraph {
        LinkGraph.build(
            files: [path("Lecture.md"), path("Sampling.md"), path("Figure.png"), path("Orphan.md"), path("Deep/Far.md")],
            links: [(path("Lecture.md"), path("Sampling.md")), (path("Sampling.md"), path("Lecture.md")),
                    (path("Lecture.md"), path("Figure.png")), (path("Sampling.md"), path("Deep/Far.md")),
                    (path("Lecture.md"), path("Sampling.md"))],
            unresolvedLinks: [(path("Sampling.md"), "Missing note"), (path("Lecture.md"), "missing NOTE")],
            tags: [(path("Lecture.md"), "course/signals"), (path("Sampling.md"), "Course/signals")])
    }

    func testBuildsNodesAndMergesRepeats() {
        let graph = sampleGraph()
        XCTAssertEqual(graph.nodes.map(\.id), ["Lecture.md", "Sampling.md", "Figure.png", "Orphan.md", "Deep/Far.md", "Missing note", "#course/signals"])
        XCTAssertEqual(graph.nodes.map(\.kind), [.note, .note, .attachment, .note, .note, .unresolved, .tag])
        XCTAssertEqual(graph.nodes.map(\.title), ["Lecture", "Sampling", "Figure.png", "Orphan", "Far", "Missing note", "#course/signals"])
        XCTAssertEqual(graph.edges.count, 8, "The repeated link counts once; the unresolved and tag links are merged ignoring capitals.")
        XCTAssertEqual(graph.linkCounts["Lecture.md"], 5)
        XCTAssertNil(graph.linkCounts["Orphan.md"])
    }

    func testFiltersAsObsidiansGraphDoes() {
        let graph = sampleGraph()
        XCTAssertEqual(graph.filtered(by: GraphFilterOptions()).nodes.map(\.id), ["Lecture.md", "Sampling.md", "Orphan.md", "Deep/Far.md"],
                       "By default: no tags, no attachments, existing files only, orphans shown.")
        let everything = graph.filtered(by: GraphFilterOptions(showsTags: true, showsAttachments: true, showsExistingFilesOnly: false))
        XCTAssertEqual(everything.nodes.count, 7)
        XCTAssertEqual(everything.edges.count, 8)
        XCTAssertFalse(graph.filtered(by: GraphFilterOptions(showsOrphans: false)).nodes.contains { node in node.id == "Orphan.md" })

        let searched = graph.filtered(by: GraphFilterOptions(searchText: "far", showsTags: true))
        XCTAssertEqual(searched.nodes.map(\.id), ["Deep/Far.md"], "A tag leaves with the notes that have it.")
        XCTAssertEqual(graph.filtered(by: GraphFilterOptions(searchText: "LECT")).nodes.map(\.id), ["Lecture.md"], "Search ignores capitals.")
        XCTAssertEqual(LinkGraph.build(files: [path("Étude.md")], links: [], unresolvedLinks: [], tags: []).filtered(by: GraphFilterOptions(searchText: "etude")).nodes.count, 1,
                       "Search ignores accents.")
    }

    func testLocalGraphFollowsLinksToTheChosenDepth() {
        let graph = sampleGraph().filtered(by: GraphFilterOptions(showsAttachments: true))
        let firstLevel = graph.neighborhood(of: "Lecture.md", options: LocalGraphOptions())
        XCTAssertEqual(Set(firstLevel.nodes.map(\.id)), ["Lecture.md", "Sampling.md", "Figure.png"])
        let secondLevel = graph.neighborhood(of: "Lecture.md", options: LocalGraphOptions(depth: 2))
        XCTAssertEqual(Set(secondLevel.nodes.map(\.id)), ["Lecture.md", "Sampling.md", "Figure.png", "Deep/Far.md"])

        let incomingOnly = graph.neighborhood(of: "Deep/Far.md", options: LocalGraphOptions(followsOutgoingLinks: false))
        XCTAssertEqual(Set(incomingOnly.nodes.map(\.id)), ["Deep/Far.md", "Sampling.md"])
        let outgoingOnly = graph.neighborhood(of: "Deep/Far.md", options: LocalGraphOptions(followsIncomingLinks: false))
        XCTAssertEqual(outgoingOnly.nodes.map(\.id), ["Deep/Far.md"])

        // Center links to two notes that link to each other: that link is a neighbor link.
        let triangle = LinkGraph(nodes: ["Center", "First", "Second"].map { name in GraphNode(id: name, kind: .note) },
                                 edges: [GraphEdge(source: "Center", target: "First"), GraphEdge(source: "Center", target: "Second"),
                                         GraphEdge(source: "First", target: "Second")])
        XCTAssertEqual(Set(triangle.neighborhood(of: "Center", options: LocalGraphOptions(showsNeighborLinks: false)).edges),
                       [GraphEdge(source: "Center", target: "First"), GraphEdge(source: "Center", target: "Second")], "Only the links followed from the center.")
        XCTAssertEqual(triangle.neighborhood(of: "Center", options: LocalGraphOptions()).edges.count, 3)
        XCTAssertTrue(graph.neighborhood(of: "Not there.md", options: LocalGraphOptions()).nodes.isEmpty)
        XCTAssertEqual(graph.neighborhood(of: "Orphan.md", options: LocalGraphOptions()).nodes.map(\.id), ["Orphan.md"])
    }

    // MARK: Layout

    func testLinkedNodesSettleCloserThanUnlinkedOnes() {
        let graph = LinkGraph(nodes: ["A", "B", "C"].map { name in GraphNode(id: name, kind: .note) }, edges: [GraphEdge(source: "A", target: "B")])
        var layout = GraphLayout(graph: graph)
        layout.settle()
        XCTAssertTrue(layout.isSettled)
        func distance(_ first: String, _ second: String) -> Double {
            guard let firstPosition = layout.position(of: first), let secondPosition = layout.position(of: second) else { return .nan }
            let delta = firstPosition - secondPosition
            return (delta * delta).sum().squareRoot()
        }
        XCTAssertLessThan(distance("A", "B"), distance("A", "C"))
        XCTAssertLessThan(distance("A", "B"), distance("B", "C"))
        XCTAssertGreaterThan(distance("A", "B"), layout.forces.linkDistance * 0.5)
        XCTAssertLessThan(distance("A", "B"), layout.forces.linkDistance * 3)
    }

    func testLayoutIsTheSameEveryTimeAndStaysFinite() {
        let names = (0..<60).map { number in "Note \(number)" }
        let edges = (1..<60).map { number in GraphEdge(source: names[number], target: names[number / 3]) }
        let graph = LinkGraph(nodes: names.map { name in GraphNode(id: name, kind: .note) }, edges: edges)
        var first = GraphLayout(graph: graph), second = GraphLayout(graph: graph)
        first.settle()
        second.settle()
        XCTAssertEqual(first.positions, second.positions)
        XCTAssertTrue(first.positions.allSatisfy { position in position.x.isFinite && position.y.isFinite })

        // Every node in the same place, as a broken earlier layout might leave them.
        let samePlace = Dictionary(uniqueKeysWithValues: names.map { name in (name, SIMD2<Double>(5, 5)) })
        var crowded = GraphLayout(graph: graph, previousPositions: samePlace)
        crowded.settle()
        XCTAssertTrue(crowded.positions.allSatisfy { position in position.x.isFinite && position.y.isFinite })
        XCTAssertGreaterThan(crowded.bounds?.size.x ?? 0, 50, "They spread out.")
    }

    func testAChangedGraphKeepsItsShape() {
        let graph = LinkGraph(nodes: ["A", "B"].map { name in GraphNode(id: name, kind: .note) }, edges: [GraphEdge(source: "A", target: "B")])
        var layout = GraphLayout(graph: graph)
        layout.settle()
        let grown = LinkGraph(nodes: ["A", "B", "C"].map { name in GraphNode(id: name, kind: .note) },
                              edges: [GraphEdge(source: "A", target: "B"), GraphEdge(source: "C", target: "A")])
        let relaid = GraphLayout(graph: grown, previousPositions: layout.positionsByIdentifier)
        XCTAssertEqual(relaid.position(of: "A"), layout.position(of: "A"))
        XCTAssertLessThan(relaid.alpha, 1, "Only adjusts.")
        guard let newPosition = relaid.position(of: "C"), let neighbor = layout.position(of: "A") else { return XCTFail("Missing positions") }
        let delta = newPosition - neighbor
        XCTAssertLessThan((delta * delta).sum().squareRoot(), layout.forces.linkDistance, "A new node starts beside its neighbor.")
    }

    func testPinnedNodesStayWhereTheyAreDragged() {
        let graph = LinkGraph(nodes: ["A", "B"].map { name in GraphNode(id: name, kind: .note) }, edges: [GraphEdge(source: "A", target: "B")])
        var layout = GraphLayout(graph: graph)
        layout.pin("A", at: SIMD2(400, -300))
        layout.reheat(to: 1)
        layout.settle()
        XCTAssertEqual(layout.position(of: "A"), SIMD2(400, -300))
        guard let other = layout.position(of: "B") else { return XCTFail("Missing B") }
        let delta = other - SIMD2(400, -300)
        XCTAssertLessThan((delta * delta).sum().squareRoot(), 300, "Its neighbor follows it.")
    }

    func testTheQuadtreeMatchesTheExactForceWhenNothingIsApproximated() {
        var generator = SplitMixGenerator(seed: 7)
        let positions = (0..<200).map { _ in SIMD2(Double.random(in: -500...500, using: &generator), Double.random(in: -500...500, using: &generator)) }
            + [SIMD2(3, 3), SIMD2(3, 3)]
        let tree = RepulsionTree(positions: positions)
        for index in [0, 57, 199, 200, 201] {
            var exact = SIMD2<Double>.zero
            for other in positions.indices where other != index {
                var delta = positions[other] - positions[index]
                if delta == .zero { delta = GraphLayout.offset(for: other &+ index) * 1e-3 }
                exact += delta * (-30 / max((delta * delta).sum(), 1))
            }
            let fromTree = tree.force(on: index, positions: positions, strength: -30, threshold: 0)
            XCTAssertEqual(fromTree.x, exact.x, accuracy: 1e-9)
            XCTAssertEqual(fromTree.y, exact.y, accuracy: 1e-9)
            let approximated = tree.force(on: index, positions: positions, strength: -30, threshold: 0.9)
            let error = approximated - exact
            XCTAssertLessThan((error * error).sum().squareRoot(), 0.1 * max((exact * exact).sum().squareRoot(), 0.01), "Barnes–Hut stays close.")
        }
    }

    func testALargeGraphSettlesQuickly() {
        let names = (0..<1_500).map { number in "N\(number)" }
        let edges = (1..<1_500).map { number in GraphEdge(source: names[number], target: names[(number * 7) % number]) }
        var layout = GraphLayout(graph: LinkGraph(nodes: names.map { name in GraphNode(id: name, kind: .note) }, edges: edges))
        let start = Date.now
        for _ in 0..<60 { layout.step() }
        XCTAssertLessThan(Date.now.timeIntervalSince(start), 10, "60 steps of 1,500 nodes, even in a debug build.")
    }
}

/// A seeded random number generator, so tests see the same numbers every run.
private struct SplitMixGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
