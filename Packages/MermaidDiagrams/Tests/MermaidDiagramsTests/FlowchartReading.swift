@testable import MermaidDiagrams

/// Reads a flowchart for a test.
enum FlowchartReading {
    struct NotAFlowchart: Error {}

    static func flowchart(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> FlowchartDiagram {
        switch try MermaidDiagramReader.read(source, limits: limits) {
        case .flowchart(let diagram): diagram
        case .stateDiagram: throw NotAFlowchart()
        case .classDiagram: throw NotAFlowchart()
        case .sequence: throw NotAFlowchart()
        }
    }

    /// The text read is a diagram of another type.
    struct NotAFlowchart: Error {}

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try MermaidDiagramReader.read(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }
}
