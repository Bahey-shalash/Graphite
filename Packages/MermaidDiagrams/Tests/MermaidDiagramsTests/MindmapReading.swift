@testable import MermaidDiagrams

/// Reads a mindmap for a test, from its whole text, through `MermaidDiagramReader`.
enum MindmapReading {
    struct NotAMindmap: Error {}

    static func mindmap(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> MindmapDiagram {
        guard case .mindmap(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw NotAMindmap() }
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
}
