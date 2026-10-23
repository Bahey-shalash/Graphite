/// A Mermaid mindmap (`mindmap`) as its text describes it: one tree, whose hierarchy comes from each line's
/// indentation, with its nodes in the order they are written. That order is depth first, so the root comes first
/// and every node comes before its children.
public struct MindmapDiagram: Equatable, Sendable {
    /// The nodes in the order they are written; the first is the root.
    public internal(set) var nodes: [MindmapNode]
    /// The diagram's title, from `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?
    /// Decorations read and not drawn: `::icon(…)`, which takes no room, as in Pele when the icon is not available,
    /// and `:::class`, which only a style sheet would apply.
    public internal(set) var unappliedDecorationCount: Int

    init(nodes: [MindmapNode] = [], title: String? = nil, accessibilityTitle: String? = nil, accessibilityDescription: String? = nil,
         unappliedDecorationCount: Int = 0) {
        self.nodes = nodes
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
        self.unappliedDecorationCount = unappliedDecorationCount
    }
}

/// A node of a mindmap: its text and shape, and where it sits in the tree.
public struct MindmapNode: Equatable, Sendable {
    /// The identifier written before the node's delimiters, or its text when it has none.
    public let identifier: String
    public let label: DiagramLabel
    public let shape: MindmapNodeShape
    /// The index of the node's parent in `MindmapDiagram.nodes`, or nil for the root.
    public let parentIndex: Int?
    /// The indexes of the node's children, in the order they are written.
    public internal(set) var childIndices: [Int]
    /// The first-level branch the node belongs to, which gives its color: that branch's place among the root's
    /// children, counted from 0 again after `MindmapNode.branchCount`, as Mermaid numbers its sections. Nil for the root.
    public let branchIndex: Int?

    /// How many branches Mermaid numbers before it starts again from the first.
    public static let branchCount = 11

    init(identifier: String, label: DiagramLabel, shape: MindmapNodeShape, parentIndex: Int?, branchIndex: Int?, childIndices: [Int] = []) {
        self.identifier = identifier
        self.label = label
        self.shape = shape
        self.parentIndex = parentIndex
        self.branchIndex = branchIndex
        self.childIndices = childIndices
    }
}

/// The shapes a mindmap node is written in, by the delimiters around its text.
public enum MindmapNodeShape: Equatable, Sendable, CaseIterable {
    /// No delimiters (`text`), or `(-text-)`: the root is drawn as a stadium, a node with children as a pill, and any
    /// other node as its text alone, as Pele draws them.
    case plain
    /// `[text]`.
    case rectangle
    /// `(text)`.
    case roundedRectangle
    /// `((text))`.
    case circle
    /// `)text(`.
    case cloud
    /// `))text((`.
    case bang
    /// `{{text}}`.
    case hexagon
}
