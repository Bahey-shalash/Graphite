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
        case .reading(.tooManyParticipants(let limit)): "This diagram has more than \(limit) participants, too many to draw."
        case .reading(.tooManySequenceStatements(let limit)): "This diagram has more than \(limit) messages, notes and blocks, too many to draw."
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
        case .sequence(let problem): problem.explanation
        }
    }
}
