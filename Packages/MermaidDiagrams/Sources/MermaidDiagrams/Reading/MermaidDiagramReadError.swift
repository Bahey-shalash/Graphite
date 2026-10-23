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
    /// A sequence diagram names more participants than `MermaidDiagramLimits.maximumNodeCount`.
    case tooManyParticipants(limit: Int)
    /// A sequence diagram holds more messages, notes, activations and block lines than
    /// `MermaidDiagramLimits.maximumEdgeCount`.
    case tooManySequenceStatements(limit: Int)
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
    /// A state was expected: after `-->`, after `note left of`, or after `as`.
    case expectedState
    /// `state two words {`: a composite state's name is one word. The words before the brace.
    case stateNameNotOneWord(String)
    /// A note over several lines has no `end note`.
    case unclosedNote
    /// The text ends inside a composite state's body, by the state's identifier.
    case unclosedCompositeState(identifier: String)
    /// `}` with no composite state's body open.
    case closingBraceWithoutCompositeState
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
    /// A problem of a sequence diagram's own syntax.
    case sequence(SequenceSyntaxProblem)
    /// An entity relationship's first cardinality is not followed by its line: `--`, `..`, `.-`, `-.`, `to` or
    /// `optionally to`.
    case expectedRelationshipLine
    /// An entity relationship's line is not followed by a cardinality (`||`, `o{`, `one or more` …).
    case expectedCardinality
    /// An entity relationship has no label: `:` then a word or quoted text after the second entity.
    case expectedRelationshipLabel
    /// An entity's `{ … }` holds something other than attributes: a type and a name, then keys and a comment.
    case expectedAttribute
    /// The text ends inside an entity's `{ … }`, by the entity's name.
    case unclosedAttributeBlock(entity: String)
    /// A mindmap node indented no more than the root, by its text: a mindmap has one root.
    case secondRoot(text: String)
    /// A mindmap's `::icon(` has no closing parenthesis.
    case unclosedIcon
    /// A timeline's event (`: event`) comes before any time period.
    case eventWithoutPeriod
    /// A pie chart's slice label is not followed by `:` and a number (`"Dogs" : 386`).
    case expectedSliceValue
    /// A pie chart's slice has a value below zero, by the slice's label.
    case negativeSliceValue(label: String)
    /// A Gantt chart's task has no colon and data after its text (`Design :a1, 2014-01-01, 3d`).
    case expectedTaskData
    /// A Gantt chart's task has tags and nothing else: no end or duration, by the task's text.
    case taskWithoutEnd(task: String)
    /// A Gantt chart's task has more than an identifier, a start and an end after its tags, by the task's text.
    case taskWithTooManyFields(task: String)
    /// A user journey's task has no colon and score after its text (`Make tea: 5: Me`).
    case expectedTaskScore
}
