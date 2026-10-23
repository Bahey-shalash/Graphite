/// A Mermaid XY chart (`xychart` or `xychart-beta`) as Mermaid's chart database holds it once its text is read: the
/// orientation, the titles, the x axis (categories or a range of numbers), the y axis' title and range when one is
/// written, and the bar and line series with their values placed along the x axis.
public struct XYChart: Equatable, Sendable {
    public internal(set) var orientation: XYChartOrientation
    /// `title …` in the chart, else `title:` in the front matter, or nil.
    public internal(set) var title: String?
    public internal(set) var xAxis: XYChartXAxis
    public internal(set) var yAxis: XYChartYAxis
    /// The series in the order they are written: each keeps the series color of its place.
    public internal(set) var series: [XYChartSeries]
    /// `accTitle: …`, the short name a screen reader gives the chart, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?

    init(orientation: XYChartOrientation = .vertical, title: String? = nil, xAxis: XYChartXAxis = XYChartXAxis(),
         yAxis: XYChartYAxis = XYChartYAxis(), series: [XYChartSeries] = [], accessibilityTitle: String? = nil,
         accessibilityDescription: String? = nil) {
        self.orientation = orientation
        self.title = title
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.series = series
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
    }
}

/// Which way an XY chart's x axis runs.
public enum XYChartOrientation: Equatable, Sendable {
    /// `xychart` or `xychart vertical`: the x axis along the bottom, values up the left, bars standing up.
    case vertical
    /// `xychart horizontal`: the x axis down the left, values along the bottom, bars lying across.
    case horizontal
}

/// `x-axis …`: where the series' values are placed.
public struct XYChartXAxis: Equatable, Sendable {
    /// The axis' title, empty when none is written.
    public internal(set) var title: DiagramLabel
    public internal(set) var scale: XYChartXAxisScale

    init(title: DiagramLabel = DiagramLabel(lines: []), scale: XYChartXAxisScale = .categories([])) {
        self.title = title
        self.scale = scale
    }
}

/// The places along an XY chart's x axis.
public enum XYChartXAxisScale: Equatable, Sendable {
    /// `x-axis [a, b]`: one place per category, in the order they are written. No category before any is written.
    case categories([DiagramLabel])
    /// `x-axis 1 --> 10`, or the range a series written before any `x-axis` gives (1 to its number of values): the
    /// first value at `start` and the last at `end`, which may be the smaller.
    case range(start: Double, end: Double)
}

/// `y-axis …`: the values' title and range.
public struct XYChartYAxis: Equatable, Sendable {
    /// The axis' title, empty when none is written.
    public internal(set) var title: DiagramLabel
    /// `y-axis 0 --> 100`, the value at the bottom and the value at the top, or nil when no range is written and the
    /// layout takes it from the values.
    public internal(set) var range: XYChartValueRange?

    init(title: DiagramLabel = DiagramLabel(lines: []), range: XYChartValueRange? = nil) {
        self.title = title
        self.range = range
    }
}

/// A range of values as written: `start --> end`, the end possibly the smaller.
public struct XYChartValueRange: Equatable, Sendable {
    public let start: Double
    public let end: Double
}

/// A `bar` or `line` series of an XY chart.
public struct XYChartSeries: Equatable, Sendable {
    public let kind: XYChartSeriesKind
    /// The series' title, which the legend shows, empty when none is written.
    public let title: DiagramLabel
    /// The values at the x axis' places as Mermaid places them when the series is written: one per category (nil
    /// where the series has no value, and the values past the last category left out), else one per value written.
    /// A value is as written, and may be infinite when its digits overflow.
    public let values: [Double?]
    /// A line's point labels (`line [540 "PaLM", 65]`), one per value written, empty for a point without one; empty
    /// when no point of the line has one, and for bars, whose point labels Mermaid reads and does not show.
    public let pointLabels: [DiagramLabel]

    init(kind: XYChartSeriesKind, title: DiagramLabel, values: [Double?], pointLabels: [DiagramLabel] = []) {
        self.kind = kind
        self.title = title
        self.values = values
        self.pointLabels = pointLabels
    }
}

public enum XYChartSeriesKind: Equatable, Sendable {
    /// `bar [ … ]`: a bar per value, from zero.
    case bar
    /// `line [ … ]`: the values joined by a line, drawn over the bars.
    case line
}
