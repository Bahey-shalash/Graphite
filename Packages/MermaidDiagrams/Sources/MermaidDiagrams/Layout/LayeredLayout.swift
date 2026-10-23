import CoreGraphics

/// A layered layout of a directed graph, the Sugiyama method on plain values: cycles broken by turning edges around,
/// ranks, passing points for edges that span several ranks, an order across each rank with few crossings, and
/// positions. When any edge has text, every span is doubled so that the texts get ranks of their own between the
/// ranks of nodes, half a rank gap from each. A graph laid out as a box of a cluster layout may also have border
/// points, nodes pinned first or last in their rank, and edges held off their ends' centers (`LayeredGraph`).
enum LayeredLayout {
    /// Lays `graph` out, or returns nil when it would need more than `maximumPointCount` nodes and passing points.
    static func place(_ graph: LayeredGraph, spacing: LayeredSpacing, maximumPointCount: Int) -> LayeredPlacement? {
        let nodeCount = graph.nodeSizes.count
        let isReversed = graph.nodePlacements.isEmpty ? LayeredRanking.cycleClosingEdges(nodeCount: nodeCount, edges: graph.edges)
            : LayeredRanking.reversedEdges(nodeCount: nodeCount, edges: graph.edges, placements: graph.nodePlacements)
        let hasLabels = graph.edges.contains { edge in edge.labelSize != nil }
        let spanFactor = hasLabels ? 2 : 1
        let oriented = graph.edges.enumerated().map { edgeIndex, edge in
            isReversed[edgeIndex] ? (upper: edge.target, lower: edge.source, labelSize: edge.labelSize)
                                  : (upper: edge.source, lower: edge.target, labelSize: edge.labelSize)
        }
        let rankedEdges = zip(oriented, graph.edges).map { orientedEdge, edge in
            (orientedEdge.upper, orientedEdge.lower, max(1, edge.minimumRankSpan) * spanFactor)
        }
        let ranks = graph.nodePlacements.isEmpty ? LayeredRanking.ranks(nodeCount: nodeCount, orientedEdges: rankedEdges)
            : LayeredRanking.ranks(nodeCount: nodeCount, orientedEdges: rankedEdges, placements: graph.nodePlacements, span: spanFactor)
        guard var vertexGraph = LayeredVertexGraph(nodeSizes: graph.nodeSizes, nodeRanks: ranks, orientedEdges: oriented,
                                                   maximumVertexCount: maximumPointCount) else { return nil }
        vertexGraph.nodePlacements = graph.nodePlacements
        if graph.edges.contains(where: { edge in edge.sourceOffset != 0 || edge.targetOffset != 0 }) {
            vertexGraph.holdEnds(at: zip(graph.edges, isReversed).map { edge, reversed in
                reversed ? LayeredChainEndOffsets(upper: edge.targetOffset, lower: edge.sourceOffset)
                         : LayeredChainEndOffsets(upper: edge.sourceOffset, lower: edge.targetOffset)
            })
        }
        LayeredOrdering.order(&vertexGraph)
        let across = LayeredPositioning.acrossCenters(vertexGraph, spacing: spacing)
        let along = rankCenters(vertexGraph, spacing: spacing, spanFactor: spanFactor)
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

    /// The ranks' centers along the flow, the gaps next to border points `LayeredSpacing.borderSeparation`.
    private static func rankCenters(_ graph: LayeredVertexGraph, spacing: LayeredSpacing, spanFactor: Int) -> [CGFloat] {
        let rankGap = spacing.rankSeparation / CGFloat(spanFactor)
        guard !graph.nodePlacements.isEmpty else { return LayeredPositioning.rankCenters(graph, rankGap: rankGap) }
        let hasStartBorder = graph.nodePlacements.contains(.startBorder)
        let hasEndBorder = graph.nodePlacements.contains(.endBorder)
        return LayeredPositioning.rankCenters(graph, rankGap: rankGap, borderGap: (spacing.borderSeparation ?? spacing.rankSeparation) / CGFloat(spanFactor),
                                              startBorderRankCount: hasStartBorder ? spanFactor : 0, endBorderRankCount: hasEndBorder ? spanFactor : 0)
    }
}
