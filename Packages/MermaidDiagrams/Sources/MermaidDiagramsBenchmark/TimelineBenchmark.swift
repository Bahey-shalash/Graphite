import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and drawing timelines on `TimelineCorpus`, with the median and the 99th percentile per
/// diagram, and the memory a layout holds, as the flowchart's benchmark does.
enum TimelineBenchmark {
    static func run(typography: DiagramTypography) throws {
        let examples = try TimelineCorpus.documentationExamples()
        let drawable = examples.filter { source in (try? read(source)) != nil } // The examples that do not read are counted below.
        print("timeline documentation examples drawn: \(drawable.count) of \(examples.count)")
        let cases: [(name: String, sources: [String])] = [
            ("timeline documentation examples", drawable),
            ("timeline, 20 periods across", [TimelineCorpus.generated(periodCount: 20)]),
            ("timeline, 20 periods down", [TimelineCorpus.generated(periodCount: 20, isDown: true)]),
            ("timeline, 200 periods across", [TimelineCorpus.generated(periodCount: 200)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let generated = try read(TimelineCorpus.generated(periodCount: 20))
        let bytes = BenchmarkHeap.growth { TimelineLayoutEngine.layout(generated, typography: typography) }
        print("memory of one laid-out timeline, 20 periods: \(bytes) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = diagrams.map { diagram in TimelineLayoutEngine.layout(diagram, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) { for diagram in diagrams { _ = TimelineLayoutEngine.layout(diagram, typography: typography) } }
        let both = measure(count) {
            for source in sources { _ = (try? read(source)).map { diagram in TimelineLayoutEngine.layout(diagram, typography: typography) } } // Read above.
        }
        let parts = measure(count) { for layout in layouts { _ = TimelineDrawingParts(layout: layout) } }
        let contexts = layouts.map { layout in BenchmarkBitmap.context(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { TimelineRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func read(_ source: String) throws -> TimelineDiagram {
        switch try MermaidDiagramReader.read(source, limits: .standard) {
        case .timeline(let diagram): diagram
        case .flowchart, .mindmap: throw NotATimeline()
        }
    }

    /// A text of the timeline corpus that reads as another type.
    struct NotATimeline: Error {}
}
