@testable import MermaidDiagrams

/// Reads a flowchart for a test.
enum FlowchartReading {
    static func flowchart(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> FlowchartDiagram {
        switch try MermaidDiagramReader.read(source, limits: limits) {
        case .flowchart(let diagram): diagram
        }
    }

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
