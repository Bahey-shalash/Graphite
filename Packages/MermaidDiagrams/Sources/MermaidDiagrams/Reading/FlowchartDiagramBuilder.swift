/// Collects a flowchart as its statements are read: nodes by identifier, edges within the limits, and the groups open
/// at each point, which take the names written inside them. A group's members are settled when it ends, and the
/// groups' nesting once the whole text is read (`finishedDiagram()`).
struct FlowchartDiagramBuilder {
    private var diagram = FlowchartDiagram()
    private let limits: MermaidDiagramLimits
    private var nodeIndexByIdentifier: [String: Int] = [:]
    /// Identifiers given to edges (`e1@-->`), whose `e1@{ … }` sets an edge's attributes rather than a node's.
    private var edgeIdentifiers: Set<String> = []
    /// The groups open now, outermost first.
    private var openSubgraphs: [OpenSubgraph] = []
    /// The groups ended so far, in the order they ended; a group ended again under the same identifier is merged.
    private var endedSubgraphs: [EndedFlowchartSubgraph] = []
    private var endedSubgraphIndexByIdentifier: [String: Int] = [:]
    /// Names a group took as it ended: a node or group belongs to the first group that ends with it named inside.
    private var takenMemberNames: Set<String> = []
    /// How many groups have opened, and how many have ended (the number in an identifier Mermaid makes, `subGraph0`).
    private var openedSubgraphCount = 0
    private var endedSubgraphCount = 0
    /// Identifiers given `@{ view: collapsed }`.
    private var collapsedIdentifiers: Set<String> = []

    /// A group open at the reading position.
    private struct OpenSubgraph {
        /// The identifier written after `subgraph`, or nil when Mermaid makes one as the group ends.
        let writtenIdentifier: String?
        let title: DiagramLabel
        let openingOrder: Int
        var direction: FlowchartDirection?
        var memberNames: [String] = []
        var memberNameSet: Set<String> = []

        mutating func add(memberName: String) {
            guard memberNameSet.insert(memberName).inserted else { return }
            memberNames.append(memberName)
        }
    }

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    /// The index of the node named `identifier`, added with its identifier as its text the first time it is named.
    /// A node named inside a group joins the innermost one.
    mutating func nodeIndex(for identifier: String) throws(MermaidDiagramReadError) -> Int {
        let index: Int
        if let existing = nodeIndexByIdentifier[identifier] {
            index = existing
        } else {
            guard diagram.nodes.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
            index = diagram.nodes.count
            diagram.nodes.append(FlowchartNode(identifier: identifier, label: DiagramLabel(identifier)))
            nodeIndexByIdentifier[identifier] = index
        }
        if !openSubgraphs.isEmpty { openSubgraphs[openSubgraphs.count - 1].add(memberName: identifier) }
        return index
    }

    /// A later definition of a node replaces what an earlier one set, as in Mermaid.
    mutating func define(nodeAt index: Int, as definition: FlowchartNodeDefinition) {
        if let shape = definition.shape { diagram.nodes[index].shape = shape }
        if let label = definition.label { diagram.nodes[index].label = label }
        if definition.asksForCollapsedView { collapsedIdentifiers.insert(diagram.nodes[index].identifier) }
    }

    /// One edge from each source to each target, as `A & B --> C & D` asks.
    mutating func addEdges(from sourceIndices: [Int], to targetIndices: [Int], link: FlowchartLink) throws(MermaidDiagramReadError) {
        guard diagram.edges.count + sourceIndices.count * targetIndices.count <= limits.maximumEdgeCount else {
            throw .tooManyEdges(limit: limits.maximumEdgeCount)
        }
        for sourceIndex in sourceIndices {
            for targetIndex in targetIndices {
                diagram.edges.append(FlowchartEdge(sourceIndex: sourceIndex, targetIndex: targetIndex, stroke: link.stroke,
                                                   sourceArrowhead: link.sourceArrowhead, targetArrowhead: link.targetArrowhead,
                                                   minimumRankSpan: link.minimumRankSpan, label: link.label))
            }
        }
    }

    mutating func recordEdgeIdentifier(_ identifier: String) {
        edgeIdentifiers.insert(identifier)
    }

    func isEdgeIdentifier(_ identifier: String) -> Bool {
        edgeIdentifiers.contains(identifier)
    }

    /// Opens a group; `identifier` is nil when the text gives none, and Mermaid's is made as the group ends.
    mutating func openSubgraph(identifier: String?, title: DiagramLabel) {
        openSubgraphs.append(OpenSubgraph(writtenIdentifier: identifier, title: title, openingOrder: openedSubgraphCount))
        openedSubgraphCount += 1
    }

    /// Ends the innermost group: it takes the names written inside it that no group ended before it took, never its
    /// own, and its identifier joins the group around it. False when no group is open.
    mutating func closeSubgraph() -> Bool {
        guard let group = openSubgraphs.popLast() else { return false }
        let identifier = group.writtenIdentifier ?? "subGraph\(endedSubgraphCount)"
        endedSubgraphCount += 1
        let members = group.memberNames.filter { name in !takenMemberNames.contains(name) && name != identifier }
        takenMemberNames.formUnion(members)
        if let existing = endedSubgraphIndexByIdentifier[identifier] {
            endedSubgraphs[existing].memberNames.append(contentsOf: members)
        } else {
            endedSubgraphIndexByIdentifier[identifier] = endedSubgraphs.count
            endedSubgraphs.append(EndedFlowchartSubgraph(identifier: identifier, title: group.title, direction: group.direction,
                                                         openingOrder: group.openingOrder, memberNames: members))
        }
        if !openSubgraphs.isEmpty { openSubgraphs[openSubgraphs.count - 1].add(memberName: identifier) }
        return true
    }

    /// The identifier of the innermost group still open (as Mermaid would make it, when the text gives none), or nil.
    var innermostOpenSubgraphIdentifier: String? {
        openSubgraphs.last.map { group in group.writtenIdentifier ?? "subGraph\(endedSubgraphCount)" }
    }

    var hasOpenSubgraph: Bool { !openSubgraphs.isEmpty }

    /// `direction` inside the innermost open group.
    mutating func setInnermostSubgraphDirection(_ direction: FlowchartDirection) {
        guard !openSubgraphs.isEmpty else { return }
        openSubgraphs[openSubgraphs.count - 1].direction = direction
    }

    /// The flowchart read, its groups nested and ordered (`FlowchartSubgraphNesting`).
    func finishedDiagram() -> FlowchartDiagram {
        var finished = diagram
        finished.subgraphs = FlowchartSubgraphNesting.subgraphs(endedSubgraphs, nodeIndexByIdentifier: nodeIndexByIdentifier,
                                                                collapsedIdentifiers: collapsedIdentifiers)
        return finished
    }

    mutating func setDirection(_ direction: FlowchartDirection) {
        diagram.direction = direction
    }

    mutating func setAccessibilityTitle(_ title: String) {
        diagram.accessibilityTitle = title
    }

    mutating func setAccessibilityDescription(_ description: String) {
        diagram.accessibilityDescription = description
    }

    mutating func countUnappliedStatement() {
        diagram.unappliedStatementCount += 1
    }
}
