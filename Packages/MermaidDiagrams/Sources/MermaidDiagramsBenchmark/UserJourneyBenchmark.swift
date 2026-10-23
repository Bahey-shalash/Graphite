import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and drawing user journeys on `UserJourneyCorpus`, with the median and the 99th
/// percentile per diagram, and the memory a layout holds, as the flowchart's benchmark does.
enum UserJourneyBenchmark {
    static func run(typography: DiagramTypography) throws {
        let cases: [(name: String, sources: [String])] = [
            ("user journey documentation example", try UserJourneyCorpus.documentationExamples()),
            ("user journey, 20 tasks", [UserJourneyCorpus.generated(taskCount: 20)]),
            ("user journey, 200 tasks", [UserJourneyCorpus.generated(taskCount: 200)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let generated = try read(UserJourneyCorpus.generated(taskCount: 20))
        let bytes = BenchmarkHeap.growth { UserJourneyLayoutEngine.layout(generated, typography: typography) }
        print("memory of one laid-out user journey, 20 tasks: \(bytes) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = diagrams.map { diagram in UserJourneyLayoutEngine.layout(diagram, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) { for diagram in diagrams { _ = UserJourneyLayoutEngine.layout(diagram, typography: typography) } }
        let both = measure(count) {
            for source in sources { _ = (try? read(source)).map { diagram in UserJourneyLayoutEngine.layout(diagram, typography: typography) } } // Read above.
        }
        let parts = measure(count) { for layout in layouts { _ = UserJourneyDrawingParts(layout: layout) } }
        let contexts = layouts.map { layout in MermaidDiagramsBenchmark.bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { UserJourneyRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func read(_ source: String) throws -> UserJourneyDiagram {
        guard case .userJourney(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotAUserJourney() }
        return diagram
    }

    /// A text of the user journey corpus that reads as another type.
    struct NotAUserJourney: Error {}
}
