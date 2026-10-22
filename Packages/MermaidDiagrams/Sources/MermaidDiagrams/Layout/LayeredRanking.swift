/// The first two steps of a layered layout: turning around the edges that close cycles, then giving each node a rank
/// so that every edge runs from a lower rank to a higher one, at least its minimum span apart.
enum LayeredRanking {
    /// The edges to turn around: those a depth-first walk finds closing a cycle. The walk starts from nodes no edge
    /// enters, in their order, so that in `A --> B --> A` the edge written last is the one turned.
    static func cycleClosingEdges(nodeCount: Int, edges: [LayeredEdge]) -> [Bool] {
        var outgoingEdgeIndices = [[Int]](repeating: [], count: nodeCount)
        var hasIncomingEdge = [Bool](repeating: false, count: nodeCount)
        for (edgeIndex, edge) in edges.enumerated() {
            outgoingEdgeIndices[edge.source].append(edgeIndex)
            hasIncomingEdge[edge.target] = true
        }
        let startOrder = (0..<nodeCount).filter { node in !hasIncomingEdge[node] } + (0..<nodeCount).filter { node in hasIncomingEdge[node] }
        var isReversed = [Bool](repeating: false, count: edges.count)
        var visitState = [VisitState](repeating: .unvisited, count: nodeCount)
        // An explicit stack, so that a long chain cannot exhaust the thread's stack.
        var stack: [(node: Int, nextOutgoingPosition: Int)] = []
        for start in startOrder where visitState[start] == .unvisited {
            visitState[start] = .onPath
            stack.append((start, 0))
            while let top = stack.last {
                let outgoing = outgoingEdgeIndices[top.node]
                guard top.nextOutgoingPosition < outgoing.count else {
                    visitState[top.node] = .finished
                    stack.removeLast()
                    continue
                }
                stack[stack.count - 1].nextOutgoingPosition += 1
                let edgeIndex = outgoing[top.nextOutgoingPosition]
                let target = edges[edgeIndex].target
                switch visitState[target] {
                case .onPath: isReversed[edgeIndex] = true
                case .unvisited:
                    visitState[target] = .onPath
                    stack.append((target, 0))
                case .finished: break
                }
            }
        }
        return isReversed
    }

    private enum VisitState {
        case unvisited, onPath, finished
    }

    /// Ranks for an acyclic graph, given as oriented `(source, target, span)` triples: each node as low as its
    /// longest path from a node no edge enters, then each node no edge enters moved down next to its nearest
    /// successor, so that a side branch does not start far above where it joins. The smallest rank is 0.
    static func ranks(nodeCount: Int, orientedEdges: [(source: Int, target: Int, span: Int)]) -> [Int] {
        var incomingCount = [Int](repeating: 0, count: nodeCount)
        var outgoing = [[(target: Int, span: Int)]](repeating: [], count: nodeCount)
        for edge in orientedEdges {
            incomingCount[edge.target] += 1
            outgoing[edge.source].append((edge.target, edge.span))
        }
        let isSource = incomingCount.map { count in count == 0 }
        var topologicalOrder = (0..<nodeCount).filter { node in incomingCount[node] == 0 }
        var rank = [Int](repeating: 0, count: nodeCount)
        var position = 0
        while position < topologicalOrder.count {
            let node = topologicalOrder[position]
            position += 1
            for (target, span) in outgoing[node] {
                rank[target] = max(rank[target], rank[node] + span)
                incomingCount[target] -= 1
                if incomingCount[target] == 0 { topologicalOrder.append(target) }
            }
        }
        for node in topologicalOrder.reversed() where isSource[node] && !outgoing[node].isEmpty {
            rank[node] = outgoing[node].map { successor in rank[successor.target] - successor.span }.min() ?? rank[node]
        }
        let lowest = rank.min() ?? 0
        return rank.map { nodeRank in nodeRank - lowest }
    }
}
