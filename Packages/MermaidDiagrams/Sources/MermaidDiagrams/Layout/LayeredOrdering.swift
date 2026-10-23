import CoreGraphics

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
    /// first rank in their written order, so that what is written together stays together; a node pinned first or
    /// last in its rank (`LayeredNodePlacement`) is moved there.
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
        guard !graph.nodePlacements.isEmpty else { return layers }
        return layers.map { layer in
            layer.filter { vertex in graph.placement(of: vertex) == .firstInRank }
                + layer.filter { vertex in graph.placement(of: vertex) != .firstInRank && graph.placement(of: vertex) != .lastInRank }
                + layer.filter { vertex in graph.placement(of: vertex) == .lastInRank }
        }
    }

    /// One sweep: each rank after the first (downward) or before the last (upward) sorted by the mean position of
    /// its vertices' neighbours in the rank already placed. A vertex with no such neighbour keeps its position, and a
    /// pinned node stays first or last.
    private static func sortByNeighborMeans(_ graph: inout LayeredVertexGraph, downward: Bool) {
        var position = positions(graph)
        let ranks = downward ? Array(graph.layers.indices.dropFirst()) : Array(graph.layers.indices.dropLast().reversed())
        for rank in ranks {
            let keyed = graph.layers[rank].map { vertex in
                let neighbors = downward ? graph.upperNeighbors[vertex] : graph.lowerNeighbors[vertex]
                var key = neighbors.isEmpty ? Double(position[vertex])
                    : Double(neighbors.reduce(0) { sum, neighbor in sum + position[neighbor] }) / Double(neighbors.count)
                if !graph.nodePlacements.isEmpty || graph.hasLinkOffsets { key = constrainedKey(key, of: vertex, in: graph, downward: downward) }
                return (vertex: vertex, key: key, current: position[vertex])
            }
            graph.layers[rank] = keyed.sorted { first, second in (first.key, first.current) < (second.key, second.current) }.map(\.vertex)
            for (index, vertex) in graph.layers[rank].enumerated() { position[vertex] = index }
        }
    }

    /// A vertex's sort key where some nodes are placed: a pinned node sorts before or after every other, and a neighbour
    /// held off its center (`LayeredEdge.sourceOffset`) counts where its edge leaves it, as a fraction of its width.
    private static func constrainedKey(_ key: Double, of vertex: Int, in graph: LayeredVertexGraph, downward: Bool) -> Double {
        switch graph.placement(of: vertex) {
        case .firstInRank: return -Double.greatestFiniteMagnitude
        case .lastInRank: return Double.greatestFiniteMagnitude
        case .free, .startBorder, .endBorder: break
        }
        let neighbors = downward ? graph.upperNeighbors[vertex] : graph.lowerNeighbors[vertex]
        guard graph.hasLinkOffsets, !neighbors.isEmpty else { return key }
        let offsets = downward ? graph.upperLinkOffsets[vertex] : graph.lowerLinkOffsets[vertex]
        let shift = zip(neighbors, offsets).reduce(0.0) { sum, link in
            sum + Double(link.1.atNeighbor / max(graph.size[link.0].across, 1))
        }
        return key + shift / Double(neighbors.count)
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
    /// upper end, then the pairs whose lower ends come in the other order, counted with a binary indexed tree. Where
    /// edges are held off their ends' centers, an end counts where it is held, as a fraction of its vertex's width.
    static func crossingCount(_ graph: LayeredVertexGraph) -> Int {
        guard !graph.hasLinkOffsets else { return heldCrossingCount(graph) }
        let position = positions(graph)
        var total = 0
        for rank in graph.layers.indices.dropLast() {
            var lowerEnds: [Int] = []
            for upper in graph.layers[rank] {
                lowerEnds.append(contentsOf: graph.lowerNeighbors[upper].map { lower in position[lower] }.sorted())
            }
            total += inversionCount(lowerEnds, valueCount: graph.layers[rank + 1].count)
        }
        return total
    }

    /// `crossingCount` where some edges are held off their ends' centers.
    private static func heldCrossingCount(_ graph: LayeredVertexGraph) -> Int {
        let position = positions(graph)
        func place(of vertex: Int, offset: CGFloat) -> Double {
            Double(position[vertex]) + Double(offset / max(graph.size[vertex].across, 1))
        }
        var total = 0
        for rank in graph.layers.indices.dropLast() {
            var links: [(upper: Double, lower: Double)] = []
            for upper in graph.layers[rank] {
                for (index, lower) in graph.lowerNeighbors[upper].enumerated() {
                    let offsets = graph.lowerLinkOffsets[upper][index]
                    links.append((place(of: upper, offset: offsets.atVertex), place(of: lower, offset: offsets.atNeighbor)))
                }
            }
            links.sort { first, second in (first.upper, first.lower) < (second.upper, second.lower) }
            let distinctLowerPlaces = Array(Set(links.map(\.lower))).sorted()
            var rankOfPlace: [Double: Int] = [:]
            for (rank, place) in distinctLowerPlaces.enumerated() { rankOfPlace[place] = rank }
            total += inversionCount(links.map { link in rankOfPlace[link.lower] ?? 0 }, valueCount: distinctLowerPlaces.count)
        }
        return total
    }

    /// How many pairs of `values` (each in `0..<valueCount`) come in decreasing order, with a binary indexed tree.
    private static func inversionCount(_ values: [Int], valueCount: Int) -> Int {
        var tree = [Int](repeating: 0, count: valueCount + 1)
        var total = 0
        for (seen, value) in values.enumerated() {
            var index = value + 1
            var notGreater = 0
            while index > 0 {
                notGreater += tree[index]
                index -= index & -index
            }
            total += seen - notGreater
            index = value + 1
            while index <= valueCount {
                tree[index] += 1
                index += index & -index
            }
        }
        return total
    }
}
