import Foundation

/// Builds an XY chart statement by statement as Mermaid's chart database does: the last `x-axis` and `y-axis` win,
/// a series written before any `x-axis` sets the x axis to the range from 1 to its number of values, and each
/// series' values are placed along the x axis as it is when the series is written. The categories and values of the
/// whole chart are bounded by `MermaidDiagramLimits.maximumNodeCount`.
struct XYChartBuilder {
    private(set) var chart = XYChart()
    /// Whether an `x-axis` statement with categories or a range, or a series, has set the x axis' places.
    private var hasPlacedXAxis = false
    /// The categories and values read, for the limit.
    private var valueCount = 0
    private let limits: MermaidDiagramLimits

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    /// `horizontal` in lower case turns the chart; any other orientation word leaves it vertical, as in Mermaid.
    mutating func setOrientation(_ written: String) {
        chart.orientation = written == "horizontal" ? .horizontal : .vertical
    }

    mutating func setTitle(_ written: String) {
        chart.title = written.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func setXAxisTitle(_ written: String) {
        chart.xAxis.title = Self.label(written)
    }

    mutating func setYAxisTitle(_ written: String) {
        chart.yAxis.title = Self.label(written)
    }

    mutating func setXAxisRange(start: Double, end: Double) {
        chart.xAxis.scale = .range(start: start, end: end)
        hasPlacedXAxis = true
    }

    mutating func setXAxisCategories(_ written: [String]) throws(MermaidDiagramReadError) {
        try count(written.count)
        chart.xAxis.scale = .categories(written.map(Self.label))
        hasPlacedXAxis = true
    }

    mutating func setYAxisRange(start: Double, end: Double) {
        chart.yAxis.range = XYChartValueRange(start: start, end: end)
    }

    mutating func setAccessibilityTitle(_ written: String) {
        chart.accessibilityTitle = written.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The description, its lines' leading spaces removed, as Mermaid's database does.
    mutating func setAccessibilityDescription(_ written: String) {
        let lines = written.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n", omittingEmptySubsequences: false)
        chart.accessibilityDescription = lines.enumerated().map { index, line in
            index == 0 ? String(line) : String(line.drop { character in character.isWhitespace })
        }.filter { line in !line.isEmpty }.joined(separator: "\n")
    }

    /// A series and its points, each a value and its label, empty when it has none.
    mutating func addSeries(_ kind: XYChartSeriesKind, title: String, points: [(value: Double, label: String)]) throws(MermaidDiagramReadError) {
        try count(points.count)
        if !hasPlacedXAxis { setXAxisRange(start: 1, end: Double(points.count)) }
        let values: [Double?]
        switch chart.xAxis.scale {
        case .categories(let categories): values = categories.indices.map { index in index < points.count ? points[index].value : nil }
        case .range: values = points.map(\.value)
        }
        let labels = points.map { point in point.label.trimmingCharacters(in: .whitespacesAndNewlines) }
        let pointLabels = kind == .line && labels.contains { label in !label.isEmpty } ? labels.map(Self.label) : []
        chart.series.append(XYChartSeries(kind: kind, title: Self.label(title), values: values, pointLabels: pointLabels))
    }

    private mutating func count(_ added: Int) throws(MermaidDiagramReadError) {
        valueCount += added
        guard valueCount <= limits.maximumNodeCount else { throw .tooManyChartValues(limit: limits.maximumNodeCount) }
    }

    /// Text as written, without spaces at either end, read as plain lines: `<br>` breaks a line, tags are dropped and
    /// entity codes decoded.
    private static func label(_ written: String) -> DiagramLabel {
        let trimmed = written.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? DiagramLabel(lines: []) : DiagramLabelDecoder.label(from: trimmed, form: .plain)
    }
}
