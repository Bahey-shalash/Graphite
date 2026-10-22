/// A Mermaid flowchart (`flowchart` or `graph`) as its text describes it: the nodes in the order they first
/// appear, the edges between them in the order they are written, and the groups and statements read but not drawn.
public struct FlowchartDiagram: Equatable, Sendable {
    public internal(set) var direction: FlowchartDirection
    public internal(set) var nodes: [FlowchartNode]
    public internal(set) var edges: [FlowchartEdge]
    /// The `subgraph … end` groups, outermost first. They are read so that a diagram with groups is recognised;
    /// laying them out is not supported yet.
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

/// A `subgraph … end` group: its identifier, its title and the nodes written inside it.
public struct FlowchartSubgraph: Equatable, Sendable {
    public let identifier: String
    public internal(set) var title: DiagramLabel
    /// Indexes into `FlowchartDiagram.nodes`, in the order the nodes appear in the group.
    public internal(set) var nodeIndices: [Int]

    init(identifier: String, title: DiagramLabel, nodeIndices: [Int] = []) {
        self.identifier = identifier
        self.title = title
        self.nodeIndices = nodeIndices
    }
}
