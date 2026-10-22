@testable import MermaidDiagrams

/// Reads a pie chart for a test, as the reading view does.
enum PieChartReading {
    static func pieChart(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> PieChart {
        guard case .pieChart(let chart) = try MermaidDiagramReader.read(source, limits: limits) else { throw .noDiagram }
        return chart
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
