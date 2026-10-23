import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and drawing pie charts (`PieChartCorpus`), and the memory a layout holds, as
/// `MermaidDiagramsBenchmark` does for flowcharts.
enum PieChartBenchmark {
    static func run(typography: DiagramTypography) throws {
        let cases: [(name: String, sources: [String])] = [
            ("pie documentation examples", try PieChartCorpus.documentationExamples()),
            ("pie, 8 slices", [PieChartCorpus.pie(sliceCount: 8)]),
            ("pie, 100 slices", [PieChartCorpus.pie(sliceCount: 100)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        print("memory of one laid-out pie of 8 slices: \(try heapGrowthPerLayout(of: PieChartCorpus.pie(sliceCount: 8), typography: typography)) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let charts = try sources.map(read)
        let layouts = charts.map { chart in PieChartLayoutEngine.layout(chart, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) { for chart in charts { _ = PieChartLayoutEngine.layout(chart, typography: typography) } }
        let both = measure(count) {
            for source in sources { _ = (try? read(source)).map { chart in PieChartLayoutEngine.layout(chart, typography: typography) } } // Read above.
        }
        let parts = measure(count) { for layout in layouts { _ = PieChartDrawingParts(layout: layout) } }
        let contexts = layouts.map { layout in bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { PieChartRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func read(_ source: String) throws -> PieChart {
        guard case .pieChart(let chart) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotAPieChart() }
        return chart
    }

    /// A pie chart input read as another type.
    struct NotAPieChart: Error {}

    /// The growth of the heap's bytes in use while `MermaidDiagramsBenchmark.keptLayoutCount` layouts are kept, per layout.
    private static func heapGrowthPerLayout(of source: String, typography: DiagramTypography) throws -> Int {
        let chart = try read(source)
        var kept: [PieChartLayout] = []
        kept.reserveCapacity(MermaidDiagramsBenchmark.keptLayoutCount)
        let before = MermaidDiagramsBenchmark.heapBytesInUse()
        for _ in 0..<MermaidDiagramsBenchmark.keptLayoutCount { kept.append(PieChartLayoutEngine.layout(chart, typography: typography)) }
        let growth = MermaidDiagramsBenchmark.heapBytesInUse() - before
        return kept.isEmpty ? 0 : growth / kept.count
    }

    /// A bitmap at two pixels per point, its y running down as a layout's does.
    private static func bitmapContext(size: CGSize) -> CGContext? {
        let scale: CGFloat = 2
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -scale)
        return context
    }
}
