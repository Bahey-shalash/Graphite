import CoreGraphics

/// A Gantt chart laid out on a page whose origin is the top left corner and whose y runs down, in points: the title
/// above, then a row per task across the plot, with the section bands and names on the left, and the axis' dates
/// below (and above with `topAxis`). Drawing it needs only colors.
public struct GanttLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the title was measured in; task, section and axis text are in the same font at their own `fontSize`.
    public let font: DiagramFont
    public let title: DiagramTextBlock?
    /// The rows and the axis, or nil when no task could be given a start and an end: only the title is drawn.
    public let plot: GanttPlot?
}

public struct GanttPlot: Equatable, Sendable {
    /// From the axis' first date to its last across, and from the first row's top to the last row's bottom down.
    public let frame: CGRect
    /// Whether the axis' dates and line are drawn above the rows too.
    public let showsTopAxis: Bool
    /// The bands behind the rows of every other section, filled in the surface color, as wide as the page.
    public let sectionBands: [CGRect]
    /// The sections' names, each centered down its rows, at the left.
    public let sectionNames: [DiagramTextBlock]
    /// The runs of excluded days, filled in the alternate surface color.
    public let excludedDays: [CGRect]
    /// Where a dotted grid line runs down the rows at each of the axis' dates.
    public let gridLineOffsets: [CGFloat]
    /// The axis' dates below the rows, and above them with `topAxis`; a date that would run into the one before it is
    /// left out, its grid line kept.
    public let axisDates: [DiagramTextBlock]
    public let tasks: [GanttLayoutTask]
    /// Where today's line runs down the rows, or nil when it is off or today is outside the chart.
    public let todayOffset: CGFloat?
}

public struct GanttLayoutTask: Equatable, Sendable {
    public let shape: GanttTaskShape
    public let paint: GanttTaskPaint
    /// The task's text on one line: inside its bar when it fits, else beside it.
    public let label: DiagramTextBlock
    public let labelColor: GanttLabelColor
}

/// How a task is drawn.
public enum GanttTaskShape: Equatable, Sendable {
    /// A bar from the task's start to its end, with rounded corners.
    case bar(CGRect)
    /// A diamond at the middle of the task's time, as tall as a bar: its bounding square.
    case milestone(CGRect)
    /// No shape: the task has no start or end, and only its text is drawn.
    case unscheduled
}

/// The colors of a task's shape, by Pele's rules: a critical task takes the critical color in place of the accent;
/// an active one is a faint fill of its color; a done one takes the alternate surface, with the border color unless
/// it is critical.
public struct GanttTaskPaint: Equatable, Sendable {
    public let fill: GanttTaskFill
    public let stroke: GanttTaskStroke
}

public enum GanttTaskFill: Equatable, Sendable {
    case accent
    case faintAccent
    case critical
    case faintCritical
    case alternateSurface
}

public enum GanttTaskStroke: Equatable, Sendable {
    case accent
    case critical
    case border
}

/// The color of a task's text.
public enum GanttLabelColor: Equatable, Sendable {
    /// Inside a bar of a task neither done nor active: the page's color on the bar's.
    case background
    case foreground
    /// Beside a done task, or for a task without a start and an end.
    case muted
}
