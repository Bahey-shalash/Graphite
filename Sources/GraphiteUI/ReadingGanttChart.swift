import Foundation
import MermaidDiagrams

/// A Gantt chart scheduled and laid out on the moment the note is built, its shapes ready to paint, and what a
/// screen reader says of it.
struct ReadingGanttChart: Sendable {
    let layout: GanttLayout
    let shapes: ReadingGanttChartShapes
    /// `accTitle`, else the chart's title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// The tasks' text, in the order they are written.
    let taskNames: [String]

    init(chart: GanttChart, layout: GanttLayout) {
        self.layout = layout
        shapes = ReadingGanttChartShapes(parts: GanttDrawingParts(layout: layout), font: layout.font)
        title = chart.accessibilityTitle ?? chart.title
        description = chart.accessibilityDescription
        taskNames = chart.tasks.map(\.name)
    }

    /// The reading view's diagram for a Gantt chart drawn on `now` in `timeZone`: drawn, or its source with why it
    /// could not be scheduled, or nil to show it as code when it has a statement not drawn yet or a date in a form
    /// not read here (Mermaid then asks JavaScript's date parser, which reads more).
    static func diagram(source: String, chart: GanttChart, typography: DiagramTypography, now: Date, timeZone: TimeZone) -> ReadingDiagram? {
        do {
            let layout = try GanttLayoutEngine.layout(chart, typography: typography, now: now, timeZone: timeZone, limits: .standard)
            return .ganttChart(ReadingGanttChart(chart: chart, layout: layout))
        } catch .statementNotDrawn, .unreadableDate {
            return nil
        } catch {
            return .unreadable(source: source, failure: .ganttLayout(error))
        }
    }
}
