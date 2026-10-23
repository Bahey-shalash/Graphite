import Foundation

/// Collects a quadrant chart as its statements are read, as Mermaid's quadrant database does: a point's coordinates as
/// JavaScript's `Number` reads them, and its styles and a class's read and checked (`QuadrantChartPointStyleSyntax`).
/// The parser hands it texts without the spaces at their ends. Points and classes count against the node limit.
struct QuadrantChartBuilder {
    private(set) var chart = QuadrantChart()
    private let limits: MermaidDiagramLimits
    private var nodeCount = 0

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    /// A later `title` replaces an earlier one; one with nothing but spaces leaves none.
    mutating func setTitle(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        chart.title = trimmed.isEmpty ? nil : trimmed
    }

    /// The text of quadrant `index + 1`; a later one replaces an earlier one.
    mutating func setQuadrantLabel(at index: Int, _ text: QuadrantChartText) {
        chart.quadrantLabels[index] = Self.label(text)
    }

    /// An axis's texts; without a high end, the axis keeps the high end it had.
    mutating func setAxisLabels(low: QuadrantChartText, high: QuadrantChartText?, isHorizontal: Bool) {
        if isHorizontal {
            chart.xAxisLowLabel = Self.label(low)
            if let high { chart.xAxisHighLabel = Self.label(high) }
        } else {
            chart.yAxisLowLabel = Self.label(low)
            if let high { chart.yAxisHighLabel = Self.label(high) }
        }
    }

    mutating func addPoint(_ point: QuadrantChartWrittenPoint, line: Int) throws(MermaidDiagramReadError) {
        try countNode()
        let style = try QuadrantChartPointStyleSyntax.style(from: point.styles, line: line)
        chart.points.append(QuadrantChartPoint(label: Self.label(point.label) ?? DiagramLabel(lines: []),
                                               xCoordinate: JavaScriptNumber.value(of: point.xCoordinate[...]),
                                               yCoordinate: JavaScriptNumber.value(of: point.yCoordinate[...]), className: point.className, style: style))
    }

    /// The styles of the class `name`; a later `classDef` of a name replaces an earlier one.
    mutating func addClass(_ name: String, styles: [String], line: Int) throws(MermaidDiagramReadError) {
        try countNode()
        chart.classStyles[name] = try QuadrantChartPointStyleSyntax.style(from: styles, line: line)
    }

    mutating func apply(_ statement: MermaidAccessibilityStatement) {
        switch statement {
        case .title(let title): chart.accessibilityTitle = title
        case .description(let description): chart.accessibilityDescription = description
        }
    }

    private mutating func countNode() throws(MermaidDiagramReadError) {
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        nodeCount += 1
    }

    /// A text as Pele draws it: a Markdown string without its emphasis markers, other text with `<br>` ending a line,
    /// tags dropped and entity codes read. Nil for empty text.
    private static func label(_ text: QuadrantChartText) -> DiagramLabel? {
        guard !text.text.isEmpty else { return nil }
        return DiagramLabelDecoder.label(from: text.text, form: text.isMarkdown ? .markdown : .plain)
    }
}
