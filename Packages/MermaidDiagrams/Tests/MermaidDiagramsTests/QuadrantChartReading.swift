@testable import MermaidDiagrams

/// Reads a quadrant chart for a test, from its whole text.
enum QuadrantChartReading {
    static func quadrantChart(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> QuadrantChart {
        try QuadrantChartParser.parse(cursorAfterKeyword(source), limits: limits)
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try quadrantChart(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    /// The first example of Mermaid's quadrant chart documentation.
    static let reachAndEngagement = """
    quadrantChart
        title Reach and engagement of campaigns
        x-axis Low Reach --> High Reach
        y-axis Low Engagement --> High Engagement
        quadrant-1 We should expand
        quadrant-2 Need to promote
        quadrant-3 Re-evaluate
        quadrant-4 May be improved
        Campaign A: [0.3, 0.6]
        Campaign B: [0.45, 0.23]
        Campaign C: [0.57, 0.69]
        Campaign D: [0.78, 0.34]
        Campaign E: [0.40, 0.34]
        Campaign F: [0.35, 0.78]
    """

    /// The quadrant chart of `source` laid out with text of fixed widths: quadrants 8 points a character at 16 points
    /// (24-point lines), axes 7 at 14 (21), points 6 at 12 (18), the title 8 at 16.
    static func uniformLayout(_ source: String) throws -> QuadrantChartLayout {
        QuadrantChartLayoutEngine.layout(try quadrantChart(source), quadrantText: UniformWidthTextMeasurer(),
                                         axisText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                         pointText: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 12, lineHeight: 18),
                                         titleText: UniformWidthTextMeasurer(), font: DiagramFont(postScriptName: nil, size: 16))
    }

    /// A cursor just past the `quadrantChart` keyword that every test text starts with.
    private static func cursorAfterKeyword(_ source: String) -> MermaidTextCursor {
        var cursor = MermaidTextCursor(bytes: Array(source.utf8))
        cursor.skipWhitespace()
        precondition(cursor.readWord() == "quadrantChart", "A quadrant chart's text starts with its keyword")
        return cursor
    }
}
