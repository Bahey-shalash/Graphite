import CoreGraphics
import MermaidDiagrams

/// The sequence diagram measurements of `MermaidDiagramsBenchmark`: the documentation examples that lay out,
/// the second of them alone (autonumber, an actor, aliases, an activation and a note over the four participants),
/// and a generated conversation of 200 messages, with the heap one laid-out example holds.
extension MermaidDiagramsBenchmark {
    static func reportSequenceDiagrams(typography: DiagramTypography) throws {
        let examples = try SequenceCorpus.documentationExamples()
        let drawable = examples.filter { source in (try? sequenceLayout(source, typography)) != nil } // Statements not laid out yet.
        print("sequence documentation examples drawn: \(drawable.count) of \(examples.count)")
        let typical = examples[1]
        let cases: [(name: String, sources: [String])] = [
            ("sequence documentation examples", drawable),
            ("sequence example with autonumber, an actor, an activation and a note", [typical]),
            ("sequence conversation, 10 participants and 200 messages", [SequenceCorpus.conversation(participantCount: 10, messageCount: 200)]),
        ]
        for (name, sources) in cases { try reportSequences(name, sources: sources, typography: typography) }
        print("memory of one laid-out sequence example: \(try sequenceHeapGrowthPerLayout(of: typical, typography: typography)) bytes")
    }

    private static func reportSequences(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(readSequence)
        let layouts = try diagrams.map { diagram in try SequenceLayoutEngine.layout(diagram, typography: typography) }
        let count = sources.count
        let reading = measure(perDiagramOf: count) { for source in sources { _ = try? readSequence(source) } } // Each read above.
        let layingOut = measure(perDiagramOf: count) {
            for diagram in diagrams { _ = try? SequenceLayoutEngine.layout(diagram, typography: typography) } // Laid out above.
        }
        let both = measure(perDiagramOf: count) { for source in sources { _ = try? sequenceLayout(source, typography) } } // Laid out above.
        let parts = measure(perDiagramOf: count) { for layout in layouts { _ = SequenceDrawingParts(layout: layout) } }
        let contexts = layouts.map { layout in bitmapContext(size: layout.size) }
        let painting = measure(perDiagramOf: count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { SequenceRenderer.draw(layout, in: context, palette: palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func readSequence(_ source: String) throws -> SequenceDiagram {
        guard case .sequence(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotASequenceDiagram() }
        return diagram
    }

    private static func sequenceLayout(_ source: String, _ typography: DiagramTypography) throws -> SequenceLayout {
        try SequenceLayoutEngine.layout(readSequence(source), typography: typography)
    }

    /// The growth of the heap's bytes in use while `keptLayoutCount` layouts of `source` are kept, per layout.
    private static func sequenceHeapGrowthPerLayout(of source: String, typography: DiagramTypography) throws -> Int {
        let diagram = try readSequence(source)
        var kept: [SequenceLayout] = []
        kept.reserveCapacity(keptLayoutCount)
        let before = heapBytesInUse()
        for _ in 0..<keptLayoutCount { kept.append(try SequenceLayoutEngine.layout(diagram, typography: typography)) }
        let growth = heapBytesInUse() - before
        return kept.isEmpty ? 0 : growth / kept.count
    }

    /// A sequence diagram input read as another type.
    struct NotASequenceDiagram: Error {}
}
