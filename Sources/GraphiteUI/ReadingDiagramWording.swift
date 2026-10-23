import MermaidDiagrams

extension ReadingDiagramFailure {
    /// Why the diagram is not drawn, in a sentence.
    var explanation: String {
        switch self {
        case .reading(.invalidSyntax(let line, let problem)): "This diagram could not be drawn: line \(line), \(problem.explanation)."
        case .reading(.noDiagram): "This block does not name a diagram type."
        case .reading(.sourceTooLarge(let limitBytes)): "This diagram is too long to draw (more than \(limitBytes) bytes)."
        case .reading(.tooManyNodes(let limit)): "This diagram has more than \(limit) nodes, too many to draw."
        case .reading(.tooManyEdges(let limit)): "This diagram has more than \(limit) links, too many to draw."
        case .reading(.unsupportedDiagramType(let keyword)): "Diagrams of type “\(keyword)” are not drawn yet."
        case .layout(.tooManyLayoutPoints): "This diagram is too large to lay out."
        case .layout(.subgraphsNotLaidOut): "Diagrams with subgraphs are not drawn yet."
        case .stateLayout(.tooManyLayoutPoints): "This state diagram is too large to lay out."
        case .stateLayout(.compositeStatesNotLaidOut): "State diagrams with composite states are not drawn yet."
        case .classLayout(.tooManyLayoutPoints): "This class diagram is too large to lay out."
        case .classLayout(.namespacesNotLaidOut): "Class diagrams with namespaces are not drawn yet."
        case .reading(.tooManyParticipants(let limit)): "This diagram has more than \(limit) participants, too many to draw."
        case .reading(.tooManySequenceStatements(let limit)): "This diagram has more than \(limit) messages, notes and blocks, too many to draw."
        case .entityRelationshipLayout(.tooManyLayoutPoints): "This diagram is too large to lay out."
        case .entityRelationshipLayout(.subgraphsNotLaidOut): "Diagrams with subgraphs are not drawn yet."
        case .ganttLayout(.statementNotDrawn): "Gantt charts with “click” or “vert” are not drawn yet."
        case .ganttLayout(.unreadableDate(let text)): "The date “\(text)” is not in the chart’s date format."
        case .ganttLayout(.noDayLeftAfterExclusions(let task)): "Every day after the task “\(task)” is excluded."
        case .ganttLayout(.tooManyScheduledDays): "This Gantt chart’s tasks are too long to schedule around the excluded days."
        }
    }
}

extension MermaidSyntaxProblem {
    var explanation: String {
        switch self {
        case .unknownDirection(let direction): "“\(direction)” is not a direction (TB, TD, BT, LR or RL)"
        case .expectedNode: "a node is missing"
        case .unclosedShape(let closingText): "a node’s text is not closed with “\(closingText)”"
        case .unclosedQuotation: "a quotation mark is not closed"
        case .unclosedEdgeLabel: "a link’s text is not closed"
        case .unclosedAttributes: "“@{” is not closed with “}”"
        case .unclosedAccessibilityDescription: "“accDescr {” is not closed with “}”"
        case .unclosedFrontMatter: "the front matter’s “---” is not closed"
        case .endWithoutSubgraph: "“end” closes no subgraph"
        case .unclosedSubgraph(let identifier): "the subgraph “\(identifier)” has no “end”"
        case .unexpectedText(let text): "“\(text)” is not understood here"
        case .expectedState: "a state is missing"
        case .stateNameNotOneWord(let words): "a composite state’s name is one word, not “\(words)”"
        case .unclosedNote: "a note is not closed with “end note”"
        case .unclosedCompositeState(let identifier): "the composite state “\(identifier)” is not closed with “}”"
        case .closingBraceWithoutCompositeState: "“}” closes no composite state"
        case .expectedName: "a class’s or a namespace’s name is missing"
        case .expectedRelationLine: "a relation’s line (“--” or “..”) is missing"
        case .expectedQuotedText: "text in quotation marks is missing"
        case .unclosedClassBody(let identifier): "the class “\(identifier)” has no closing “}”"
        case .unclosedNamespace(let identifier): "the namespace “\(identifier)” has no closing “}”"
        case .unclosedGenericType: "a generic type’s “~” is not closed"
        case .unclosedAnnotation: "“<<” is not closed with “>>”"
        case .sequence(let problem): problem.explanation
        case .expectedRelationshipLine: "a relationship’s line (“--” or “..”) is missing"
        case .expectedCardinality: "a relationship’s cardinality (such as “||” or “o{”) is missing"
        case .expectedRelationshipLabel: "a relationship has no label after “:”"
        case .expectedAttribute: "an attribute is not written as a type and a name"
        case .unclosedAttributeBlock(let entity): "the attributes of “\(entity)” are not closed with “}”"
        case .secondRoot(let text): "“\(text)” is not indented under the root, and a mindmap has one root"
        case .unclosedIcon: "“::icon(” is not closed with “)”"
        case .eventWithoutPeriod: "an event comes before any time period"
        case .expectedSliceValue: "a slice’s label is not followed by “:” and a number"
        case .negativeSliceValue(let label): "the slice “\(label)” has a value below zero"
        case .expectedTaskData: "a task’s text is not followed by “:” and its dates"
        case .taskWithoutEnd(let task): "the task “\(task)” has no end date or duration"
        case .taskWithTooManyFields(let task): "the task “\(task)” has more than an identifier, a start and an end"
        case .expectedTaskScore: "a task’s text is not followed by “:” and its score"
        }
    }
}
