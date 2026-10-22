@testable import MermaidDiagrams

/// Reads a timeline for a test, from its whole text, through `MermaidDiagramReader`.
enum TimelineReading {
    struct NotATimeline: Error {}

    static func timeline(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> TimelineDiagram {
        switch try MermaidDiagramReader.read(source, limits: limits) {
        case .timeline(let diagram): diagram
        case .flowchart, .mindmap: throw NotATimeline()
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
