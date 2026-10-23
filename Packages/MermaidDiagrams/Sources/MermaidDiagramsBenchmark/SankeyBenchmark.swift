import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and drawing Sankey diagrams on `SankeyCorpus`, with the median and the 99th percentile per
/// diagram, and the memory a layout holds, as the flowchart's benchmark does.
enum SankeyBenchmark {
    /// Fewer lines than this make one of the documentation's small examples; the energy flows have more.
    static let smallExampleLineCount = 20

    static func run(typography: DiagramTypography) throws {
        let examples = try SankeyCorpus.documentationExamples()
        let drawable = examples.filter { source in (try? layout(source, typography: typography)) != nil } // Options not drawn are counted below.
        print("Sankey documentation examples drawn: \(drawable.count) of \(examples.count)")
        let cases: [(name: String, sources: [String])] = [
            ("Sankey documentation examples of 2 or 3 rows", drawable.filter { source in source.split(separator: "\n").count < smallExampleLineCount }),
            ("Sankey documentation example of 68 rows", drawable.filter { source in source.split(separator: "\n").count >= smallExampleLineCount }),
            ("Sankey energy flows, 70 links", ["sankey-beta\n\n " + (try SankeyCorpus.energyRows())]),
            ("Sankey, 5 layers of 10 nodes", [SankeyCorpus.generated(layerCount: 5, nodesPerLayer: 10)]),
            ("Sankey, 10 layers of 30 nodes", [SankeyCorpus.generated(layerCount: 10, nodesPerLayer: 30)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let generated = try read(SankeyCorpus.generated(layerCount: 5, nodesPerLayer: 10))
        let bytes = BenchmarkHeap.growth { try? SankeyLayoutEngine.layout(generated, typography: typography) } // Laid out above.
        print("memory of one laid-out Sankey diagram, 5 layers of 10 nodes: \(bytes) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = try diagrams.map { diagram in try SankeyLayoutEngine.layout(diagram, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) { for diagram in diagrams { _ = try? SankeyLayoutEngine.layout(diagram, typography: typography) } } // Above.
        let both = measure(count) { for source in sources { _ = try? layout(source, typography: typography) } } // Laid out above.
        let parts = measure(count) { for layout in layouts { _ = SankeyDrawingParts(layout: layout) } }
        let contexts = layouts.map { layout in MermaidDiagramsBenchmark.bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { SankeyRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func layout(_ source: String, typography: DiagramTypography) throws -> SankeyLayout {
        try SankeyLayoutEngine.layout(read(source), typography: typography)
    }

    private static func read(_ source: String) throws -> SankeyDiagram {
        guard case .sankey(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotASankeyDiagram() }
        return diagram
    }

    /// A text of the Sankey corpus that reads as another type.
    struct NotASankeyDiagram: Error {}
}
