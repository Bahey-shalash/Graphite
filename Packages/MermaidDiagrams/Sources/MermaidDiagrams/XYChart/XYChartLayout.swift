import CoreGraphics

/// An XY chart laid out on a page whose origin is the top left corner and whose y runs down, in points, as Pele lays
/// it out: the title above, the plot with its grid, bars and lines, the axes on its left and bottom with their marks'
/// labels and titles, and the legend on the right. Drawing it needs only colors.
public struct XYChartLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the title was measured in; the axes, the legend and the point labels are in the same font at their
    /// own `fontSize`.
    public let font: DiagramFont
    /// The chart's title, drawn bold, or nil.
    public let title: DiagramTextBlock?
    /// The plot, from the axes' corner: the bars and lines are inside it.
    public let plotFrame: CGRect
    /// A line across the plot at each mark of the value axis, drawn first, in the alternate surface color.
    public let gridLines: [XYChartSegment]
    /// The axes' lines, their marks' ticks, and the line bars stand on when they go both ways, in the border color.
    public let axisLines: [XYChartSegment]
    /// The marks' labels, left of the left axis and below the bottom one, in the muted color.
    public let axisLabels: [DiagramTextBlock]
    /// The bottom axis' title below its labels, or nil.
    public let bottomAxisTitle: DiagramTextBlock?
    /// The left axis' title, drawn turned a quarter turn counterclockwise about its center, or nil.
    public let leftAxisTitle: DiagramTextBlock?
    /// Every bar series' bars, filled in their series' colors.
    public let bars: [XYChartBar]
    /// Every line series' line and dots, in the order the series are written, drawn over the bars.
    public let lines: [XYChartLine]
    /// The labels of lines' points, in the text color.
    public let pointLabels: [DiagramTextBlock]
    /// One entry for each series with a title, in the order they are written, while they fit the page's height.
    public let legend: [XYChartLegendEntry]
}

/// A straight line from one point to another.
public struct XYChartSegment: Equatable, Sendable {
    public let start: CGPoint
    public let end: CGPoint
}

public struct XYChartBar: Equatable, Sendable {
    /// The series' place among the chart's series, which picks its series color.
    public let seriesIndex: Int
    public let frame: CGRect
}

public struct XYChartLine: Equatable, Sendable {
    /// The series' place among the chart's series, which picks its series color.
    public let seriesIndex: Int
    /// The line's runs, each a polyline: a run ends where the line leaves the value range or a value is missing.
    public let runs: [[CGPoint]]
    /// The dots on the values inside the range, empty when the places are too close together for them.
    public let dots: [CGPoint]
}

/// A row of the legend: a swatch in the series' color, then its title.
public struct XYChartLegendEntry: Equatable, Sendable {
    public let seriesIndex: Int
    public let kind: XYChartSeriesKind
    /// The swatch's square: filled with rounded corners for a bar series, crossed by a line through its middle for a
    /// line series.
    public let swatch: CGRect
    public let text: DiagramTextBlock
}

/// Why an XY chart is not laid out.
public enum XYChartLayoutError: Error, Equatable, Sendable {
    /// The chart has no bar or line series: Mermaid draws nothing and says so.
    case noSeries
}
