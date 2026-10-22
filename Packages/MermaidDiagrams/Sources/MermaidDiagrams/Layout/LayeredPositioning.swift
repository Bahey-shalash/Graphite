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

    /// Each vertex's center across the flow, the smallest left edge at 0.
    static func acrossCenters(_ graph: LayeredVertexGraph, spacing: LayeredSpacing) -> [CGFloat] {
        var center = [CGFloat](repeating: 0, count: graph.vertexCount)
        for layer in graph.layers {
            let gaps = minimumGaps(layer, graph: graph, spacing: spacing)
            var position: CGFloat = 0
            for (index, vertex) in layer.enumerated() {
                if index > 0 { position += gaps[index - 1] }
                center[vertex] = position
            }
        }
        for round in 0..<(passRoundCount * 2 + 1) {
            let isDownward = round.isMultiple(of: 2)
            let ranks = isDownward ? Array(graph.layers.indices.dropFirst()) : Array(graph.layers.indices.dropLast().reversed())
            for rank in ranks {
                place(graph.layers[rank], following: isDownward ? graph.upperNeighbors : graph.lowerNeighbors, graph: graph,
                      spacing: spacing, centers: &center)
            }
        }
        straightenChains(graph, spacing: spacing, centers: &center)
        let leftmost = graph.layers.flatMap { layer in layer.map { vertex in center[vertex] - graph.size[vertex].across / 2 } }.min() ?? 0
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
            let gap = minimumGaps([left, vertex], graph: graph, spacing: spacing)[0]
            if position - centers[left] < gap { return false }
        }
        if index + 1 < layer.count {
            let right = layer[index + 1]
            let gap = minimumGaps([vertex, right], graph: graph, spacing: spacing)[0]
            if centers[right] - position < gap { return false }
        }
        return true
    }

    /// The least distance between the centers of each pair of neighbours in a rank.
    private static func minimumGaps(_ layer: [Int], graph: LayeredVertexGraph, spacing: LayeredSpacing) -> [CGFloat] {
        zip(layer, layer.dropFirst()).map { left, right in
            let separation = graph.isPassingPoint(left) || graph.isPassingPoint(right) ? spacing.edgeSeparation : spacing.nodeSeparation
            return graph.size[left].across / 2 + separation + graph.size[right].across / 2
        }
    }

    /// Places one rank: each vertex wants the mean position of its neighbours (or stays, with little weight, when it
    /// has none), and the rank takes the positions closest to those wishes that keep its order and gaps.
    private static func place(_ layer: [Int], following neighbors: [[Int]], graph: LayeredVertexGraph, spacing: LayeredSpacing,
                              centers: inout [CGFloat]) {
        guard !layer.isEmpty else { return }
        let gaps = minimumGaps(layer, graph: graph, spacing: spacing)
        var targets: [CGFloat] = []
        var weights: [CGFloat] = []
        var offset: CGFloat = 0
        for (index, vertex) in layer.enumerated() {
            if index > 0 { offset += gaps[index - 1] }
            let vertexNeighbors = neighbors[vertex]
            let wish = vertexNeighbors.isEmpty ? centers[vertex]
                : vertexNeighbors.reduce(0) { sum, neighbor in sum + centers[neighbor] } / CGFloat(vertexNeighbors.count)
            let weight = vertexNeighbors.isEmpty ? 0.01 : (graph.isPassingPoint(vertex) ? passingPointWeight : CGFloat(vertexNeighbors.count))
            targets.append(wish - offset)
            weights.append(weight)
        }
        let shifted = nondecreasingFit(targets, weights: weights)
        offset = 0
        for (index, vertex) in layer.enumerated() {
            if index > 0 { offset += gaps[index - 1] }
            centers[vertex] = shifted[index] + offset
        }
    }

    /// The nondecreasing sequence closest to `targets` in weighted least squares (pool adjacent violators).
    static func nondecreasingFit(_ targets: [CGFloat], weights: [CGFloat]) -> [CGFloat] {
        var blockMeans: [CGFloat] = []
        var blockWeights: [CGFloat] = []
        var blockCounts: [Int] = []
        for (target, weight) in zip(targets, weights) {
            var mean = target
            var totalWeight = weight
            var count = 1
            while let previousMean = blockMeans.last, previousMean > mean {
                let previousWeight = blockWeights.removeLast()
                mean = (previousMean * previousWeight + mean * totalWeight) / (previousWeight + totalWeight)
                totalWeight += previousWeight
                count += blockCounts.removeLast()
                blockMeans.removeLast()
            }
            blockMeans.append(mean)
            blockWeights.append(totalWeight)
            blockCounts.append(count)
        }
        return zip(blockMeans, blockCounts).flatMap { mean, count in Array(repeating: mean, count: count) }
    }
}
