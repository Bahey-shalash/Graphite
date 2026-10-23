import CoreGraphics

/// A ranked graph whose edges each join two neighbouring ranks: an edge that spans several ranks passes through one
/// extra vertex in each rank between its ends. Vertices `0..<nodeCount` are the graph's nodes; the rest are those
/// passing points. Each edge runs downward, from its upper end to its lower end.
struct LayeredVertexGraph {
    let nodeCount: Int
    private(set) var rank: [Int]
    /// Extent of each vertex: a node's size, zero for a passing point, the text's size for the point an edge's text
    /// sits on.
    private(set) var size: [LayeredSize]
    /// The vertices of each rank, in their order across.
    var layers: [[Int]]
    private(set) var upperNeighbors: [[Int]]
    private(set) var lowerNeighbors: [[Int]]
    /// For each edge of the graph, its vertices from upper end to lower end.
    private(set) var chains: [[Int]]
    /// For each edge of the graph, the vertex its text sits on, or nil.
    private(set) var labelVertices: [Int?]
    /// Where each node must go (`LayeredGraph.nodePlacements`); empty when every node is free.
    var nodePlacements: [LayeredNodePlacement] = []
    /// For each vertex, the offsets of the links to its upper and lower neighbours, parallel to `upperNeighbors` and
    /// `lowerNeighbors`; empty when no edge is held off a center (`LayeredEdge.sourceOffset`).
    private(set) var upperLinkOffsets: [[LayeredLinkOffsets]] = []
    private(set) var lowerLinkOffsets: [[LayeredLinkOffsets]] = []
    /// For each edge, the offsets at its upper and lower ends; empty when no edge is held off a center.
    private(set) var chainEndOffsets: [LayeredChainEndOffsets] = []

    func isPassingPoint(_ vertex: Int) -> Bool { vertex >= nodeCount }
    var vertexCount: Int { rank.count }
    var hasLinkOffsets: Bool { !upperLinkOffsets.isEmpty }

    /// Where `vertex` must go; free for a passing point.
    func placement(of vertex: Int) -> LayeredNodePlacement {
        vertex < nodePlacements.count ? nodePlacements[vertex] : .free
    }

    /// - Parameters:
    ///   - orientedEdges: Each edge with its ends in the order the ranks run.
    ///   - maximumVertexCount: The most vertices, nodes and passing points together; past it, nil.
    init?(nodeSizes: [LayeredSize], nodeRanks: [Int], orientedEdges: [(upper: Int, lower: Int, labelSize: LayeredSize?)], maximumVertexCount: Int) {
        let passingPointCount = orientedEdges.reduce(0) { count, edge in count + max(0, nodeRanks[edge.lower] - nodeRanks[edge.upper] - 1) }
        guard nodeSizes.count + passingPointCount <= maximumVertexCount else { return nil }
        nodeCount = nodeSizes.count
        rank = nodeRanks
        size = nodeSizes
        upperNeighbors = Array(repeating: [], count: nodeCount)
        lowerNeighbors = Array(repeating: [], count: nodeCount)
        chains = []
        labelVertices = []
        layers = []
        rank.reserveCapacity(nodeCount + passingPointCount)
        size.reserveCapacity(nodeCount + passingPointCount)
        for edge in orientedEdges { addChain(from: edge.upper, to: edge.lower, labelSize: edge.labelSize) }
        layers = Array(repeating: [], count: (rank.max() ?? 0) + 1)
    }

    private mutating func addChain(from upper: Int, to lower: Int, labelSize: LayeredSize?) {
        var chain = [upper]
        let labelRank = labelSize == nil ? nil : (rank[upper] + rank[lower] + 1) / 2
        var labelVertex: Int?
        var previous = upper
        for passingRank in stride(from: rank[upper] + 1, to: rank[lower], by: 1) {
            let vertex = rank.count
            rank.append(passingRank)
            size.append(passingRank == labelRank ? labelSize ?? LayeredSize(across: 0, along: 0) : LayeredSize(across: 0, along: 0))
            upperNeighbors.append([])
            lowerNeighbors.append([])
            if passingRank == labelRank { labelVertex = vertex }
            link(previous, vertex)
            chain.append(vertex)
            previous = vertex
        }
        link(previous, lower)
        chain.append(lower)
        chains.append(chain)
        labelVertices.append(labelVertex)
    }

    private mutating func link(_ upper: Int, _ lower: Int) {
        lowerNeighbors[upper].append(lower)
        upperNeighbors[lower].append(upper)
    }
}

/// The offsets across, from the centers, at the two ends of a link between neighbouring ranks, seen from one of them:
/// where an edge held at a point of a box's side (`LayeredEdge.sourceOffset`) meets it.
struct LayeredLinkOffsets: Equatable {
    var atNeighbor: CGFloat
    var atVertex: CGFloat

    static let none = LayeredLinkOffsets(atNeighbor: 0, atVertex: 0)
}

/// The offsets across, from the centers, at the upper and lower ends of an edge.
struct LayeredChainEndOffsets: Equatable {
    var upper: CGFloat
    var lower: CGFloat
}

extension LayeredVertexGraph {
    /// Records the offsets of edges held off their ends' centers, one per edge in the order the edges were added: the
    /// first link of a chain carries its upper end's, the last its lower end's. Nothing is recorded when all are 0.
    mutating func holdEnds(at endOffsets: [LayeredChainEndOffsets]) {
        guard endOffsets.contains(where: { offsets in offsets.upper != 0 || offsets.lower != 0 }) else { return }
        chainEndOffsets = endOffsets
        upperLinkOffsets = upperNeighbors.map { neighbors in Array(repeating: .none, count: neighbors.count) }
        lowerLinkOffsets = lowerNeighbors.map { neighbors in Array(repeating: .none, count: neighbors.count) }
        for (chain, offsets) in zip(chains, endOffsets) {
            let upper = chain[0]
            let lower = chain[chain.count - 1]
            addLinkOffset(from: upper, to: chain[1], atUpper: offsets.upper, atLower: chain.count == 2 ? offsets.lower : 0)
            if chain.count > 2 { addLinkOffset(from: chain[chain.count - 2], to: lower, atUpper: 0, atLower: offsets.lower) }
        }
    }

    private mutating func addLinkOffset(from upper: Int, to lower: Int, atUpper: CGFloat, atLower: CGFloat) {
        guard atUpper != 0 || atLower != 0 else { return }
        // A vertex's link to a neighbour is the first entry of that neighbour not yet given an offset; two edges between
        // the same pair of vertices are told apart this way.
        if let index = lowerNeighbors[upper].indices.first(where: { index in
            lowerNeighbors[upper][index] == lower && lowerLinkOffsets[upper][index] == .none
        }) { lowerLinkOffsets[upper][index] = LayeredLinkOffsets(atNeighbor: atLower, atVertex: atUpper) }
        if let index = upperNeighbors[lower].indices.first(where: { index in
            upperNeighbors[lower][index] == upper && upperLinkOffsets[lower][index] == .none
        }) { upperLinkOffsets[lower][index] = LayeredLinkOffsets(atNeighbor: atUpper, atVertex: atLower) }
    }
}
