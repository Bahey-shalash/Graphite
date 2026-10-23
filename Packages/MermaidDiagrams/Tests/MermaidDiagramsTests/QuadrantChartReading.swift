@testable import MermaidDiagrams

/// Reads a quadrant chart for a test, from its whole text.
enum QuadrantChartReading {
    static func quadrantChart(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> QuadrantChart {
        try QuadrantChartParser.parse(cursorAfterKeyword(source), limits: limits)
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try quadrantChart(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    /// A cursor just past the `quadrantChart` keyword that every test text starts with.
    private static func cursorAfterKeyword(_ source: String) -> MermaidTextCursor {
        var cursor = MermaidTextCursor(bytes: Array(source.utf8))
        cursor.skipWhitespace()
        precondition(cursor.readWord() == "quadrantChart", "A quadrant chart's text starts with its keyword")
        return cursor
    }
}
