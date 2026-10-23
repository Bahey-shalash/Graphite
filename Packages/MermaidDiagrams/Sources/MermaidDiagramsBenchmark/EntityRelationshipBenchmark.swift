import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and drawing entity relationship diagrams, as `MermaidDiagramsBenchmark` times
/// flowcharts: Mermaid's documentation examples that are laid out (those without subgraphs) and generated schemas,
/// with the median and the 99th percentile per diagram, and the heap a layout holds.
enum EntityRelationshipBenchmark {
    static func run(typography: DiagramTypography) throws {
        let examples = try EntityRelationshipCorpus.documentationExamples()
        let drawable = examples.filter { source in (try? layout(source, typography)) != nil } // Subgraphs are not laid out yet.
        print("entity relationship documentation examples drawn: \(drawable.count) of \(examples.count)")
        let cases: [(name: String, sources: [String])] = [
            ("entity relationship documentation examples", drawable),
            ("entity relationship schema, 10 tables", [EntityRelationshipCorpus.schema(entityCount: 10)]),
            ("entity relationship schema, 100 tables", [EntityRelationshipCorpus.schema(entityCount: 100)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let schema = EntityRelationshipCorpus.schema(entityCount: 10)
        print("memory of one laid-out entity relationship schema, 10 tables: \(try heapGrowthPerLayout(of: schema, typography: typography)) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = try diagrams.map { diagram in try EntityRelationshipLayoutEngine.layout(diagram, typography: typography, limits: .standard) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) {
            for diagram in diagrams { _ = try? EntityRelationshipLayoutEngine.layout(diagram, typography: typography, limits: .standard) } // Laid out above.
        }
        let both = measure(count) { for source in sources { _ = try? layout(source, typography) } } // Laid out above.
        let parts = measure(count) { for layout in layouts { _ = EntityRelationshipDrawingParts(layout: layout) } }
        let contexts = layouts.map { layout in MermaidDiagramsBenchmark.bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { EntityRelationshipRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func read(_ source: String) throws -> EntityRelationshipDiagram {
        guard case .entityRelationship(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotAnEntityRelationshipDiagram() }
        return diagram
    }

    private static func layout(_ source: String, _ typography: DiagramTypography) throws -> EntityRelationshipLayout {
        try EntityRelationshipLayoutEngine.layout(read(source), typography: typography, limits: .standard)
    }

    /// The growth of the heap's bytes in use while layouts of `source` are kept, per layout.
    private static func heapGrowthPerLayout(of source: String, typography: DiagramTypography) throws -> Int {
        let diagram = try read(source)
        var kept: [EntityRelationshipLayout] = []
        kept.reserveCapacity(MermaidDiagramsBenchmark.keptLayoutCount)
        let before = MermaidDiagramsBenchmark.heapBytesInUse()
        for _ in 0..<MermaidDiagramsBenchmark.keptLayoutCount {
            kept.append(try EntityRelationshipLayoutEngine.layout(diagram, typography: typography, limits: .standard))
        }
        let growth = MermaidDiagramsBenchmark.heapBytesInUse() - before
        return kept.isEmpty ? 0 : growth / kept.count
    }

    /// An input that reads as another type of diagram.
    struct NotAnEntityRelationshipDiagram: Error {}
}
