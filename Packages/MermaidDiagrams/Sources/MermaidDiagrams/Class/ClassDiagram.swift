/// A Mermaid class diagram (`classDiagram` or `classDiagram-v2`) as its text describes it: the classes in the order
/// they first appear, the relations between them and the notes in the order they are written, and the groups and
/// statements read but not drawn.
public struct ClassDiagram: Equatable, Sendable {
    /// The way ranks of classes follow each other: `direction TB`, `BT`, `LR` or `RL`, top to bottom by default.
    public internal(set) var direction: FlowchartDirection
    public internal(set) var classes: [ClassDiagramClass]
    public internal(set) var relations: [ClassDiagramRelation]
    public internal(set) var notes: [ClassDiagramNote]
    /// The `namespace … { … }` groups, in the order they open. They are read so that a diagram with groups is
    /// recognised; laying them out is not supported yet.
    public internal(set) var namespaces: [ClassDiagramNamespace]
    /// The diagram's title, from `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?
    /// Statements that change only how the diagram looks (`style`, `classDef`, `cssClass`, `:::`) or what a click
    /// does (`click`, `link`, `callback`). They are read and not applied.
    public internal(set) var unappliedStatementCount: Int

    init(direction: FlowchartDirection = .topToBottom, classes: [ClassDiagramClass] = [], relations: [ClassDiagramRelation] = [],
         notes: [ClassDiagramNote] = [], namespaces: [ClassDiagramNamespace] = [], title: String? = nil, accessibilityTitle: String? = nil,
         accessibilityDescription: String? = nil, unappliedStatementCount: Int = 0) {
        self.direction = direction
        self.classes = classes
        self.relations = relations
        self.notes = notes
        self.namespaces = namespaces
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
        self.unappliedStatementCount = unappliedStatementCount
    }
}

/// A note: `note "text"` stands alone, `note for Name "text"` is joined to its class by a dotted line.
public struct ClassDiagramNote: Equatable, Sendable {
    public let text: DiagramLabel
    /// Index into `ClassDiagram.classes` of the class `note for` names, or nil for a note on its own or one whose
    /// class the diagram never declares.
    public internal(set) var classIndex: Int?

    init(text: DiagramLabel, classIndex: Int? = nil) {
        self.text = text
        self.classIndex = classIndex
    }
}

/// A `namespace Name { … }` group: its identifier (a nested one's joined to its parents' by dots), its title, and
/// the classes declared inside it.
public struct ClassDiagramNamespace: Equatable, Sendable {
    public let identifier: String
    public let title: DiagramLabel
    /// Indexes into `ClassDiagram.classes`, in the order the classes appear in the group.
    public internal(set) var classIndices: [Int]

    init(identifier: String, title: DiagramLabel, classIndices: [Int] = []) {
        self.identifier = identifier
        self.title = title
        self.classIndices = classIndices
    }
}
