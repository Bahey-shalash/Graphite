/// Builds a mindmap's tree from its nodes and their indentation, as Mermaid does: the first node is the root, and a
/// node's parent is the last node written before it with a smaller indentation, wherever that node is in the tree.
struct MindmapTreeBuilder {
    private(set) var diagram = MindmapDiagram()
    private let limits: MermaidDiagramLimits
    /// The root's indentation, which every other indentation is measured from.
    private var rootIndentation = 0
    /// The nodes that can still take children, by strictly increasing indentation: the last node written and its
    /// ancestors that are less indented than it.
    private var openNodes: [(index: Int, indentation: Int)] = []

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    /// Adds a node written `indentation` characters in, on `line`.
    mutating func addNode(_ definition: MindmapNodeDefinition, indentation writtenIndentation: Int, line: Int) throws(MermaidDiagramReadError) {
        guard diagram.nodes.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        let isRoot = diagram.nodes.isEmpty
        if isRoot { rootIndentation = writtenIndentation }
        let indentation = writtenIndentation - rootIndentation
        var openCount = openNodes.count
        while openCount > 0, openNodes[openCount - 1].indentation >= indentation { openCount -= 1 }
        let parentIndex = openCount > 0 ? openNodes[openCount - 1].index : nil
        if parentIndex == nil, !isRoot { throw .invalidSyntax(line: line, problem: .secondRoot(text: definition.label.spokenText)) }
        let index = diagram.nodes.count
        diagram.nodes.append(MindmapNode(identifier: definition.identifier, label: definition.label, shape: definition.shape,
                                         parentIndex: parentIndex, branchIndex: parentIndex.flatMap(branchIndex(underParent:))))
        if let parentIndex { diagram.nodes[parentIndex].childIndices.append(index) }
        openNodes.removeLast(openNodes.count - openCount)
        openNodes.append((index, indentation))
    }

    /// The branch of a new child of `parentIndex`: the next one when the parent is the root, else the parent's.
    private func branchIndex(underParent parentIndex: Int) -> Int? {
        let parent = diagram.nodes[parentIndex]
        return parent.parentIndex == nil ? parent.childIndices.count % MindmapNode.branchCount : parent.branchIndex
    }

    /// `::icon(…)` or `:::class`: read and not drawn.
    mutating func countUnappliedDecoration() {
        diagram.unappliedDecorationCount += 1
    }

    mutating func apply(_ statement: MermaidAccessibilityStatement) {
        switch statement {
        case .title(let title): diagram.accessibilityTitle = title
        case .description(let description): diagram.accessibilityDescription = description
        }
    }
}
