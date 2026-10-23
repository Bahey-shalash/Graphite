import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and drawing Git graphs on `GitGraphCorpus`, with the median and the 99th percentile per
/// diagram, and the memory a layout holds, as the flowchart's benchmark does.
enum GitGraphBenchmark {
    static func run(typography: DiagramTypography) throws {
        let examples = try GitGraphCorpus.documentationExamples()
        let drawable = examples.filter { source in (try? layout(read(source), typography)) != nil } // The rest set options, not applied.
        print("Git graph documentation examples drawn: \(drawable.count) of \(examples.count)")
        let cases: [(name: String, sources: [String])] = [
            ("Git graph documentation examples", drawable),
            ("Git graph, 10 feature branches", [GitGraphCorpus.generated(branchCount: 10)]),
            ("Git graph, 100 feature branches", [GitGraphCorpus.generated(branchCount: 100)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let generated = try read(GitGraphCorpus.generated(branchCount: 10))
        var kept: [GitGraphLayout] = []
        kept.reserveCapacity(MermaidDiagramsBenchmark.keptLayoutCount)
        let before = MermaidDiagramsBenchmark.heapBytesInUse()
        for _ in 0..<MermaidDiagramsBenchmark.keptLayoutCount { kept.append(try layout(generated, typography)) }
        let growth = MermaidDiagramsBenchmark.heapBytesInUse() - before
        print("memory of one laid-out Git graph, 10 feature branches: \(kept.isEmpty ? 0 : growth / kept.count) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = try diagrams.map { diagram in try layout(diagram, typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) { for diagram in diagrams { _ = try? layout(diagram, typography) } } // Each laid out above.
        let both = measure(count) { for source in sources { _ = try? layout(read(source), typography) } } // Each laid out above.
        let parts = measure(count) { for layout in layouts { _ = GitGraphDrawingParts(layout: layout) } }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting(layouts))")
    }

    /// The time to paint the layouts into bitmaps at two pixels per point, or why they are not painted.
    private static func painting(_ layouts: [GitGraphLayout]) -> String {
        guard layouts.allSatisfy({ layout in layout.size.width * layout.size.height * 4 <= maximumPaintedPixelCount }) else {
            return "not measured: the bitmap would be over \(Int(maximumPaintedPixelCount)) pixels"
        }
        let contexts = layouts.map { layout in MermaidDiagramsBenchmark.bitmapContext(size: layout.size) }
        return MermaidDiagramsBenchmark.measure(perDiagramOf: layouts.count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { GitGraphRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
    }

    /// The largest bitmap painted, 16 million pixels: a graph wider than a page, painted, measures the bitmap's fill.
    static let maximumPaintedPixelCount: CGFloat = 16_000_000

    private static func read(_ source: String) throws -> GitGraphDiagram {
        guard case .gitGraph(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotAGitGraph() }
        return diagram
    }

    private static func layout(_ diagram: GitGraphDiagram, _ typography: DiagramTypography) throws -> GitGraphLayout {
        try GitGraphLayoutEngine.layout(diagram, typography: typography)
    }

    /// A text of the Git graph corpus that reads as another type.
    struct NotAGitGraph: Error {}
}
