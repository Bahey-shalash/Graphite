/// The levels of a cluster graph and its edges split between them. Items are the nodes, then the clusters (item
/// `nodeCount + c` is cluster `c`); level 0 is the top and level `c + 1` the inside of cluster `c`'s box. An edge is laid
/// out as a level edge between the two items that hold its ends where they sit side by side, and as a crossing of
/// each box border it passes on the way down to either end.
struct LayeredClusterHierarchy {
    let nodeCount: Int
    /// The level each item sits in.
    let itemLevels: [Int]
    /// How many boxes each item sits in.
    let itemDepths: [Int]
    /// The items of each level, in the order they are declared: a node by its index, a cluster where its first node
    /// is, an empty cluster before them all.
    let levelItems: [[Int]]
    let levelDirections: [LayeredDirection]
    /// The levels, each after the level its box sits in.
    let topDownLevels: [Int]
    /// For each edge, the level its level edge is in.
    let edgeLevels: [Int]
    /// The level edges of each level.
    let levelEdges: [[LayeredClusterLevelEdge]]
    /// The crossings of each level's border; their sides are settled by `LayeredClusterCrossingSides`.
    var crossings: [[LayeredClusterCrossing]]
    /// For each level, the index into its crossings by `crossingKey`.
    let crossingIndices: [[Int: Int]]

    init(_ graph: LayeredClusterGraph) throws(LayeredClusterLayoutError) {
        nodeCount = graph.nodeSizes.count
        let clusterDepths = try Self.clusterDepths(graph.clusters)
        itemLevels = graph.nodeClusters.map { cluster in cluster.map { $0 + 1 } ?? 0 }
            + graph.clusters.map { cluster in cluster.parent.map { $0 + 1 } ?? 0 }
        itemDepths = graph.nodeClusters.map { cluster in cluster.map { clusterDepths[$0] + 1 } ?? 0 } + clusterDepths
        topDownLevels = [0] + graph.clusters.indices.sorted { first, second in
            (clusterDepths[first], first) < (clusterDepths[second], second)
        }.map { cluster in cluster + 1 }
        var directions = [LayeredDirection](repeating: graph.direction, count: graph.clusters.count + 1)
        for level in topDownLevels.dropFirst() {
            let cluster = graph.clusters[level - 1]
            directions[level] = cluster.direction ?? directions[cluster.parent.map { $0 + 1 } ?? 0]
        }
        levelDirections = directions
        levelItems = Self.declaredItems(itemLevels: itemLevels, nodeCount: nodeCount, clusterCount: graph.clusters.count,
                                        clustersDeepestFirst: topDownLevels.dropFirst().reversed().map { level in level - 1 })
        var split = EdgeSplit(nodeCount: nodeCount, itemLevels: itemLevels, itemDepths: itemDepths, levelCount: graph.clusters.count + 1)
        for (edgeIndex, edge) in graph.edges.enumerated() { try split.add(edge, at: edgeIndex) }
        edgeLevels = split.edgeLevels
        levelEdges = split.levelEdges
        crossings = split.crossings
        crossingIndices = split.crossingIndices
    }

    func isCluster(_ item: Int) -> Bool { item >= nodeCount }

    func item(of end: LayeredClusterEnd) -> Int {
        switch end {
        case .node(let node): node
        case .cluster(let cluster): nodeCount + cluster
        }
    }

    /// The level inside a cluster item's box.
    func boxLevel(ofClusterItem item: Int) -> Int { item - nodeCount + 1 }

    /// The cluster item whose box is `level`, for a level other than the top.
    func clusterItem(ofBoxLevel level: Int) -> Int { nodeCount + level - 1 }

    /// The key of an edge's crossing in a level's `crossingIndices`: an edge crosses a border once each way at most.
    static func crossingKey(edgeIndex: Int, isLeaving: Bool) -> Int { edgeIndex * 2 + (isLeaving ? 0 : 1) }

    func crossingIndex(level: Int, edgeIndex: Int, isLeaving: Bool) -> Int? {
        crossingIndices[level][Self.crossingKey(edgeIndex: edgeIndex, isLeaving: isLeaving)]
    }

    /// How many boxes each cluster sits in, or a failure when one sits inside itself through its parents.
    private static func clusterDepths(_ clusters: [LayeredCluster]) throws(LayeredClusterLayoutError) -> [Int] {
        var depths = [Int?](repeating: nil, count: clusters.count)
        for start in clusters.indices where depths[start] == nil {
            var chain: [Int] = []
            var current: Int? = start
            while let cluster = current, depths[cluster] == nil {
                guard chain.count < clusters.count else { throw .clusterInsideItself }
                chain.append(cluster)
                current = clusters[cluster].parent
            }
            var depth = current.flatMap { cluster in depths[cluster].map { $0 + 1 } } ?? 0
            for cluster in chain.reversed() {
                depths[cluster] = depth
                depth += 1
            }
        }
        return depths.map { depth in depth ?? 0 }
    }

