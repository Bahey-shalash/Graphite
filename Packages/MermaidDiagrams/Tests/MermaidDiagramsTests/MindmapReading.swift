@testable import MermaidDiagrams

/// Reads a mindmap for a test, from its whole text, through `MermaidDiagramReader`.
enum MindmapReading {
    struct NotAMindmap: Error {}

    static func mindmap(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> MindmapDiagram {
        switch try MermaidDiagramReader.read(source, limits: limits) {
        case .mindmap(let diagram): diagram
        case .flowchart, .timeline: throw NotAMindmap()
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
