@testable import MermaidDiagrams

/// Reads a user journey for a test, from its whole text.
enum UserJourneyReading {
    static func userJourney(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> UserJourneyDiagram {
        try UserJourneyParser.parse(cursorAfterKeyword(source), limits: limits)
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try userJourney(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    /// A cursor just past the `journey` keyword that every test text starts with.
    private static func cursorAfterKeyword(_ source: String) -> MermaidTextCursor {
        var cursor = MermaidTextCursor(bytes: Array(source.utf8))
        cursor.skipWhitespace()
        precondition(cursor.readWord() == "journey", "A user journey's text starts with its keyword")
        return cursor
    }
}
