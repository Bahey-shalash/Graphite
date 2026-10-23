/// A relation of a class diagram, from one end to the other as written (`Animal <|-- Duck` runs from Animal to
/// Duck, with the triangle at Animal).
public struct ClassDiagramRelation: Equatable, Sendable {
    public let source: ClassDiagramRelationEndpoint
    public let target: ClassDiagramRelationEndpoint
    /// The mark at the source: the one written before the line.
    public let sourceEnd: ClassDiagramRelationEnd
    /// The mark at the target: the one written after the line.
    public let targetEnd: ClassDiagramRelationEnd
    /// Solid for `--`, dashed for `..`.
    public let line: ClassDiagramLineStyle
    /// The quoted text before the line (`"1"` in `A "1" --> "*" B`), or nil.
    public let sourceCardinality: String?
    /// The quoted text after the line, or nil.
    public let targetCardinality: String?
    /// The text after a colon (`A --> B : uses`), or nil.
    public let label: DiagramLabel?

    init(source: ClassDiagramRelationEndpoint, target: ClassDiagramRelationEndpoint, sourceEnd: ClassDiagramRelationEnd = .none,
         targetEnd: ClassDiagramRelationEnd = .none, line: ClassDiagramLineStyle = .solid, sourceCardinality: String? = nil,
         targetCardinality: String? = nil, label: DiagramLabel? = nil) {
        self.source = source
        self.target = target
        self.sourceEnd = sourceEnd
        self.targetEnd = targetEnd
        self.line = line
        self.sourceCardinality = sourceCardinality
        self.targetCardinality = targetCardinality
        self.label = label
    }
}

/// What a relation joins at one end.
public enum ClassDiagramRelationEndpoint: Equatable, Sendable {
    /// Index into `ClassDiagram.classes`.
    case classIndex(Int)
    /// The interface a lollipop end names (`bar` in `bar ()-- foo`): drawn as its name beside the class, joined by
    /// a ring. Each lollipop relation has its own, as in Mermaid.
    case interface(DiagramLabel)
}

/// The mark drawn where a relation meets what it joins.
public enum ClassDiagramRelationEnd: Equatable, Sendable, CaseIterable {
    case none
    /// `<|` or `|>`: a hollow triangle, inheritance on a solid line and realization on a dashed one.
    case inheritance
    /// `*`: a filled diamond.
    case composition
    /// `o`: a hollow diamond.
    case aggregation
    /// `<` or `>`: a filled arrowhead, association on a solid line and dependency on a dashed one.
    case arrow
    /// `()`: a ring, where a lollipop interface meets its class.
    case lollipop
}

/// How a relation's or a note's line is drawn.
public enum ClassDiagramLineStyle: Equatable, Sendable, CaseIterable {
    /// `--`.
    case solid
    /// `..`, in dashes.
    case dashed
    /// In dots: the line that joins a note to its class.
    case dotted
}
