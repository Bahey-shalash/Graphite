import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and drawing mindmaps on `MindmapCorpus`, with the median and the 99th percentile per
/// diagram, and the memory a layout holds, as the flowchart's benchmark does.
enum MindmapBenchmark {
    static func run(typography: DiagramTypography) throws {
        let examples = try MindmapCorpus.documentationExamples()
        let drawable = examples.filter { source in (try? read(source)) != nil } // The examples that do not read are counted below.
        print("mindmap documentation examples drawn: \(drawable.count) of \(examples.count)")
        let cases: [(name: String, sources: [String])] = [
            ("mindmap documentation examples", drawable),
            ("mindmap tree, 50 nodes", [MindmapCorpus.tree(nodeCount: 50)]),
            ("mindmap tree, 500 nodes", [MindmapCorpus.tree(nodeCount: 500)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let tree = try read(MindmapCorpus.tree(nodeCount: 50))
        let bytes = BenchmarkHeap.growth { MindmapLayoutEngine.layout(tree, typography: typography) }
        print("memory of one laid-out mindmap tree, 50 nodes: \(bytes) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = diagrams.map { diagram in MindmapLayoutEngine.layout(diagram, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) { for diagram in diagrams { _ = MindmapLayoutEngine.layout(diagram, typography: typography) } }
        let both = measure(count) {
            for source in sources { _ = (try? read(source)).map { diagram in MindmapLayoutEngine.layout(diagram, typography: typography) } } // Read above.
        }
        let parts = measure(count) { for layout in layouts { _ = MindmapDrawingParts(layout: layout) } }
        let contexts = layouts.map { layout in BenchmarkBitmap.context(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { MindmapRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func read(_ source: String) throws -> MindmapDiagram {
        guard case .mindmap(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotAMindmap() }
        return diagram
    }

    /// A text of the mindmap corpus that reads as another type.
    struct NotAMindmap: Error {}
}
