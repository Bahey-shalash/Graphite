/// Why a diagram's text was not read. Each case carries facts; the words are the caller's.
public enum MermaidDiagramReadError: Error, Equatable, Sendable {
    /// The text declares no diagram: it is empty, or holds only comments and front matter.
    case noDiagram
    case sourceTooLarge(limitBytes: Int)
    /// A diagram type this package does not read yet, by the keyword that declares it (`sequenceDiagram`).
    case unsupportedDiagramType(keyword: String)
    /// The text breaks the diagram's syntax on `line`, counted from 1 at the diagram's first line.
    case invalidSyntax(line: Int, problem: MermaidSyntaxProblem)
    case tooManyNodes(limit: Int)
    case tooManyEdges(limit: Int)
}

/// What a reader found where the syntax broke.
public enum MermaidSyntaxProblem: Equatable, Sendable {
    /// A direction other than `TB`, `TD`, `BT`, `LR` and `RL` after `flowchart` or `graph`.
    case unknownDirection(String)
    /// A node was expected, after a link or an `&`, or at the start of a statement.
    case expectedNode
    /// A node's text has no closing bracket: the text that should close it.
    case unclosedShape(closingText: String)
    case unclosedQuotation
    /// An edge's text (`-->|text|` or `-- text -->`) has no end.
    case unclosedEdgeLabel
    /// `@{ … }` has no closing brace.
    case unclosedAttributes
    /// `accDescr { … }` has no closing brace.
    case unclosedAccessibilityDescription
    /// The front matter's opening `---` has no closing `---`.
    case unclosedFrontMatter
    /// `end` with no `subgraph` open.
    case endWithoutSubgraph
    /// The text ends inside a `subgraph`, by the group's identifier.
    case unclosedSubgraph(identifier: String)
    /// Text that fits nowhere in the statement: its first characters.
    case unexpectedText(String)
    /// A name was expected: a class's after `class`, a relation's line, `note for` or an annotation, or a namespace's.
    case expectedName
    /// A relation's line (`--` or `..`) was expected after its first class, cardinality or mark.
    case expectedRelationLine
    /// Text in quotation marks was expected: a note's, or a class's label inside `[` `]`.
    case expectedQuotedText
    /// A class's `{` has no closing `}`, by the class's identifier.
    case unclosedClassBody(identifier: String)
    /// The text ends inside a `namespace`, by the innermost one's identifier.
    case unclosedNamespace(identifier: String)
    /// A `~` that opens a generic type has no closing `~` on its line.
    case unclosedGenericType
    /// A `<<` that opens an annotation has no closing `>>` on its line.
    case unclosedAnnotation
}
