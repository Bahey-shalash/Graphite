/// Where each node and group of a flowchart sits among its groups, and which way each runs.
struct FlowchartClusterNesting {
    /// For each node, the group directly holding it, or nil.
    let nodeSubgraphs: [Int?]
    /// For each node, the group it stands for, or nil.
    let representedSubgraphs: [Int?]
    /// For each group, the group directly holding it, or nil.
    let subgraphParents: [Int?]
    let subgraphDepths: [Int]
    /// For each node, the direction of the box it is in: its group's, else the nearest group's around it that sets
    /// one, else the diagram's.
    let nodeDirections: [FlowchartDirection]

    init(diagram: FlowchartDiagram) {
        var nodeSubgraphs = [Int?](repeating: nil, count: diagram.nodes.count)
        var representedSubgraphs = [Int?](repeating: nil, count: diagram.nodes.count)
        var subgraphParents = [Int?](repeating: nil, count: diagram.subgraphs.count)
        for (index, subgraph) in diagram.subgraphs.enumerated() {
            for node in subgraph.nodeIndices { nodeSubgraphs[node] = index }
            for child in subgraph.childSubgraphIndices { subgraphParents[child] = index }
            if let node = subgraph.representingNodeIndex { representedSubgraphs[node] = index }
        }
        // `FlowchartDiagram.subgraphs` lists each group before the groups inside it.
        var depths = [Int](repeating: 0, count: diagram.subgraphs.count)
        var directions = [FlowchartDirection](repeating: diagram.direction, count: diagram.subgraphs.count)
        for (index, subgraph) in diagram.subgraphs.enumerated() {
            let parent = subgraphParents[index]
            depths[index] = parent.map { depths[$0] + 1 } ?? 0
            directions[index] = subgraph.direction ?? parent.map { directions[$0] } ?? diagram.direction
        }
        self.nodeSubgraphs = nodeSubgraphs
        self.representedSubgraphs = representedSubgraphs
        self.subgraphParents = subgraphParents
        subgraphDepths = depths
        nodeDirections = nodeSubgraphs.map { subgraph in subgraph.map { directions[$0] } ?? diagram.direction }
    }
}
