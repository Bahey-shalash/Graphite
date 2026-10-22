@testable import MermaidDiagrams

/// Reads a class diagram for a test, through the reader that every diagram's text goes through.
enum ClassDiagramReading {
    static func classDiagram(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> ClassDiagram {
        guard case .classDiagram(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw NotAClassDiagram() }
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

    /// The text read is a diagram of another type.
    struct NotAClassDiagram: Error {}
}
