import MermaidDiagrams

/// A Sankey diagram laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingSankeyDiagram: Sendable {
    let layout: SankeyLayout
    let shapes: ReadingSankeyShapes
    /// The front matter's title, or nil: Mermaid's Sankey grammar has no accessibility statements.
    let title: String?
    /// Each flow in the order of its row, as its label writes its value: “Coal to Solid: 75.57”.
    let flowSummaries: [String]

    init(diagram: SankeyDiagram, layout: SankeyLayout) {
        self.layout = layout
        shapes = ReadingSankeyShapes(parts: SankeyDrawingParts(layout: layout), size: layout.size, font: layout.font)
        title = diagram.title
        flowSummaries = diagram.links.map { link in
            let flow = diagram.nodes[link.sourceIndex].name + " to " + diagram.nodes[link.targetIndex].name
            guard let value = link.value, value.isFinite, value > 0 else { return flow }
            return flow + ": " + Self.spoken(value)
        }
    }

    /// The reading view's diagram for a Sankey diagram: drawn, or nil to show it as code when its links run in a
    /// circle or its front matter sets an option not drawn yet.
    static func diagram(source: String, diagram: SankeyDiagram, typography: DiagramTypography) -> ReadingDiagram? {
        guard let layout = try? SankeyLayoutEngine.layout(diagram, typography: typography) else { return nil } // Circular links or options: code.
        return .sankey(ReadingSankeyDiagram(diagram: diagram, layout: layout))
    }

    /// A value rounded to two decimals, a whole number without a fraction.
    private static func spoken(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() && rounded.magnitude < largestExactWholeNumber ? String(Int64(rounded)) : String(rounded)
    }

    /// 2⁵³: past it, a double holds no fraction and not every whole number.
    private static let largestExactWholeNumber = 9_007_199_254_740_992.0
}
