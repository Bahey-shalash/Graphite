/// A Mermaid flowchart (`flowchart` or `graph`) as its text describes it: the nodes in the order they first
/// appear, the edges between them in the order they are written, and the groups and statements read but not drawn.
public struct FlowchartDiagram: Equatable, Sendable {
    public internal(set) var direction: FlowchartDirection
    public internal(set) var nodes: [FlowchartNode]
    public internal(set) var edges: [FlowchartEdge]
    /// The `subgraph … end` groups, each before the groups inside it, groups side by side in the order they are written.
    public internal(set) var subgraphs: [FlowchartSubgraph]
    /// The diagram's title, from `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?
    /// Statements that change only how the diagram looks (`classDef`, `class`, `:::`, `style`, `linkStyle`) or
    /// what a click does (`click`). They are read and not applied yet.
    public internal(set) var unappliedStatementCount: Int

    init(direction: FlowchartDirection = .topToBottom, nodes: [FlowchartNode] = [], edges: [FlowchartEdge] = [],
         subgraphs: [FlowchartSubgraph] = [], title: String? = nil, accessibilityTitle: String? = nil,
         accessibilityDescription: String? = nil, unappliedStatementCount: Int = 0) {
        self.direction = direction
        self.nodes = nodes
        self.edges = edges
        self.subgraphs = subgraphs
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
        self.unappliedStatementCount = unappliedStatementCount
    }
}

/// The way a flowchart's ranks follow each other.
public enum FlowchartDirection: Equatable, Sendable, CaseIterable {
    /// `TB` or `TD`, the default.
    case topToBottom
    /// `BT`.
    case bottomToTop
    /// `LR`.
    case leftToRight
    /// `RL`.
    case rightToLeft

    /// The direction a Mermaid keyword names: `TB`, `TD`, `BT`, `LR`, `RL`, or the older arrows `v`, `^`, `>`, `<`.
    init?(keyword: String) {
        switch keyword.uppercased() {
        case "TB", "TD", "V": self = .topToBottom
        case "BT", "^": self = .bottomToTop
        case "LR", ">": self = .leftToRight
        case "RL", "<": self = .rightToLeft
        default: return nil
        }
    }

    /// Whether ranks follow each other across the page rather than down it.
    var runsAcross: Bool {
        switch self {
        case .leftToRight, .rightToLeft: true
        case .topToBottom, .bottomToTop: false
        }
    }
}

/// A `subgraph … end` group: its identifier, its title, what is directly inside it and the direction it runs in.
///
/// Membership follows Mermaid: a group holds the nodes and groups named in its own statements, and a node named in
/// several groups belongs to the first of them to end, so a node named in a group and again in the group around it
/// is in the inner one only. A group whose identifier is named inside another group (`A --> inner`) sits inside it.
public struct FlowchartSubgraph: Equatable, Sendable {
    /// The identifier written after `subgraph`, or `subGraph` and the number of groups that ended before this one.
    public let identifier: String
    public internal(set) var title: DiagramLabel
    /// Indexes into `FlowchartDiagram.nodes` of the nodes directly inside the group, in the order they are named in it.
    public internal(set) var nodeIndices: [Int]
    /// Indexes into `FlowchartDiagram.subgraphs` of the groups directly inside this one.
    public internal(set) var childSubgraphIndices: [Int]
    /// `direction TB`, `TD`, `BT`, `LR` or `RL` inside the group, or nil when it runs as the group around it does.
    public internal(set) var direction: FlowchartDirection?
    /// The node whose identifier is the group's, when the text names the group like a node (`A --> group`,
    /// `group@{ … }`): it stands for the group, so edges to it meet the group's box, and it is not drawn as a node.
    public internal(set) var representingNodeIndex: Int?
    /// Whether `@{ view: collapsed }` asks for the group drawn as one node in place of its content.
    public internal(set) var isCollapsed: Bool

    init(identifier: String, title: DiagramLabel, nodeIndices: [Int] = [], childSubgraphIndices: [Int] = [],
         direction: FlowchartDirection? = nil, representingNodeIndex: Int? = nil, isCollapsed: Bool = false) {
        self.identifier = identifier
        self.title = title
        self.nodeIndices = nodeIndices
        self.childSubgraphIndices = childSubgraphIndices
        self.direction = direction
        self.representingNodeIndex = representingNodeIndex
        self.isCollapsed = isCollapsed
    }
}
