import CoreGraphics

/// The last step of a layered layout: where each vertex goes. Along the flow, each rank is as deep as its deepest
/// vertex and ranks are a fixed gap apart. Across, each rank in turn is placed as close as its order and gaps allow
/// to where its vertices' neighbours in the rank before are (the mean of their positions), alternately downward and
/// upward; the closest placement is a weighted isotonic regression, solved exactly by pooling adjacent violators.
enum LayeredPositioning {
    /// Rounds of one downward and one upward pass; a few settle a diagram in a note.
    static let passRoundCount = 4
    /// How strongly a passing point keeps to its neighbours compared with a node, so that long edges run straight.
    static let passingPointWeight: CGFloat = 4
    /// How weakly a vertex with no neighbour in the rank followed keeps its place.
    static let unconnectedWeight: CGFloat = 0.01
    /// A pass that moves no vertex farther than this, in points, changes nothing visible; two in a row end the passes.
    static let settledMovement: CGFloat = 0.25

    /// Each rank's center along the flow.
    static func rankCenters(_ graph: LayeredVertexGraph, rankGap: CGFloat) -> [CGFloat] {
        var centers: [CGFloat] = []
        var previousHalfDepth: CGFloat = 0
        var previousCenter: CGFloat = 0
        for (rank, layer) in graph.layers.enumerated() {
            let halfDepth = (layer.map { vertex in graph.size[vertex].along }.max() ?? 0) / 2
            let center = rank == 0 ? halfDepth : previousCenter + previousHalfDepth + rankGap + halfDepth
            centers.append(center)
            previousCenter = center
            previousHalfDepth = halfDepth
        }
        return centers
    }

    /// Each vertex's center across the flow, the smallest left edge at 0. The passes stop early once two in a row
    /// have moved no vertex visibly.
    static func acrossCenters(_ graph: LayeredVertexGraph, spacing: LayeredSpacing) -> [CGFloat] {
        // A rank's gaps depend on its order and sizes only, which the passes do not change.
        let gapsByRank = graph.layers.map { layer in minimumGaps(layer, graph: graph, spacing: spacing) }
        var center = [CGFloat](repeating: 0, count: graph.vertexCount)
        for (rank, layer) in graph.layers.enumerated() {
            var position: CGFloat = 0
            for (index, vertex) in layer.enumerated() {
                if index > 0 { position += gapsByRank[rank][index - 1] }
                center[vertex] = position
            }
        }
        var pooling = IsotonicPooling(capacity: graph.layers.map(\.count).max() ?? 0)
        var settledPassCount = 0
        let lastRank = graph.layers.count - 1
        for pass in 0..<(passRoundCount * 2 + 1) where settledPassCount < 2 {
            let isDownward = pass.isMultiple(of: 2)
            let ranks = isDownward ? stride(from: 1, through: lastRank, by: 1) : stride(from: lastRank - 1, through: 0, by: -1)
            var largestMovement: CGFloat = 0
            for rank in ranks {
                let movement = place(graph.layers[rank], following: isDownward ? graph.upperNeighbors : graph.lowerNeighbors, gaps: gapsByRank[rank],
                                     graph: graph, pooling: &pooling, centers: &center)
                largestMovement = max(largestMovement, movement)
            }
            settledPassCount = largestMovement < settledMovement ? settledPassCount + 1 : 0
        }
        straightenChains(graph, spacing: spacing, centers: &center)
        var leftmost = CGFloat.greatestFiniteMagnitude
        for layer in graph.layers {
            for vertex in layer { leftmost = min(leftmost, center[vertex] - graph.size[vertex].across / 2) }
        }
        if leftmost == .greatestFiniteMagnitude { leftmost = 0 }
        return center.map { position in position - leftmost }
    }

