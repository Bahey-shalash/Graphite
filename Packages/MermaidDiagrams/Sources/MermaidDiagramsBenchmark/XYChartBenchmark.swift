import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and drawing XY charts on `XYChartCorpus`, with the median and the 99th percentile per
/// diagram, and the memory a layout holds, as the flowchart's benchmark does.
enum XYChartBenchmark {
    static func run(typography: DiagramTypography) throws {
        let cases: [(name: String, sources: [String])] = [
            ("XY chart documentation examples", try XYChartCorpus.documentationExamples()),
            ("XY chart, 12 categories and 2 series", [XYChartCorpus.generated(categoryCount: 12, seriesCount: 2)]),
            ("XY chart, 100 categories and 4 series", [XYChartCorpus.generated(categoryCount: 100, seriesCount: 4)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let generated = try read(XYChartCorpus.generated(categoryCount: 12, seriesCount: 2))
        let bytes = BenchmarkHeap.growth { try? XYChartLayoutEngine.layout(generated, typography: typography) } // Laid out above.
        print("memory of one laid-out XY chart, 12 categories and 2 series: \(bytes) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let charts = try sources.map(read)
        let layouts = try charts.map { chart in try XYChartLayoutEngine.layout(chart, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) { for chart in charts { _ = try? XYChartLayoutEngine.layout(chart, typography: typography) } } // Laid out above.
        let both = measure(count) {
            for source in sources { _ = (try? read(source)).map { chart in try? XYChartLayoutEngine.layout(chart, typography: typography) } } // Above.
        }
        let parts = measure(count) { for layout in layouts { _ = XYChartDrawingParts(layout: layout) } }
        let contexts = layouts.map { layout in MermaidDiagramsBenchmark.bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { XYChartRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func read(_ source: String) throws -> XYChart {
        guard case .xyChart(let chart) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotAnXYChart() }
        return chart
    }

    /// A text of the XY chart corpus that reads as another type.
    struct NotAnXYChart: Error {}
}
