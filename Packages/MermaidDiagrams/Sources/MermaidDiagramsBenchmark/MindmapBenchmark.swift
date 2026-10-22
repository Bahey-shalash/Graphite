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
        print("memory of one laid-out mindmap tree, 50 nodes: \(heapGrowthPerLayout(of: tree, typography: typography)) bytes")
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
        let contexts = layouts.map { layout in bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { MindmapRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func read(_ source: String) throws -> MindmapDiagram {
        switch try MermaidDiagramReader.read(source, limits: .standard) {
        case .mindmap(let diagram): diagram
        case .flowchart: throw NotAMindmap()
        }
    }

    /// A text of the mindmap corpus that reads as another type.
    struct NotAMindmap: Error {}

    /// The growth of the heap's bytes in use while `MermaidDiagramsBenchmark.keptLayoutCount` layouts are kept, per layout.
    private static func heapGrowthPerLayout(of diagram: MindmapDiagram, typography: DiagramTypography) -> Int {
        var kept: [MindmapLayout] = []
        kept.reserveCapacity(MermaidDiagramsBenchmark.keptLayoutCount)
        let before = MermaidDiagramsBenchmark.heapBytesInUse()
        for _ in 0..<MermaidDiagramsBenchmark.keptLayoutCount { kept.append(MindmapLayoutEngine.layout(diagram, typography: typography)) }
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
