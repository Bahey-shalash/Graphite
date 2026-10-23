/// A `subgraph … end` group as it ends: what it is called, and the names written in its statements that no group
/// ended before it took.
struct EndedFlowchartSubgraph {
    let identifier: String
    let title: DiagramLabel
    let direction: FlowchartDirection?
    /// How many groups opened before this one: groups side by side keep the order they are written in.
    let openingOrder: Int
    /// The identifiers named in the group's own statements, nodes and groups alike, each once, in the order named.
    var memberNames: [String]
}

/// Turns the groups of a flowchart, in the order they ended, into its subgraphs: a member whose name is a group's
/// identifier is that group, inside this one; the others are nodes. A group in a loop of groups (each named inside
/// the next) is lifted to the top, the group that ended last first, as Pele does. Each group is listed before the
/// groups inside it.
enum FlowchartSubgraphNesting {
    static func subgraphs(_ ended: [EndedFlowchartSubgraph], nodeIndexByIdentifier: [String: Int],
                          collapsedIdentifiers: Set<String>) -> [FlowchartSubgraph] {
        var endedIndexByIdentifier: [String: Int] = [:]
        for (index, group) in ended.enumerated() { endedIndexByIdentifier[group.identifier] = index }
        var parents = [Int?](repeating: nil, count: ended.count)
        var children = [[Int]](repeating: [], count: ended.count)
        for (index, group) in ended.enumerated() {
            for name in group.memberNames {
                guard let child = endedIndexByIdentifier[name] else { continue }
                parents[child] = index
                children[index].append(child)
            }
        }
        liftGroupsInLoops(parents: &parents, children: &children)
        let order = preorder(ended, parents: parents, children: children)
        var position = [Int](repeating: 0, count: ended.count)
        for (place, endedIndex) in order.enumerated() { position[endedIndex] = place }
        return order.map { endedIndex in
            let group = ended[endedIndex]
            let nodeNames = group.memberNames.filter { name in endedIndexByIdentifier[name] == nil }
            return FlowchartSubgraph(identifier: group.identifier, title: group.title,
                                     nodeIndices: nodeNames.compactMap { name in nodeIndexByIdentifier[name] },
                                     childSubgraphIndices: children[endedIndex].map { child in position[child] }, direction: group.direction,
                                     representingNodeIndex: nodeIndexByIdentifier[group.identifier],
                                     isCollapsed: collapsedIdentifiers.contains(group.identifier))
        }
    }

    /// A group cannot be reached from the top when its parents loop; the last such group to end loses its parent,
    /// which places the rest of its loop inside it.
    private static func liftGroupsInLoops(parents: inout [Int?], children: inout [[Int]]) {
        var isReachable = [Bool](repeating: false, count: parents.count)
        func markReachable(from root: Int) {
            var stack = [root]
            while let group = stack.popLast() {
                guard !isReachable[group] else { continue }
                isReachable[group] = true
                stack.append(contentsOf: children[group])
            }
        }
        for group in parents.indices where parents[group] == nil { markReachable(from: group) }
        for group in parents.indices.reversed() where !isReachable[group] {
            if let former = parents[group] { children[former].removeAll { child in child == group } }
            parents[group] = nil
            markReachable(from: group)
        }
    }

    /// The groups depth first: the top-level groups in the order they opened, each followed by the groups inside it.
    private static func preorder(_ ended: [EndedFlowchartSubgraph], parents: [Int?], children: [[Int]]) -> [Int] {
        let roots = parents.indices.filter { group in parents[group] == nil }.sorted { first, second in
            ended[first].openingOrder < ended[second].openingOrder
        }
        var order: [Int] = []
        order.reserveCapacity(ended.count)
        var stack = Array(roots.reversed())
        while let group = stack.popLast() {
            order.append(group)
            stack.append(contentsOf: children[group].reversed())
        }
        return order
    }
}
