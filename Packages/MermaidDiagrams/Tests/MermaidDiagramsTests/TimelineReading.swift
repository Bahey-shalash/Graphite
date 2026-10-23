@testable import MermaidDiagrams

/// Reads a timeline for a test, from its whole text, through `MermaidDiagramReader`.
enum TimelineReading {
    struct NotATimeline: Error {}

    static func timeline(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> TimelineDiagram {
        guard case .timeline(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw NotATimeline() }
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
