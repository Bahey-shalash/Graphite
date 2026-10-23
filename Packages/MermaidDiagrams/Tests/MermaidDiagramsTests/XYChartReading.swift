@testable import MermaidDiagrams

/// Reads an XY chart for a test, from its whole text, through `MermaidDiagramReader`.
enum XYChartReading {
    static func chart(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> XYChart {
        guard case .xyChart(let chart) = try MermaidDiagramReader.read(source, limits: limits) else { throw .noDiagram }
        return chart
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try chart(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    /// The text of a label's lines, joined by spaces.
    static func text(_ label: DiagramLabel) -> String {
        label.spokenText
    }
}
