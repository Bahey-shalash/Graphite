import CoreGraphics

/// A layered layout of a directed graph, the Sugiyama method on plain values: cycles broken by turning edges around,
/// ranks, passing points for edges that span several ranks, an order across each rank with few crossings, and
/// positions. When any edge has text, every span is doubled so that the texts get ranks of their own between the
/// ranks of nodes, half a rank gap from each.
enum LayeredLayout {
    /// Lays `graph` out, or returns nil when it would need more than `maximumPointCount` nodes and passing points.
    static func place(_ graph: LayeredGraph, spacing: LayeredSpacing, maximumPointCount: Int) -> LayeredPlacement? {
        let isReversed = LayeredRanking.cycleClosingEdges(nodeCount: graph.nodeSizes.count, edges: graph.edges)
        let hasLabels = graph.edges.contains { edge in edge.labelSize != nil }
        let spanFactor = hasLabels ? 2 : 1
        let oriented = graph.edges.enumerated().map { edgeIndex, edge in
            isReversed[edgeIndex] ? (upper: edge.target, lower: edge.source, labelSize: edge.labelSize)
                                  : (upper: edge.source, lower: edge.target, labelSize: edge.labelSize)
        }
        let ranks = LayeredRanking.ranks(nodeCount: graph.nodeSizes.count, orientedEdges: zip(oriented, graph.edges).map { orientedEdge, edge in
            (orientedEdge.upper, orientedEdge.lower, max(1, edge.minimumRankSpan) * spanFactor)
        })
        guard var vertexGraph = LayeredVertexGraph(nodeSizes: graph.nodeSizes, nodeRanks: ranks, orientedEdges: oriented,
                                                   maximumVertexCount: maximumPointCount) else { return nil }
        LayeredOrdering.order(&vertexGraph)
        let across = LayeredPositioning.acrossCenters(vertexGraph, spacing: spacing)
        let along = LayeredPositioning.rankCenters(vertexGraph, rankGap: spacing.rankSeparation / CGFloat(spanFactor))
        func center(of vertex: Int) -> CGPoint { CGPoint(x: across[vertex], y: along[vertexGraph.rank[vertex]]) }
        let routes = vertexGraph.chains.enumerated().map { edgeIndex, chain in
            let points = chain.map(center(of:))
            return isReversed[edgeIndex] ? Array(points.reversed()) : points
        }
        let extentAcross = (0..<vertexGraph.vertexCount).map { vertex in across[vertex] + vertexGraph.size[vertex].across / 2 }.max() ?? 0
        let lastRank = vertexGraph.layers.count - 1
        let lastRankDepth = vertexGraph.layers[lastRank].map { vertex in vertexGraph.size[vertex].along }.max() ?? 0
        return LayeredPlacement(nodeCenters: (0..<vertexGraph.nodeCount).map(center(of:)), edgeRoutes: routes,
                                edgeLabelCenters: vertexGraph.labelVertices.map { vertex in vertex.map(center(of:)) },
                                extent: CGSize(width: extentAcross, height: (along.last ?? 0) + lastRankDepth / 2))
    }
}
