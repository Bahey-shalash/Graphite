import CoreGraphics
import Foundation

/// Lays a Gantt chart out in Pele's style: its tasks scheduled as Mermaid schedules them, one row each (bars 1.85
/// times the task text's size tall, a quarter of that between rows), across a plot 800 points wide less the section
/// names on the left and room for the axis' dates, with the title above and the dates below.
public enum GanttLayoutEngine {
    /// Around the whole chart.
    static let padding: CGFloat = 8
    /// Between the title and what is below it.
    static let titleGap: CGFloat = 16
    /// The width the chart is drawn to.
    static let pageWidth: CGFloat = 800
    static let minimumPlotWidth: CGFloat = 240
    /// The widest a section's name is before it wraps.
    static let sectionWrappingWidth: CGFloat = 180
    /// Between the section names and the plot.
    static let sectionGap: CGFloat = 24
    /// Between the page's left edge (after the padding) and a section's name.
    static let sectionInset: CGFloat = 8
    static let minimumRightPadding: CGFloat = 16
    /// The widest a task's text or the title is: wide enough that neither wraps.
    static let wrappingWidth: CGFloat = 4_000
    /// The gap between a task's text and its bar's ends, and between axis dates.
    static let labelGap: CGFloat = 8
    /// The least width of a bar that is not a milestone.
    static let minimumBarWidth: CGFloat = 2
    /// The space an axis date asks for beside it, to decide how many dates fit.
    static let tickSpacing: CGFloat = 24
    static let tickCountRange = 2...10
    /// `tickInterval` may ask for a tick every this many points across the plot at most.
    static let intervalTickWidth: CGFloat = 3
    /// Between the axis line and its dates.
    static let axisDateGap: CGFloat = 2
    /// Excluded days are shaded only on a chart spanning less than this many months, as Mermaid shades them.
    static let excludedDaySpanMonths: Int64 = 72
    /// The corner radius of a task's bar (`--pele-radius`).
    public static let barCornerRadius: CGFloat = 4

    /// Lays `chart` out on `now`, the moment it is drawn, read on the wall clock of `timeZone`: today's line and the
    /// dates that default to today depend on it, so a chart is laid out the same for the same moment and time zone.
    public static func layout(_ chart: GanttChart, typography: DiagramTypography, now: Date, timeZone: TimeZone,
                              limits: MermaidDiagramLimits) throws(GanttLayoutError) -> GanttLayout {
        if let notDrawn = chart.statementsNotDrawn.first { throw .statementNotDrawn(notDrawn) }
        let zone = GanttTimeZone(timeZone: timeZone)
        let unixMilliseconds = (now.timeIntervalSince1970 * Double(GanttTime.millisecondsPerSecond)).rounded(.down)
        let boundedMilliseconds = Int64(max(-Double(GanttTime.largestMilliseconds), min(Double(GanttTime.largestMilliseconds), unixMilliseconds)))
        // A moment within a date's range always has a wall clock time; the epoch stands in for one past it.
        let wallClockNow = zone.wallClockTime(unixMilliseconds: boundedMilliseconds) ?? GanttTime(milliseconds: 0)
        let schedule = try GanttSchedule(chart: chart, now: wallClockNow, zone: zone, limits: limits)
        let measurers = GanttMeasurers(title: typography.nodeText, row: typography.rowText, axis: typography.axisText)
        return layout(chart, schedule: schedule.entries, now: wallClockNow, zone: zone, measurers: measurers, font: typography.font)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ chart: GanttChart, schedule: [GanttSchedule.Entry], now: GanttTime, zone: GanttTimeZone,
                                                       measurers: GanttMeasurers<Measurer>, font: DiagramFont) -> GanttLayout {
        let title = chart.title.map { title in
            DiagramTextBlock(label: DiagramLabelDecoder.label(from: title, form: .plain), measurer: measurers.title, maximumWidth: wrappingWidth)
        }.flatMap { block in block.lines.isEmpty ? nil : block }
        let titleHeight = title.map { title in title.size.height + titleGap } ?? 0
        guard let span = GanttTimeSpan(schedule: schedule) else {
            let size = CGSize(width: (max(title?.size.width ?? 0, 1) + 2 * padding).rounded(.up),
                              height: (max(title?.size.height ?? 0, 1) + 2 * padding).rounded(.up))
            return GanttLayout(size: size, font: font, title: title.map { title in centered(title, pageWidth: size.width) }, plot: nil)
        }
        var plot = GanttPlotBuilder(chart: chart, schedule: schedule, span: span, zone: zone, measurers: measurers, top: padding + titleHeight)
        plot.placeTasks()
        plot.placeAxis()
        let width = (max(plot.extent, padding + (title?.size.width ?? 0)) + padding).rounded(.up)
        let height = (plot.bottom + plot.metrics.tickHeight + padding).rounded(.up)
        return GanttLayout(size: CGSize(width: width, height: height), font: font, title: title.map { title in centered(title, pageWidth: width) },
                           plot: plot.finished(pageWidth: width, now: now))
    }

    /// The title centered across the page, under the padding.
    private static func centered(_ title: DiagramTextBlock, pageWidth: CGFloat) -> DiagramTextBlock {
        var placed = title
        placed.center = CGPoint(x: pageWidth / 2, y: padding + title.size.height / 2)
        return placed
    }
}

/// The measurers of a Gantt chart's text: the title's, the rows' (tasks and sections) and the axis'.
struct GanttMeasurers<Measurer: DiagramTextMeasuring> {
    let title: Measurer
    let row: Measurer
    let axis: Measurer
}

/// The time a Gantt chart's plot spans: from the earliest start to the latest end of the tasks that have both.
struct GanttTimeSpan {
    let start: GanttTime
    let stop: GanttTime

    init?(schedule: [GanttSchedule.Entry]) {
        var start: GanttTime?
        var stop: GanttTime?
        for entry in schedule {
            guard let entryStart = entry.start, let entryEnd = entry.end else { continue }
            start = min(start ?? entryStart, entryStart)
            stop = max(stop ?? entryEnd, entryEnd)
        }
        guard let start, let stop, start <= stop else { return nil }
        self.start = start
        self.stop = stop
    }
}
