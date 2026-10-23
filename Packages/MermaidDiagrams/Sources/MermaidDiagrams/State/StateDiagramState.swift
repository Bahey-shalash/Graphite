/// A state of a state diagram: the identifier transitions name it by, what kind of state it is, and the text written
/// for it.
public struct StateDiagramState: Equatable, Sendable {
    /// The identifier as written; `[*]` for a start or an end.
    public let identifier: String
    public internal(set) var kind: StateDiagramStateKind
    /// The texts written for the state (`Id : text`, `state "text" as Id`), in the order written. The first is drawn
    /// as its name, and the others under a line below it, in smaller type.
    public internal(set) var descriptions: [DiagramLabel]
    /// Index into `StateDiagram.composites` of the composite state it was last named inside, or nil when it was only
    /// named at the top level.
    public internal(set) var compositeIndex: Int?

    init(identifier: String, kind: StateDiagramStateKind, descriptions: [DiagramLabel] = [], compositeIndex: Int? = nil) {
        self.identifier = identifier
        self.kind = kind
        self.descriptions = descriptions
        self.compositeIndex = compositeIndex
    }

    /// The text drawn as the state's name: its first description, else its identifier.
    public var name: DiagramLabel {
        descriptions.first ?? DiagramLabel(identifier)
    }
}

/// What a state is drawn as.
public enum StateDiagramStateKind: Equatable, Sendable, CaseIterable {
    /// A rounded box around its name.
    case state
    /// `[*]` where a transition leaves it: a filled circle.
    case start
    /// `[*]` where a transition arrives: a filled circle in a ring.
    case end
    /// `<<choice>>`: a small diamond.
    case choice
    /// `<<fork>>`: a bar across the flow that one transition enters and several leave.
    case fork
    /// `<<join>>`: a bar across the flow that several transitions enter and one leaves.
    case join

    /// The kind a stereotype names, `fork`, `join` or `choice` (`<<fork>>`, `[[fork]]`), in any case.
    init?(stereotype: String) {
        switch stereotype.lowercased() {
        case "fork": self = .fork
        case "join": self = .join
        case "choice": self = .choice
        default: return nil
        }
    }
}
