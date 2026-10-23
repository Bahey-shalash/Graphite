@testable import MermaidDiagrams

/// Reads a Git graph for a test, from its whole text, through `MermaidDiagramReader`.
enum GitGraphReading {
    struct NotAGitGraph: Error {}

    static func gitGraph(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> GitGraphDiagram {
        guard case .gitGraph(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw NotAGitGraph() }
        return diagram
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

    /// The problem of a Git graph's own on `line`, as `readError` reports it.
    static func problem(_ problem: GitGraphSyntaxProblem, line: Int) -> MermaidDiagramReadError {
        .invalidSyntax(line: line, problem: .gitGraph(problem))
    }
}
