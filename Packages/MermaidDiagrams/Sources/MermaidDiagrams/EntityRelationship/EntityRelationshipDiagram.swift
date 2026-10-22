/// A Mermaid entity relationship diagram (`erDiagram`) as its text describes it: the entities in the order Mermaid
/// adds them, the relationships between them in the order they are written, and what is read but not drawn.
public struct EntityRelationshipDiagram: Equatable, Sendable {
    /// `direction TB`, `BT`, `LR` or `RL`: the way the entities' ranks follow each other, top to bottom by default.
    /// The four directions are the flowchart's, and are laid out the same way.
    public internal(set) var direction: FlowchartDirection
    public internal(set) var entities: [EntityRelationshipEntity]
    public internal(set) var relationships: [EntityRelationship]
    /// How many `subgraph … end` groups the diagram has. They are read so that a diagram with groups is recognised;
    /// laying them out is not supported yet.
    public internal(set) var subgraphCount: Int
    /// The diagram's title, from `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?
    /// Statements that change only how the diagram looks (`style`, `classDef`, `class`, `:::`). They are read and not
    /// applied yet.
    public internal(set) var unappliedStatementCount: Int

    init(direction: FlowchartDirection = .topToBottom, entities: [EntityRelationshipEntity] = [], relationships: [EntityRelationship] = [],
         subgraphCount: Int = 0, title: String? = nil, accessibilityTitle: String? = nil, accessibilityDescription: String? = nil,
         unappliedStatementCount: Int = 0) {
        self.direction = direction
        self.entities = entities
        self.relationships = relationships
        self.subgraphCount = subgraphCount
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
        self.unappliedStatementCount = unappliedStatementCount
    }
}
