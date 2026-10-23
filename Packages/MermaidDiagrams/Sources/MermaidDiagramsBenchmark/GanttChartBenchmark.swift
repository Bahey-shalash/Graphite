import CoreGraphics
import MermaidDiagrams

/// Times reading, scheduling and laying out, and drawing Gantt charts (`GanttChartCorpus`), and the memory a layout
/// holds, as `MermaidDiagramsBenchmark` does for flowcharts.
enum GanttChartBenchmark {
    static func run(typography: DiagramTypography) throws {
        let examples = try GanttChartCorpus.documentationExamples()
        let drawable = examples.filter { source in (try? layout(source, typography)) != nil } // Charts with vert tasks are not drawn yet.
        print("Gantt documentation examples drawn: \(drawable.count) of \(examples.count)")
        let cases: [(name: String, sources: [String])] = [
            ("Gantt documentation examples", drawable),
            ("Gantt, 20 tasks", [GanttChartCorpus.chart(taskCount: 20)]),
            ("Gantt, 200 tasks", [GanttChartCorpus.chart(taskCount: 200)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let heap = try heapGrowthPerLayout(of: GanttChartCorpus.chart(taskCount: 20), typography: typography)
        print("memory of one laid-out Gantt chart of 20 tasks: \(heap) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let charts = try sources.map(read)
        let layouts = try charts.map { chart in try lay(chart, typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) { for chart in charts { _ = try? lay(chart, typography) } } // Laid out above.
        let both = measure(count) { for source in sources { _ = try? layout(source, typography) } } // Laid out above.
        let parts = measure(count) { for layout in layouts { _ = GanttDrawingParts(layout: layout) } }
        let contexts = layouts.map { layout in bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { GanttRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); schedule and layout \(layingOut); both \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func read(_ source: String) throws -> GanttChart {
        guard case .ganttChart(let chart) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotAGanttChart() }
        return chart
    }

    private static func lay(_ chart: GanttChart, _ typography: DiagramTypography) throws -> GanttLayout {
        try GanttLayoutEngine.layout(chart, typography: typography, now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone, limits: .standard)
    }

    private static func layout(_ source: String, _ typography: DiagramTypography) throws -> GanttLayout {
        try lay(read(source), typography)
    }

    /// A Gantt chart input read as another type.
    struct NotAGanttChart: Error {}

    /// The growth of the heap's bytes in use while `MermaidDiagramsBenchmark.keptLayoutCount` layouts are kept, per layout.
    private static func heapGrowthPerLayout(of source: String, typography: DiagramTypography) throws -> Int {
        let chart = try read(source)
        var kept: [GanttLayout] = []
        kept.reserveCapacity(MermaidDiagramsBenchmark.keptLayoutCount)
        let before = MermaidDiagramsBenchmark.heapBytesInUse()
        for _ in 0..<MermaidDiagramsBenchmark.keptLayoutCount { kept.append(try lay(chart, typography)) }
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
