@testable import MermaidDiagrams

/// Reads a mindmap for a test, from its whole text.
enum MindmapReading {
    static func mindmap(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> MindmapDiagram {
        try MindmapParser.parse(cursorAfterKeyword(source), limits: limits)
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try mindmap(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    /// A cursor just past the `mindmap` keyword that every test text starts with.
    private static func cursorAfterKeyword(_ source: String) -> MermaidTextCursor {
        var cursor = MermaidTextCursor(bytes: Array(source.utf8))
        cursor.skipWhitespace()
        precondition(cursor.readWord() == "mindmap", "A mindmap's text starts with its keyword")
        return cursor
    }
}
