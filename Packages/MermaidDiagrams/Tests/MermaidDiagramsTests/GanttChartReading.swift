@testable import MermaidDiagrams

/// Reads a Gantt chart for a test: the text's `gantt` keyword, after any blank start, then its statements.
enum GanttChartReading {
    static func ganttChart(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> GanttChart {
        var cursor = MermaidTextCursor(bytes: Array(source.utf8))
        cursor.skipWhitespace()
        guard cursor.hasPrefix(Array("gantt".utf8)) else { throw .noDiagram }
        cursor.advance(by: 5)
        return try GanttChartParser.parse(cursor, limits: limits)
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try ganttChart(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }
}
