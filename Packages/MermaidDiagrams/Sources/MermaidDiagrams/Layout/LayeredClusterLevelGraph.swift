import CoreGraphics

/// The layered graph of one level of a cluster layout, in its direction's flow space: its items as nodes (a box at its
/// size), its level edges held where they cross the borders of the boxes their ends are inside, and for each crossing
/// of its own border either a border point with its edge, on the side the flow starts from or ends at, or the inner
/// item pinned first or last in its rank, on another side.
struct LayeredClusterLevelGraph {
    let graph: LayeredGraph
    /// By crossing of the level, the index in `graph.edges` of its edge to a border point, or nil for a crossing
    /// straight across the flow.
    let borderEdgeIndices: [Int?]

    /// - Parameters:
    ///   - itemSize: An item's size on the page.
    ///   - heldOffset: How far across from an item's center an edge is held where it crosses the item's border
    ///     (item, edge index, whether the edge leaves the item, the level's direction).
    init(level: Int, hierarchy: LayeredClusterHierarchy, graph clusterGraph: LayeredClusterGraph, itemSize: (Int) -> CGSize,
         heldOffset: (Int, Int, Bool, LayeredDirection) -> CGFloat) throws(LayeredClusterLayoutError) {
        let direction = hierarchy.levelDirections[level]
        let items = hierarchy.levelItems[level]
        var localIndex: [Int: Int] = [:]
        for (index, item) in items.enumerated() { localIndex[item] = index }
        var nodeSizes = items.map { item in direction.flowSize(of: itemSize(item)) }
        var placements = [LayeredNodePlacement](repeating: .free, count: items.count)
        var edges = hierarchy.levelEdges[level].map { levelEdge in
            let edge = clusterGraph.edges[levelEdge.edgeIndex]
            return LayeredEdge(source: localIndex[levelEdge.sourceItem] ?? 0, target: localIndex[levelEdge.targetItem] ?? 0,
                               minimumRankSpan: edge.minimumRankSpan, labelSize: edge.labelSize.map(direction.flowSize(of:)),
                               sourceOffset: heldOffset(levelEdge.sourceItem, levelEdge.edgeIndex, true, direction),
                               targetOffset: heldOffset(levelEdge.targetItem, levelEdge.edgeIndex, false, direction))
        }
        var borderEdgeIndices: [Int?] = []
        for crossing in hierarchy.crossings[level] {
            let inner = localIndex[crossing.innerItem] ?? 0
            let offset = heldOffset(crossing.innerItem, crossing.edgeIndex, crossing.isLeaving, direction)
            guard crossing.side == direction.startSide || crossing.side == direction.endSide else {
                let pin: LayeredNodePlacement = crossing.side == .top || crossing.side == .left ? .firstInRank : .lastInRank
                guard placements[inner] == .free || placements[inner] == pin else { throw .crossFlowExitsShareARank }
                placements[inner] = pin
                borderEdgeIndices.append(nil)
                continue
            }
            let border = nodeSizes.count
            nodeSizes.append(LayeredSize(across: 0, along: 0))
            placements.append(crossing.side == direction.startSide ? .startBorder : .endBorder)
            borderEdgeIndices.append(edges.count)
            edges.append(crossing.isLeaving ? LayeredEdge(source: inner, target: border, minimumRankSpan: 1, labelSize: nil, sourceOffset: offset)
                                            : LayeredEdge(source: border, target: inner, minimumRankSpan: 1, labelSize: nil, targetOffset: offset))
        }
        let isConstrained = placements.contains { placement in placement != .free }
        graph = LayeredGraph(nodeSizes: nodeSizes, edges: edges, nodePlacements: isConstrained ? placements : [])
        self.borderEdgeIndices = borderEdgeIndices
    }

    /// Fails when two items pinned to one side share a rank: the edge leaving the second straight across the flow
    /// would run through the first.
    func checkCrossFlowExits(in placement: LayeredPlacement) throws(LayeredClusterLayoutError) {
        var rankCentersBySide: [LayeredNodePlacement: Set<CGFloat>] = [:]
        for (node, nodePlacement) in graph.nodePlacements.enumerated() where nodePlacement == .firstInRank || nodePlacement == .lastInRank {
            guard rankCentersBySide[nodePlacement, default: []].insert(placement.nodeCenters[node].y).inserted else {
                throw .crossFlowExitsShareARank
            }
        }
    }
}
