/// A Mermaid Sankey diagram (`sankey` or `sankey-beta`) as its rows of comma-separated values describe it: the nodes
/// in the order the rows first name them, a link per row from a source node to a target node with its value, and the
/// options its front matter gives.
public struct SankeyDiagram: Equatable, Sendable {
    /// Each node once, in the order the rows first name it as a source or a target: a node's place picks its
    /// series color.
    public internal(set) var nodes: [SankeyNode]
    /// The links in the order of their rows.
    public internal(set) var links: [SankeyLink]
    /// `title:` in the front matter, or nil: Mermaid's Sankey grammar has no title statement.
    public internal(set) var title: String?
    /// The options of the front matter's `config:` for Sankey diagrams.
    public internal(set) var options: SankeyOptions

    init(nodes: [SankeyNode] = [], links: [SankeyLink] = [], title: String? = nil, options: SankeyOptions = SankeyOptions()) {
        self.nodes = nodes
        self.links = links
        self.title = title
        self.options = options
    }
}

/// A node of a Sankey diagram, by the name its rows give it.
public struct SankeyNode: Equatable, Sendable {
    /// The name as written, without the spaces at either end, a doubled quotation mark of a quoted field read as one.
    /// Entity codes are decoded where it is drawn, as Pele decodes them.
    public let name: String
}

/// A row of a Sankey diagram: a flow from one node to another.
public struct SankeyLink: Equatable, Sendable {
    /// The index in `SankeyDiagram.nodes` of the node the flow leaves.
    public let sourceIndex: Int
    /// The index in `SankeyDiagram.nodes` of the node the flow enters.
    public let targetIndex: Int
    /// The value as JavaScript's `parseFloat` reads the field (`124.729`, `1e3`, the leading number of `12 kg`), or nil
    /// when the field starts with no number. Only a finite value above zero gives the link a thickness.
    public let value: Double?
}