    /// Each level's items in the order they are declared.
    private static func declaredItems(itemLevels: [Int], nodeCount: Int, clusterCount: Int, clustersDeepestFirst: [Int]) -> [[Int]] {
        var items = [[Int]](repeating: [], count: clusterCount + 1)
        for (item, level) in itemLevels.enumerated() { items[level].append(item) }
        // An empty cluster keeps its own index, which sorts before every node's.
        var key = (0..<nodeCount).map { node in clusterCount + node } + Array(0..<clusterCount)
        for cluster in clustersDeepestFirst {
            if let first = items[cluster + 1].map({ item in key[item] }).min() { key[nodeCount + cluster] = first }
        }
        return items.map { levelItems in levelItems.sorted { first, second in (key[first], first) < (key[second], second) } }
    }
}

/// An edge where its ends meet: between the two items of one level that hold them.
struct LayeredClusterLevelEdge: Equatable {
    let edgeIndex: Int
    let sourceItem: Int
    let targetItem: Int
}

/// Where an edge crosses the border of a box on its way to or from something inside it.
struct LayeredClusterCrossing: Equatable {
    let edgeIndex: Int
    /// The item of the box the edge passes through: its end itself, or the box inside this one that holds it.
    let innerItem: Int
    /// Whether the edge leaves the box, starting inside it, rather than enters it.
    let isLeaving: Bool
    /// The side of the box the edge crosses: the side facing where it goes, settled from the top level down.
    var side: DiagramSide = .top
}

/// Splits each edge of a cluster graph into its level edge and its crossings, as Pele's compound layout does: both
/// ends climb to the level where they sit side by side, and each box an end climbs out of is a crossing.
private struct EdgeSplit {
    let nodeCount: Int
    let itemLevels: [Int]
    let itemDepths: [Int]
    var edgeLevels: [Int] = []
    var levelEdges: [[LayeredClusterLevelEdge]]
    var crossings: [[LayeredClusterCrossing]]
    var crossingIndices: [[Int: Int]]

    init(nodeCount: Int, itemLevels: [Int], itemDepths: [Int], levelCount: Int) {
        self.nodeCount = nodeCount
        self.itemLevels = itemLevels
        self.itemDepths = itemDepths
        levelEdges = Array(repeating: [], count: levelCount)
        crossings = Array(repeating: [], count: levelCount)
        crossingIndices = Array(repeating: [:], count: levelCount)
    }

    mutating func add(_ edge: LayeredClusterEdge, at edgeIndex: Int) throws(LayeredClusterLayoutError) {
        var source = item(of: edge.source)
        var target = item(of: edge.target)
        var sourcePath: [Int] = []
        var targetPath: [Int] = []
        while itemDepths[source] > itemDepths[target] { climb(&source, path: &sourcePath) }
        while itemDepths[target] > itemDepths[source] { climb(&target, path: &targetPath) }
        guard source != target else { throw .edgeIntoItsOwnCluster }
        while itemLevels[source] != itemLevels[target] {
            climb(&source, path: &sourcePath)
            climb(&target, path: &targetPath)
        }
        let level = itemLevels[source]
        edgeLevels.append(level)
        levelEdges[level].append(LayeredClusterLevelEdge(edgeIndex: edgeIndex, sourceItem: source, targetItem: target))
        for inner in sourcePath { addCrossing(LayeredClusterCrossing(edgeIndex: edgeIndex, innerItem: inner, isLeaving: true)) }
        for inner in targetPath { addCrossing(LayeredClusterCrossing(edgeIndex: edgeIndex, innerItem: inner, isLeaving: false)) }
    }

    private func item(of end: LayeredClusterEnd) -> Int {
        switch end {
        case .node(let node): node
        case .cluster(let cluster): nodeCount + cluster
        }
    }

    /// Records `item` on the path and moves to the cluster item that holds it.
    private func climb(_ item: inout Int, path: inout [Int]) {
        path.append(item)
        item = nodeCount + itemLevels[item] - 1
    }

    private mutating func addCrossing(_ crossing: LayeredClusterCrossing) {
        let level = itemLevels[crossing.innerItem]
        crossingIndices[level][LayeredClusterHierarchy.crossingKey(edgeIndex: crossing.edgeIndex, isLeaving: crossing.isLeaving)] = crossings[level].count
        crossings[level].append(crossing)
    }
}
