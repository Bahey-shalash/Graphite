@testable import MermaidDiagrams

/// Reads a timeline for a test, from its whole text.
enum TimelineReading {
    static func timeline(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> TimelineDiagram {
        try TimelineParser.parse(cursorAfterKeyword(source), limits: limits)
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try timeline(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    /// A cursor just past the `timeline` keyword that every test text starts with.
    private static func cursorAfterKeyword(_ source: String) -> MermaidTextCursor {
        var cursor = MermaidTextCursor(bytes: Array(source.utf8))
        cursor.skipWhitespace()
        precondition(cursor.readWord() == "timeline", "A timeline's text starts with its keyword")
        return cursor
    }
}
