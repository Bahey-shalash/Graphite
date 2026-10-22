/// A Mermaid state diagram (`stateDiagram` or `stateDiagram-v2`) as its text describes it: the states in the order
/// they are first named, the transitions between them and the notes beside them in the order they are written, and
/// the composite states read but not drawn.
public struct StateDiagram: Equatable, Sendable {
    /// The way the top level runs: its last `direction` statement, top to bottom when it has none. A state diagram
    /// takes the same four directions as a flowchart.
    public internal(set) var direction: FlowchartDirection
    public internal(set) var states: [StateDiagramState]
    public internal(set) var transitions: [StateDiagramTransition]
    public internal(set) var notes: [StateDiagramNote]
    /// The states written with a body (`state Id { … }`), in the order their bodies open. They are read so that a
    /// diagram with composite states is recognised; laying them out is not supported yet.
    public internal(set) var composites: [StateDiagramComposite]
    /// The diagram's title, from `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?
    /// Statements that change only how the diagram looks (`classDef`, `class`, `:::`, `style`) or what a click does
    /// (`click`). They are read and not applied yet.
    public internal(set) var unappliedStatementCount: Int

    init(direction: FlowchartDirection = .topToBottom, states: [StateDiagramState] = [], transitions: [StateDiagramTransition] = [],
         notes: [StateDiagramNote] = [], composites: [StateDiagramComposite] = [], title: String? = nil, accessibilityTitle: String? = nil,
         accessibilityDescription: String? = nil, unappliedStatementCount: Int = 0) {
        self.direction = direction
        self.states = states
        self.transitions = transitions
        self.notes = notes
        self.composites = composites
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
        self.unappliedStatementCount = unappliedStatementCount
    }
}
