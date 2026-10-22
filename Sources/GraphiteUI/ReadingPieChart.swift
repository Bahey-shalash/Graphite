import MermaidDiagrams

/// A pie chart laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingPieChart: Sendable {
    let layout: PieChartLayout
    let shapes: ReadingPieChartShapes
    /// `accTitle`, else the chart's title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// Each slice as the legend shows it, with its percentage when it is drawn (`Dogs 79%`), in the written order.
    let sliceSummaries: [String]

    init(chart: PieChart, layout: PieChartLayout) {
        self.layout = layout
        shapes = ReadingPieChartShapes(parts: PieChartDrawingParts(layout: layout), font: layout.font)
        title = chart.accessibilityTitle ?? chart.title
        description = chart.accessibilityDescription
        var percentages: [Int: String] = [:]
        for slice in layout.slices { percentages[slice.seriesIndex] = slice.percentage.lines.joined() }
        sliceSummaries = layout.legend.map { entry in
            let label = entry.text.lines.joined(separator: " ")
            guard let percentage = percentages[entry.seriesIndex] else { return label }
            return label + " " + percentage
        }
    }
}
