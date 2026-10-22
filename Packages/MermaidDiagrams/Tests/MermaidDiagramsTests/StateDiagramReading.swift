@testable import MermaidDiagrams

/// Reads a state diagram for a test.
enum StateDiagramReading {
    struct NotAStateDiagram: Error {}

    static func stateDiagram(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> StateDiagram {
        switch try MermaidDiagramReader.read(source, limits: limits) {
        case .stateDiagram(let diagram): diagram
        case .flowchart: throw NotAStateDiagram()
        }
    }

    /// The syntax problem reading `source` meets, with its line, or nil when it reads or fails otherwise.
    static func syntaxProblem(_ source: String) -> (line: Int, problem: MermaidSyntaxProblem)? {
        guard case .invalidSyntax(let line, let problem) = FlowchartReading.readError(source) else { return nil }
        return (line, problem)
    }
}

extension StateDiagram {
    /// The states' identifiers, in the order they were first named.
    var identifiers: [String] {
        states.map(\.identifier)
    }

    /// The index of the state named `identifier`, or nil.
    func index(of identifier: String) -> Int? {
        states.firstIndex { state in state.identifier == identifier }
    }

    /// The state named `identifier`, or nil.
    func state(_ identifier: String) -> StateDiagramState? {
        index(of: identifier).map { index in states[index] }
    }

    /// Each transition as its source's and target's identifiers.
    var transitionIdentifiers: [[String]] {
        transitions.map { transition in [states[transition.sourceIndex].identifier, states[transition.targetIndex].identifier] }
    }
}
