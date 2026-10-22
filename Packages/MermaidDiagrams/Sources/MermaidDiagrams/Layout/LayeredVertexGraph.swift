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

    func isPassingPoint(_ vertex: Int) -> Bool { vertex >= nodeCount }
    var vertexCount: Int { rank.count }

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
