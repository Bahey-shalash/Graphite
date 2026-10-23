/// An entity of an entity relationship diagram: the name relationships refer to it by, the text its box shows, and
/// the attributes listed under that text.
public struct EntityRelationshipEntity: Equatable, Sendable {
    /// The entity's name as written, without its quotation marks: what relationships name it by.
    public let identifier: String
    /// The text drawn at the top of the entity's box: its alias (`p[Person]`) when it has one, else its name.
    public internal(set) var label: DiagramLabel
    /// Whether `label` comes from an alias. The first alias given is kept, as in Mermaid.
    public internal(set) var hasAlias: Bool
    /// The rows of its `{ … }` blocks, in the order written; several blocks for one entity add up.
    public internal(set) var attributes: [EntityRelationshipAttribute]

    init(identifier: String, label: DiagramLabel, hasAlias: Bool = false, attributes: [EntityRelationshipAttribute] = []) {
        self.identifier = identifier
        self.label = label
        self.hasAlias = hasAlias
        self.attributes = attributes
    }
}

/// One row of an entity's `{ … }` block: `type name`, then any keys and a comment (`string id PK, FK "The key"`).
public struct EntityRelationshipAttribute: Equatable, Sendable {
    /// The type as written, with its `?` (`string?`), each pair of `~` read as angle brackets (`List~int~` is
    /// `List<int>`).
    public let type: String
    /// The name as written (`*title`, `author-ref[name](1)`), its pairs of `~` read as the type's are.
    public let name: String
    public let keys: [EntityRelationshipAttributeKey]
    /// The text between quotation marks at the end of the row, read as Markdown as Mermaid draws it, or nil.
    public let comment: DiagramLabel?

    init(type: String, name: String, keys: [EntityRelationshipAttributeKey] = [], comment: DiagramLabel? = nil) {
        self.type = type
        self.name = name
        self.keys = keys
        self.comment = comment
    }
}

/// The keys an attribute can be part of.
public enum EntityRelationshipAttributeKey: Equatable, Sendable, CaseIterable {
    /// `PK`.
    case primary
    /// `FK`.
    case foreign
    /// `UK`.
    case unique

    /// The key as Mermaid writes it, and as the diagram shows it.
    public var mermaidKeyword: String {
        switch self {
        case .primary: "PK"
        case .foreign: "FK"
        case .unique: "UK"
        }
    }
}
