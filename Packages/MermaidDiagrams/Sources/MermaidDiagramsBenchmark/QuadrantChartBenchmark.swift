import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and drawing quadrant charts on `QuadrantChartCorpus`, with the median and the 99th
/// percentile per diagram, and the memory a layout holds, as the flowchart's benchmark does. The 300-point chart is the
/// largest whose points' texts are kept apart; above it the search is skipped.
enum QuadrantChartBenchmark {
    static func run(typography: DiagramTypography) throws {
        let cases: [(name: String, sources: [String])] = [
            ("quadrant chart documentation examples", try QuadrantChartCorpus.documentationExamples()),
            ("quadrant chart, 20 points", [QuadrantChartCorpus.generated(pointCount: 20)]),
            ("quadrant chart, 300 points", [QuadrantChartCorpus.generated(pointCount: 300)]),
            ("quadrant chart, 1,000 points", [QuadrantChartCorpus.generated(pointCount: 1_000)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let generated = try read(QuadrantChartCorpus.generated(pointCount: 20))
        let bytes = BenchmarkHeap.growth { QuadrantChartLayoutEngine.layout(generated, typography: typography) }
        print("memory of one laid-out quadrant chart, 20 points: \(bytes) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let charts = try sources.map(read)
        let layouts = charts.map { chart in QuadrantChartLayoutEngine.layout(chart, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) { for chart in charts { _ = QuadrantChartLayoutEngine.layout(chart, typography: typography) } }
        let both = measure(count) {
            for source in sources { _ = (try? read(source)).map { chart in QuadrantChartLayoutEngine.layout(chart, typography: typography) } } // Read above.
        }
        let parts = measure(count) { for layout in layouts { _ = QuadrantChartDrawingParts(layout: layout) } }
        let contexts = layouts.map { layout in MermaidDiagramsBenchmark.bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { QuadrantChartRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func read(_ source: String) throws -> QuadrantChart {
        guard case .quadrantChart(let chart) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotAQuadrantChart() }
        return chart
    }

    /// A text of the quadrant chart corpus that reads as another type.
    struct NotAQuadrantChart: Error {}
}
