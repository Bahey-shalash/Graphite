import MermaidDiagrams

/// A quadrant chart laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingQuadrantChart: Sendable {
    let layout: QuadrantChartLayout
    let shapes: ReadingQuadrantChartShapes
    /// `accTitle`, else the title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// The quadrants' texts from quadrant 1, then each point drawn with its coordinates: “Campaign A (0.3, 0.6)”.
    let summaries: [String]

    init(chart: QuadrantChart, layout: QuadrantChartLayout) {
        self.layout = layout
        shapes = ReadingQuadrantChartShapes(parts: QuadrantChartDrawingParts(layout: layout), font: layout.font)
        title = chart.accessibilityTitle ?? chart.title
        description = chart.accessibilityDescription
        let points = chart.points.compactMap { point -> String? in
            guard let xCoordinate = point.xCoordinate, let yCoordinate = point.yCoordinate, (0...1).contains(xCoordinate),
                  (0...1).contains(yCoordinate) else { return nil }
            return point.label.spokenText + " (" + Self.written(xCoordinate) + ", " + Self.written(yCoordinate) + ")"
        }
        summaries = chart.quadrantLabels.compactMap { label in label?.spokenText } + points
    }

    /// A coordinate as written: a whole number without a fraction (`1`), else with its fraction (`0.75`).
    private static func written(_ coordinate: Double) -> String {
        coordinate == coordinate.rounded() ? String(Int(coordinate)) : String(coordinate)
    }
}
