@testable import MermaidDiagrams

/// Reads a pie chart for a test: the text's `pie` keyword, after any blank start, then its statements.
enum PieChartReading {
    static func pieChart(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> PieChart {
        var cursor = MermaidTextCursor(bytes: Array(source.utf8))
        cursor.skipWhitespace()
        guard cursor.hasPrefix(Array("pie".utf8)) else { throw .noDiagram }
        cursor.advance(by: 3)
        return try PieChartParser.parse(cursor, limits: limits)
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try pieChart(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }
}
