/// Builds a Sankey diagram row by row as Mermaid's database does: a node is made the first time a row names it.
/// Nodes are bounded by `MermaidDiagramLimits.maximumNodeCount` and links by `maximumEdgeCount`.
struct SankeyDiagramBuilder {
    private(set) var diagram = SankeyDiagram()
    private var nodeIndices: [String: Int] = [:]
    private let limits: MermaidDiagramLimits

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    mutating func addLink(from source: String, to target: String, value: Double?) throws(MermaidDiagramReadError) {
        guard diagram.links.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        let sourceIndex = try nodeIndex(source)
        let targetIndex = try nodeIndex(target)
        diagram.links.append(SankeyLink(sourceIndex: sourceIndex, targetIndex: targetIndex, value: value))
    }

    private mutating func nodeIndex(_ name: String) throws(MermaidDiagramReadError) -> Int {
        if let index = nodeIndices[name] { return index }
        guard diagram.nodes.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        nodeIndices[name] = diagram.nodes.count
        diagram.nodes.append(SankeyNode(name: name))
        return diagram.nodes.count - 1
    }
}
