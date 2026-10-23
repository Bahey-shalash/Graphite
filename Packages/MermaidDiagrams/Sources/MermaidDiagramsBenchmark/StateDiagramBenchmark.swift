import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and drawing state diagrams (`StateDiagramCorpus`), and the memory a layout holds, as
/// `MermaidDiagramsBenchmark` does for flowcharts.
enum StateDiagramBenchmark {
    static func run(typography: DiagramTypography) throws {
        let documentationExamples = try StateDiagramCorpus.documentationExamples()
        let drawable = documentationExamples.filter { source in (try? layout(source, typography)) != nil } // Composite states are not laid out yet.
        print("state documentation examples drawn: \(drawable.count) of \(documentationExamples.count)")
        let cases: [(name: String, sources: [String])] = [
            ("state documentation examples", drawable),
            ("state machine, 50 states and 20 labelled transitions", [StateDiagramCorpus.machine(stateCount: 50, extraTransitionCount: 20)]),
            ("state machine, 500 states and 200 labelled transitions", [StateDiagramCorpus.machine(stateCount: 500, extraTransitionCount: 200)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let memoryCases = [("first state documentation example", try StateDiagramCorpus.firstDocumentationExample),
                           ("state machine, 50 states", StateDiagramCorpus.machine(stateCount: 50, extraTransitionCount: 20))]
        for (name, source) in memoryCases {
            print("memory of one laid-out \(name): \(try heapGrowthPerLayout(of: source, typography: typography)) bytes")
        }
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = try diagrams.map { diagram in try StateDiagramLayoutEngine.layout(diagram, typography: typography, limits: .standard) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) {
            for diagram in diagrams { _ = try? StateDiagramLayoutEngine.layout(diagram, typography: typography, limits: .standard) } // Laid out above.
        }
        let both = measure(count) { for source in sources { _ = try? layout(source, typography) } } // Laid out above.
        let parts = measure(count) { for layout in layouts { _ = StateDiagramDrawingParts(layout: layout) } }
        let contexts = layouts.map { layout in MermaidDiagramsBenchmark.bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { StateDiagramRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func read(_ source: String) throws -> StateDiagram {
        guard case .stateDiagram(let diagram) = try MermaidDiagramReader.read(source, limits: .standard)
        else { throw MermaidDiagramsBenchmark.UnexpectedDiagramType() }
        return diagram
    }

    private static func layout(_ source: String, _ typography: DiagramTypography) throws -> StateDiagramLayout {
        try StateDiagramLayoutEngine.layout(read(source), typography: typography, limits: .standard)
    }

    /// The growth of the heap's bytes in use while `keptLayoutCount` layouts of `source` are kept, per layout.
    private static func heapGrowthPerLayout(of source: String, typography: DiagramTypography) throws -> Int {
        let diagram = try read(source)
        var kept: [StateDiagramLayout] = []
        kept.reserveCapacity(MermaidDiagramsBenchmark.keptLayoutCount)
        let before = MermaidDiagramsBenchmark.heapBytesInUse()
        for _ in 0..<MermaidDiagramsBenchmark.keptLayoutCount {
            kept.append(try StateDiagramLayoutEngine.layout(diagram, typography: typography, limits: .standard))
        }
        let growth = MermaidDiagramsBenchmark.heapBytesInUse() - before
        return kept.isEmpty ? 0 : growth / kept.count
    }
}
