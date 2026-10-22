import Foundation
import Observation
import GraphiteCore

/// Runs a graph layout away from the main thread. Dragging a node goes through it too, so
/// a pin never races a step.
actor GraphSimulator {
    private var layout: GraphLayout

    init(layout: GraphLayout) {
        self.layout = layout
    }

    func advance(steps: Int) -> (positions: [SIMD2<Double>], isSettled: Bool) {
        for _ in 0..<steps where !layout.isSettled { layout.step() }
        return (layout.positions, layout.isSettled)
    }

    func pin(_ identifier: String, at position: SIMD2<Double>) {
        layout.pin(identifier, at: position)
        layout.reheat(to: 0.3)
    }

    func unpin(_ identifier: String) {
        layout.unpin(identifier)
    }

    func change(forces: GraphLayout.Forces) {
        layout.forces = forces
        layout.reheat(to: 0.5)
    }

    var positionsByIdentifier: [String: SIMD2<Double>] { layout.positionsByIdentifier }
}

/// The nodes on screen and where they are, updated as the layout settles.
@MainActor @Observable
final class GraphCanvasModel {
    private(set) var graph = LinkGraph(nodes: [], edges: [])
    private(set) var positions: [SIMD2<Double>] = []
    /// Each edge as the indexes of its nodes.
    private(set) var edgeIndexes: [(source: Int, target: Int)] = []
    private(set) var radii: [Double] = []
    private(set) var neighborIndexes: [Set<Int>] = []
    private(set) var isSettled = true
    /// What the graph shows, counted once when it is loaded.
    private(set) var counts = LinkGraph.Counts()
    /// The group that colors each node, by the node's index; nil where no group does.
    private(set) var groupIndexes: [Int?] = []
    @ObservationIgnored private var indexByIdentifier: [String: Int] = [:]
    /// Each node's name as measured at the names' font, filled as the names are drawn, which
    /// needs their sizes every frame to keep them apart; as long as the graph's nodes.
    @ObservationIgnored private var measuredNameSizes: [CGSize?] = []
    @ObservationIgnored private var simulator: GraphSimulator?
    @ObservationIgnored private var runTask: Task<Void, Never>?

    func load(_ graph: LinkGraph, forces: GraphLayout.Forces, previousPositions: [String: SIMD2<Double>],
              groupIndexByIdentifier: [String: Int]) {
        runTask?.cancel()
        runTask = nil
        let layout = GraphLayout(graph: graph, forces: forces, previousPositions: previousPositions)
        self.graph = graph
        measuredNameSizes = Array(repeating: nil, count: graph.nodes.count)
        colorNodes(by: groupIndexByIdentifier)
        positions = layout.positions
        indexByIdentifier = Dictionary(uniqueKeysWithValues: layout.identifiers.enumerated().map { index, identifier in (identifier, index) })
        edgeIndexes = graph.edges.compactMap { edge in
            guard let source = indexByIdentifier[edge.source], let target = indexByIdentifier[edge.target] else { return nil }
            return (source, target)
        }
        var neighbors = Array(repeating: Set<Int>(), count: graph.nodes.count)
        for edge in edgeIndexes {
            neighbors[edge.source].insert(edge.target)
            neighbors[edge.target].insert(edge.source)
        }
        neighborIndexes = neighbors
        counts = graph.counts
        let linkCounts = graph.linkCounts
        // Obsidian draws well-linked notes larger, and a tag larger the more notes carry it.
        radii = graph.nodes.map { node in 4 + min(Double(linkCounts[node.id] ?? 0).squareRoot(), 8) * 1.3 }
        simulator = GraphSimulator(layout: layout)
        run()
    }

    func index(of identifier: String) -> Int? { indexByIdentifier[identifier] }

    /// A node's name size, measured by `measure` the first time it is asked for.
    func nameSize(ofNodeAt index: Int, measuring measure: () -> CGSize) -> CGSize {
        guard measuredNameSizes.indices.contains(index) else { return measure() }
        if let size = measuredNameSizes[index] { return size }
        let size = measure()
        measuredNameSizes[index] = size
        return size
    }

    /// Takes the groups' coloring of the files, as after a group's search changes.
    func colorNodes(by groupIndexByIdentifier: [String: Int]) {
        groupIndexes = graph.nodes.map { node in groupIndexByIdentifier[node.id] }
    }

    /// What a tap does: on a tag, chooses it or lets it go, so its notes stand out rather
    /// than the graph giving way to a search; on another node, opens it, keeping a chosen
    /// tag so its notes can be opened one after another. Beside the nodes, lets the tag go.
    func tap(nodeAt index: Int?, chosenTag: String?) -> GraphTap {
        guard let index, graph.nodes.indices.contains(index) else { return .choose(nil) }
        let node = graph.nodes[index]
        guard node.kind == .tag else { return .open(node) }
        return .choose(chosenTag == node.id ? nil : node.id)
    }

    func pin(_ identifier: String, at position: SIMD2<Double>) {
        guard let simulator else { return }
        if let index = indexByIdentifier[identifier] { positions[index] = position }
        Task {
            await simulator.pin(identifier, at: position)
            run()
        }
    }

    func unpin(_ identifier: String) {
        guard let simulator else { return }
        Task { await simulator.unpin(identifier) }
    }

    func change(forces: GraphLayout.Forces) {
        guard let simulator else { return }
        Task {
            await simulator.change(forces: forces)
            run()
        }
    }

    var positionsByIdentifier: [String: SIMD2<Double>] {
        Dictionary(uniqueKeysWithValues: graph.nodes.indices.map { index in (graph.nodes[index].id, positions[index]) })
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
    }

    private func run() {
        guard runTask == nil || isSettled, let simulator else { return }
        isSettled = false
        // Two steps a frame settle a graph in about three seconds; a large one takes longer
        // per step, so it is drawn less often.
        let stepsPerUpdate = graph.nodes.count > 3_000 ? 8 : 2
        runTask = Task { [weak self] in
            while !Task.isCancelled {
                let (positions, isSettled) = await simulator.advance(steps: stepsPerUpdate)
                guard let self, !Task.isCancelled else { return }
                self.positions = positions
                if isSettled {
                    self.isSettled = true
                    self.runTask = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
}

/// What a tap on the graph does.
enum GraphTap: Equatable {
    case open(GraphNode)
    /// The tag that stands out with its notes from now on; nil lets it go.
    case choose(String?)
}
