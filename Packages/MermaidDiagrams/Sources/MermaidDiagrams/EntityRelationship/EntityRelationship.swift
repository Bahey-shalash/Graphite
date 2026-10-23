/// A relationship between two entities (`CUSTOMER ||--o{ ORDER : places`), from the entity written first to the
/// entity written second, which may be the same one.
public struct EntityRelationship: Equatable, Sendable {
    /// Index into `EntityRelationshipDiagram.entities` of the entity written first.
    public let firstEntityIndex: Int
    /// Index into `EntityRelationshipDiagram.entities` of the entity written second.
    public let secondEntityIndex: Int
    /// The cardinality written next to the first entity (`||` above: one order has exactly one customer), drawn where
    /// the line meets the first entity's box.
    public let firstEntityCardinality: EntityRelationshipCardinality
    /// The cardinality written next to the second entity (`o{` above: one customer has zero or more orders), drawn
    /// where the line meets the second entity's box.
    public let secondEntityCardinality: EntityRelationshipCardinality
    public let identification: EntityRelationshipIdentification
    /// The text after the `:`, read from the first entity's side (`places`); empty for `""`.
    public let label: DiagramLabel

    init(firstEntityIndex: Int, secondEntityIndex: Int, firstEntityCardinality: EntityRelationshipCardinality,
         secondEntityCardinality: EntityRelationshipCardinality, identification: EntityRelationshipIdentification, label: DiagramLabel) {
        self.firstEntityIndex = firstEntityIndex
        self.secondEntityIndex = secondEntityIndex
        self.firstEntityCardinality = firstEntityCardinality
        self.secondEntityCardinality = secondEntityCardinality
        self.identification = identification
        self.label = label
    }
}

/// How many instances of the entity at one end of a relationship relate to one instance of the entity at the other
/// end, drawn in crow's foot notation where the line meets that end's box. Each is written with symbols on either
/// side of the line (`|o` or `o|`) or with words.
public enum EntityRelationshipCardinality: Equatable, Sendable, CaseIterable {
    /// `|o`, `o|`, `zero or one`, `one or zero`.
    case zeroOrOne
    /// `||`, `one`, `only one`, `1`.
    case exactlyOne
    /// `}o`, `o{`, `zero or more`, `zero or many`, `many`, `many(0)`, `0+`.
    case zeroOrMore
    /// `}|`, `|{`, `one or more`, `one or many`, `many(1)`, `1+`.
    case oneOrMore
    /// `u`: the parent end of a parent and child relationship (Mermaid's `MD_PARENT`), drawn as a hollow diamond.
    case parent
}

/// Whether the entity at one end cannot exist without the other.
public enum EntityRelationshipIdentification: Equatable, Sendable, CaseIterable {
    /// `--` or `to`: drawn as a solid line.
    case identifying
    /// `..`, `.-`, `-.` or `optionally to`: both entities exist on their own; drawn as a dashed line.
    case nonIdentifying
}