    /// Lines up the passing points of each edge that has two or more at one position across, where every rank they
    /// pass through has room there, so that a long edge runs straight instead of swaying from point to point. The
    /// position tried first is under the edge's source, then over its target, then the points' mean.
    private static func straightenChains(_ graph: LayeredVertexGraph, spacing: LayeredSpacing, centers: inout [CGFloat]) {
        var positionInLayer = [Int](repeating: 0, count: graph.vertexCount)
        for layer in graph.layers {
            for (index, vertex) in layer.enumerated() { positionInLayer[vertex] = index }
        }
        for chain in graph.chains where chain.count > 3 {
            let passingPoints = chain.dropFirst().dropLast()
            let mean = passingPoints.reduce(0) { sum, vertex in sum + centers[vertex] } / CGFloat(passingPoints.count)
            let candidates = [centers[chain[0]], centers[chain[chain.count - 1]], mean]
            guard let straight = candidates.first(where: { candidate in
                passingPoints.allSatisfy { vertex in
                    fits(vertex, at: candidate, graph: graph, spacing: spacing, centers: centers, positionInLayer: positionInLayer)
                }
            }) else { continue }
            for vertex in passingPoints { centers[vertex] = straight }
        }
    }

    /// Whether `vertex` keeps its gaps to its neighbours in its rank when its center moves to `position`.
    private static func fits(_ vertex: Int, at position: CGFloat, graph: LayeredVertexGraph, spacing: LayeredSpacing, centers: [CGFloat],
                             positionInLayer: [Int]) -> Bool {
        let layer = graph.layers[graph.rank[vertex]]
        let index = positionInLayer[vertex]
        if index > 0 {
            let left = layer[index - 1]
            if position - centers[left] < minimumGap(between: left, and: vertex, graph: graph, spacing: spacing) { return false }
        }
        if index + 1 < layer.count {
            let right = layer[index + 1]
            if centers[right] - position < minimumGap(between: vertex, and: right, graph: graph, spacing: spacing) { return false }
        }
        return true
    }

    /// The least distance between the centers of each pair of neighbours in a rank.
    private static func minimumGaps(_ layer: [Int], graph: LayeredVertexGraph, spacing: LayeredSpacing) -> [CGFloat] {
        zip(layer, layer.dropFirst()).map { left, right in minimumGap(between: left, and: right, graph: graph, spacing: spacing) }
    }

    private static func minimumGap(between left: Int, and right: Int, graph: LayeredVertexGraph, spacing: LayeredSpacing) -> CGFloat {
        let separation = graph.isPassingPoint(left) || graph.isPassingPoint(right) ? spacing.edgeSeparation : spacing.nodeSeparation
        return graph.size[left].across / 2 + separation + graph.size[right].across / 2
    }

    /// Places one rank: each vertex wants the mean position of its neighbours (or stays, with little weight, when it
    /// has none), and the rank takes the positions closest to those wishes that keep its order and gaps. Returns how
    /// far the vertex that moved most moved.
    private static func place(_ layer: [Int], following neighbors: [[Int]], gaps: [CGFloat], graph: LayeredVertexGraph,
                              pooling: inout IsotonicPooling, centers: inout [CGFloat]) -> CGFloat {
        guard !layer.isEmpty else { return 0 }
        pooling.reset()
        var offset: CGFloat = 0
        for (index, vertex) in layer.enumerated() {
            if index > 0 { offset += gaps[index - 1] }
            let vertexNeighbors = neighbors[vertex]
            guard !vertexNeighbors.isEmpty else {
                pooling.add(target: centers[vertex] - offset, weight: unconnectedWeight)
                continue
            }
            var sum: CGFloat = 0
            for neighbor in vertexNeighbors { sum += centers[neighbor] }
            let weight = graph.isPassingPoint(vertex) ? passingPointWeight : CGFloat(vertexNeighbors.count)
            pooling.add(target: sum / CGFloat(vertexNeighbors.count) - offset, weight: weight)
        }
        pooling.finish()
        var largestMovement: CGFloat = 0
        offset = 0
        for (index, vertex) in layer.enumerated() {
            if index > 0 { offset += gaps[index - 1] }
            let placed = pooling.fitted[index] + offset
            largestMovement = max(largestMovement, abs(placed - centers[vertex]))
            centers[vertex] = placed
        }
        return largestMovement
    }

    /// The nondecreasing sequence closest to `targets` in weighted least squares.
    static func nondecreasingFit(_ targets: [CGFloat], weights: [CGFloat]) -> [CGFloat] {
        var pooling = IsotonicPooling(capacity: targets.count)
        for (target, weight) in zip(targets, weights) { pooling.add(target: target, weight: weight) }
        pooling.finish()
        return pooling.fitted
    }
}
