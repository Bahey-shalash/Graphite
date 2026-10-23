/// Settles which side of its box each crossing passes, from the top level down, as Pele does: in each level, an edge
/// between two items runs from the upper to the lower one once cycles are broken, so it leaves a box it starts inside
/// through the side the flow ends at when that box is the upper item, and through the side it starts from otherwise;
/// it enters its target's box the other way. An edge that crosses several nested borders crosses each on the same side.
enum LayeredClusterCrossingSides {
    static func settle(_ hierarchy: inout LayeredClusterHierarchy, graph: LayeredClusterGraph) {
        for level in hierarchy.topDownLevels {
            passSidesInward(from: level, hierarchy: &hierarchy, graph: graph)
            settleLevelEdges(of: level, hierarchy: &hierarchy, graph: graph)
        }
    }

    /// A crossing whose inner item is a box holding the edge's end crosses that box's border on the same side.
    private static func passSidesInward(from level: Int, hierarchy: inout LayeredClusterHierarchy, graph: LayeredClusterGraph) {
        for crossing in hierarchy.crossings[level] {
            guard let innerIndex = heldCrossingIndex(of: crossing.innerItem, edgeIndex: crossing.edgeIndex, isLeaving: crossing.isLeaving,
                                                     hierarchy: hierarchy, graph: graph) else { continue }
            hierarchy.crossings[hierarchy.boxLevel(ofClusterItem: crossing.innerItem)][innerIndex].side = crossing.side
        }
    }

    /// The crossings of the boxes the level's edges start or end inside, by the way each edge runs in the level.
    private static func settleLevelEdges(of level: Int, hierarchy: inout LayeredClusterHierarchy, graph: LayeredClusterGraph) {
        let levelEdges = hierarchy.levelEdges[level]
        guard !levelEdges.isEmpty else { return }
        let direction = hierarchy.levelDirections[level]
        let items = hierarchy.levelItems[level]
        var localIndex: [Int: Int] = [:]
        for (index, item) in items.enumerated() { localIndex[item] = index }
        // The same edges, in the same order, as the level's layout breaks cycles in (`LayeredRanking.reversedEdges`).
        let isReversed = LayeredRanking.cycleClosingEdges(nodeCount: items.count, edges: levelEdges.map { levelEdge in
            LayeredEdge(source: localIndex[levelEdge.sourceItem] ?? 0, target: localIndex[levelEdge.targetItem] ?? 0, minimumRankSpan: 1, labelSize: nil)
        })
        for (position, levelEdge) in levelEdges.enumerated() {
            let sourceIsUpper = !isReversed[position]
            setHeldSide(sourceIsUpper ? direction.endSide : direction.startSide, of: levelEdge.sourceItem, edgeIndex: levelEdge.edgeIndex,
                        isLeaving: true, hierarchy: &hierarchy, graph: graph)
            setHeldSide(sourceIsUpper ? direction.startSide : direction.endSide, of: levelEdge.targetItem, edgeIndex: levelEdge.edgeIndex,
                        isLeaving: false, hierarchy: &hierarchy, graph: graph)
        }
    }

    private static func setHeldSide(_ side: DiagramSide, of item: Int, edgeIndex: Int, isLeaving: Bool, hierarchy: inout LayeredClusterHierarchy,
                                    graph: LayeredClusterGraph) {
        guard let index = heldCrossingIndex(of: item, edgeIndex: edgeIndex, isLeaving: isLeaving, hierarchy: hierarchy, graph: graph) else { return }
        hierarchy.crossings[hierarchy.boxLevel(ofClusterItem: item)][index].side = side
    }

    /// The index, in the box's own level, of the crossing an edge makes of `item`'s border, when `item` is a box the
    /// edge's end sits inside rather than the end itself; nil otherwise.
    static func heldCrossingIndex(of item: Int, edgeIndex: Int, isLeaving: Bool, hierarchy: LayeredClusterHierarchy,
                                  graph: LayeredClusterGraph) -> Int? {
        guard hierarchy.isCluster(item) else { return nil }
        let edge = graph.edges[edgeIndex]
        guard hierarchy.item(of: isLeaving ? edge.source : edge.target) != item else { return nil }
        return hierarchy.crossingIndex(level: hierarchy.boxLevel(ofClusterItem: item), edgeIndex: edgeIndex, isLeaving: isLeaving)
    }
}
