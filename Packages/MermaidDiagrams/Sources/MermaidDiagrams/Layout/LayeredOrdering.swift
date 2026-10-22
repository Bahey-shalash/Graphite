/// The third step of a layered layout: the order of the vertices in each rank, chosen to cross as few edges as
/// possible. A depth-first walk gives a first order; sweeps down and up then sort each rank by the mean position of
/// each vertex's neighbours in the rank before, and the order with the fewest crossings is kept.
enum LayeredOrdering {
    /// Sweeps tried after the first order, half down and half up. A diagram in a note has a few dozen nodes, for
    /// which the crossings rarely fall after a handful of sweeps.
    static let maximumSweepCount = 8

    static func order(_ graph: inout LayeredVertexGraph) {
        graph.layers = initialLayers(graph)
        var bestLayers = graph.layers
        var bestCrossings = crossingCount(graph)
        var sweep = 0
        while sweep < maximumSweepCount, bestCrossings > 0 {
            let isDownward = sweep.isMultiple(of: 2)
            sortByNeighborMeans(&graph, downward: isDownward)
            let crossings = crossingCount(graph)
            if crossings < bestCrossings {
                bestCrossings = crossings
                bestLayers = graph.layers
            }
            sweep += 1
        }
        graph.layers = bestLayers
    }

    /// Vertices in the order a depth-first walk down the edges first reaches them, starting from the nodes of the
    /// first rank in their written order, so that what is written together stays together.
    private static func initialLayers(_ graph: LayeredVertexGraph) -> [[Int]] {
        var layers = [[Int]](repeating: [], count: graph.layers.count)
        var isVisited = [Bool](repeating: false, count: graph.vertexCount)
        var stack: [Int] = []
        let starts = (0..<graph.nodeCount).sorted { first, second in (graph.rank[first], first) < (graph.rank[second], second) }
        for start in starts where !isVisited[start] {
            stack.append(start)
            while let vertex = stack.popLast() {
                guard !isVisited[vertex] else { continue }
                isVisited[vertex] = true
                layers[graph.rank[vertex]].append(vertex)
                for lower in graph.lowerNeighbors[vertex].reversed() where !isVisited[lower] { stack.append(lower) }
            }
        }
        return layers
    }

    /// One sweep: each rank after the first (downward) or before the last (upward) sorted by the mean position of
    /// its vertices' neighbours in the rank already placed. A vertex with no such neighbour keeps its position.
    private static func sortByNeighborMeans(_ graph: inout LayeredVertexGraph, downward: Bool) {
        var position = positions(graph)
        let ranks = downward ? Array(graph.layers.indices.dropFirst()) : Array(graph.layers.indices.dropLast().reversed())
        for rank in ranks {
            let keyed = graph.layers[rank].map { vertex in
                let neighbors = downward ? graph.upperNeighbors[vertex] : graph.lowerNeighbors[vertex]
                let key = neighbors.isEmpty ? Double(position[vertex])
                    : Double(neighbors.reduce(0) { sum, neighbor in sum + position[neighbor] }) / Double(neighbors.count)
                return (vertex: vertex, key: key, current: position[vertex])
            }
            graph.layers[rank] = keyed.sorted { first, second in (first.key, first.current) < (second.key, second.current) }.map(\.vertex)
            for (index, vertex) in graph.layers[rank].enumerated() { position[vertex] = index }
        }
    }

    /// Each vertex's position in its rank.
    private static func positions(_ graph: LayeredVertexGraph) -> [Int] {
        var position = [Int](repeating: 0, count: graph.vertexCount)
        for layer in graph.layers {
            for (index, vertex) in layer.enumerated() { position[vertex] = index }
        }
        return position
    }

    /// How many pairs of edges cross between neighbouring ranks: for each pair of ranks, the edges sorted by their
    /// upper end, then the pairs whose lower ends come in the other order, counted with a binary indexed tree.
    static func crossingCount(_ graph: LayeredVertexGraph) -> Int {
        let position = positions(graph)
        var total = 0
        for rank in graph.layers.indices.dropLast() {
            let lowerLayerSize = graph.layers[rank + 1].count
            var lowerEnds: [Int] = []
            for upper in graph.layers[rank] {
                lowerEnds.append(contentsOf: graph.lowerNeighbors[upper].map { lower in position[lower] }.sorted())
            }
            var tree = [Int](repeating: 0, count: lowerLayerSize + 1)
            for (seen, lowerEnd) in lowerEnds.enumerated() {
                var index = lowerEnd + 1
                var notGreater = 0
                while index > 0 {
                    notGreater += tree[index]
                    index -= index & -index
                }
                total += seen - notGreater
                index = lowerEnd + 1
                while index <= lowerLayerSize {
                    tree[index] += 1
                    index += index & -index
                }
            }
        }
        return total
    }
}
