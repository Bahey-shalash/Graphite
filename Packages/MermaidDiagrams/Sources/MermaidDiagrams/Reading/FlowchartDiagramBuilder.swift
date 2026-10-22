/// Collects a flowchart as its statements are read: nodes by identifier, edges within the limits, and the groups open
/// at each point, which take the nodes written inside them.
struct FlowchartDiagramBuilder {
    private(set) var diagram = FlowchartDiagram()
    private let limits: MermaidDiagramLimits
    private var nodeIndexByIdentifier: [String: Int] = [:]
    /// Identifiers given to edges (`e1@-->`), whose `e1@{ … }` sets an edge's attributes rather than a node's.
    private var edgeIdentifiers: Set<String> = []
    /// Indexes into `diagram.subgraphs` of the groups open now, outermost first.
    private var openSubgraphIndices: [Int] = []

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
        if let innermost = openSubgraphIndices.last, !diagram.subgraphs[innermost].nodeIndices.contains(index) {
            diagram.subgraphs[innermost].nodeIndices.append(index)
        }
        return index
    }

    /// A later definition of a node replaces what an earlier one set, as in Mermaid.
    mutating func define(nodeAt index: Int, as definition: FlowchartNodeDefinition) {
        if let shape = definition.shape { diagram.nodes[index].shape = shape }
        if let label = definition.label { diagram.nodes[index].label = label }
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

    mutating func openSubgraph(identifier: String, title: DiagramLabel) {
        diagram.subgraphs.append(FlowchartSubgraph(identifier: identifier, title: title))
        openSubgraphIndices.append(diagram.subgraphs.count - 1)
    }

    /// Closes the innermost group; false when none is open.
    mutating func closeSubgraph() -> Bool {
        openSubgraphIndices.popLast() != nil
    }

    /// The identifier of the innermost group still open, or nil.
    var innermostOpenSubgraphIdentifier: String? {
        openSubgraphIndices.last.map { index in diagram.subgraphs[index].identifier }
    }

    var subgraphCount: Int { diagram.subgraphs.count }

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
