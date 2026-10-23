import MermaidDiagrams

/// An XY chart laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingXYChart: Sendable {
    let layout: XYChartLayout
    let shapes: ReadingXYChartShapes
    /// `accTitle`, else the chart's title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// Each series with its values, in the order they are written: “Revenue: jan 5000, feb 6000” along categories,
    /// “Revenue: 5000, 6000” along a range; a series without a title is named by its kind.
    let seriesSummaries: [String]

    init(chart: XYChart, layout: XYChartLayout) {
        self.layout = layout
        shapes = ReadingXYChartShapes(parts: XYChartDrawingParts(layout: layout), font: layout.font)
        title = chart.accessibilityTitle ?? chart.title
        description = chart.accessibilityDescription
        var categories: [String] = []
        if case .categories(let labels) = chart.xAxis.scale { categories = labels.map(\.spokenText) }
        seriesSummaries = chart.series.map { series in
            let name = series.title.isEmpty ? (series.kind == .bar ? "Bars" : "Line") : series.title.spokenText
            let values = series.values.enumerated().compactMap { index, value in
                value.map { value in index < categories.count ? categories[index] + " " + Self.spoken(value) : Self.spoken(value) }
            }
            return name + ": " + values.joined(separator: ", ")
        }
    }

    /// The reading view's diagram for an XY chart: drawn, or its source with why it could not be laid out.
    static func diagram(source: String, chart: XYChart, typography: DiagramTypography) -> ReadingDiagram {
        do {
            return .xyChart(ReadingXYChart(chart: chart, layout: try XYChartLayoutEngine.layout(chart, typography: typography)))
        } catch {
            return .unreadable(source: source, failure: .xyChartLayout(error))
        }
    }

    /// A value as it is written: a whole number without a fraction.
    private static func spoken(_ value: Double) -> String {
        value == value.rounded() && value.magnitude < largestExactWholeNumber ? String(Int64(value)) : String(value)
    }

    /// 2⁵³: past it, a double holds no fraction and not every whole number.
    private static let largestExactWholeNumber = 9_007_199_254_740_992.0
}
