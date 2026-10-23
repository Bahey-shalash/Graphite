@testable import MermaidDiagrams

/// Reads a Gantt chart for a test, as the reading view does.
enum GanttChartReading {
    static func ganttChart(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> GanttChart {
        guard case .ganttChart(let chart) = try MermaidDiagramReader.read(source, limits: limits) else { throw .noDiagram }
        return chart
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
