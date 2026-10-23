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
        case .expectedSliceValue: "a slice’s label is not followed by “:” and a number"
        case .negativeSliceValue(let label): "the slice “\(label)” has a value below zero"
        case .expectedTaskData: "a task’s text is not followed by “:” and its dates"
        case .taskWithoutEnd(let task): "the task “\(task)” has no end date or duration"
        case .taskWithTooManyFields(let task): "the task “\(task)” has more than an identifier, a start and an end"
        }
    }
}
