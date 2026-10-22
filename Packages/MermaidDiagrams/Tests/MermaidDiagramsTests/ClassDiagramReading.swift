@testable import MermaidDiagrams

/// Reads a class diagram for a test: the text starts with its `classDiagram` or `classDiagram-v2` keyword.
enum ClassDiagramReading {
    static func classDiagram(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> ClassDiagram {
        var cursor = MermaidTextCursor(bytes: Array(source.utf8))
        cursor.skipWhitespace()
        _ = cursor.readIdentifier()
        return try ClassDiagramParser.parse(cursor, limits: limits)
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try classDiagram(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }
}
