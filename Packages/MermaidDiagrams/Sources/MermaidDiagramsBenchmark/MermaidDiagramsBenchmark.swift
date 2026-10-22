import CoreGraphics
import Darwin
import Foundation
import MermaidDiagrams

/// Times reading, laying out and drawing flowcharts on the inputs of Pele's benchmark (`FlowchartCorpus`), and the
/// memory a layout holds. Each measurement repeats its work until about 300 ms have passed (at least 5 and at most
/// 2,000 runs, as Pele's benchmark does) and prints the median and the 99th percentile of one run, per diagram:
/// `swift run -c release --package-path Packages/MermaidDiagrams MermaidDiagramsBenchmark`.
@main
struct MermaidDiagramsBenchmark {
    static let timeBudget = Duration.milliseconds(300)
    static let minimumRunCount = 5
    static let maximumRunCount = 2_000
    /// Pele's text size.
    static let font = DiagramFont(postScriptName: nil, size: 16)
    /// How many layouts are kept while the heap's growth is measured.
    static let keptLayoutCount = 1_000

    static func main() throws {
        let typography = DiagramTypography(font: font)
        print("typography for one font: \(measure(perDiagramOf: 1) { _ = DiagramTypography(font: font) })")
        let documentationExamples = try FlowchartCorpus.documentationExamples()
        let drawable = documentationExamples.filter { source in (try? layout(source, typography)) != nil } // Subgraphs are not laid out yet.
        print("documentation examples drawn: \(drawable.count) of \(documentationExamples.count)")
        let cases: [(name: String, sources: [String])] = [
            ("documentation examples", drawable),
            ("7-node flowchart", [FlowchartCorpus.sevenNodeFlowchart]),
            ("tree, 50 nodes", [FlowchartCorpus.tree(nodeCount: 50)]),
            ("mesh, 50 nodes and 20 labelled edges", [FlowchartCorpus.mesh(nodeCount: 50, extraEdgeCount: 20)]),
            ("tree, 500 nodes", [FlowchartCorpus.tree(nodeCount: 500)]),
            ("mesh, 500 nodes and 200 labelled edges", [FlowchartCorpus.mesh(nodeCount: 500, extraEdgeCount: 200)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        for (name, source) in [("7-node flowchart", FlowchartCorpus.sevenNodeFlowchart), ("tree, 50 nodes", FlowchartCorpus.tree(nodeCount: 50))] {
            print("memory of one laid-out \(name): \(try heapGrowthPerLayout(of: source, typography: typography)) bytes")
        }
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = try diagrams.map { diagram in try FlowchartLayoutEngine.layout(diagram, typography: typography, limits: .standard) }
        let count = sources.count
        let reading = measure(perDiagramOf: count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(perDiagramOf: count) {
            for diagram in diagrams { _ = try? FlowchartLayoutEngine.layout(diagram, typography: typography, limits: .standard) } // Laid out above.
        }
        let both = measure(perDiagramOf: count) { for source in sources { _ = try? layout(source, typography) } } // Laid out above.
        let parts = measure(perDiagramOf: count) { for layout in layouts { _ = FlowchartDrawingParts(layout: layout) } }
        let contexts = layouts.map(bitmapContext)
        let painting = measure(perDiagramOf: count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { FlowchartRenderer.draw(layout, in: context, palette: palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func read(_ source: String) throws -> FlowchartDiagram {
        switch try MermaidDiagramReader.read(source, limits: .standard) {
        case .flowchart(let diagram): diagram
        case .entityRelationship: throw NotAFlowchart()
        }
    }

    /// A flowchart input that reads as another type of diagram.
    struct NotAFlowchart: Error {}

    private static func layout(_ source: String, _ typography: DiagramTypography) throws -> FlowchartLayout {
        try FlowchartLayoutEngine.layout(read(source), typography: typography, limits: .standard)
    }

    /// Runs `work` until the time budget is spent, and gives the median and the 99th percentile of one run divided
    /// by `diagramCount`, in microseconds.
    private static func measure(perDiagramOf diagramCount: Int, _ work: () -> Void) -> String {
        let clock = ContinuousClock()
        var samples: [Duration] = []
        var spent = Duration.zero
        work()
        while (spent < timeBudget || samples.count < minimumRunCount) && samples.count < maximumRunCount {
            let elapsed = clock.measure(work)
            samples.append(elapsed)
            spent += elapsed
        }
        samples.sort()
        func microseconds(_ duration: Duration) -> String {
            let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
            return String(format: "%.2f µs", seconds * 1e6 / Double(diagramCount))
        }
        let percentileIndex = min(samples.count - 1, Int((Double(samples.count) * 0.99).rounded(.up)) - 1)
        return "median \(microseconds(samples[samples.count / 2])), p99 \(microseconds(samples[percentileIndex])) (\(samples.count) runs)"
    }

    /// The growth of the heap's bytes in use while `keptLayoutCount` layouts of `source` are kept, per layout.
    private static func heapGrowthPerLayout(of source: String, typography: DiagramTypography) throws -> Int {
        let diagram = try read(source)
        var kept: [FlowchartLayout] = []
        kept.reserveCapacity(keptLayoutCount)
        let before = heapBytesInUse()
        for _ in 0..<keptLayoutCount { kept.append(try FlowchartLayoutEngine.layout(diagram, typography: typography, limits: .standard)) }
        let growth = heapBytesInUse() - before
        return kept.isEmpty ? 0 : growth / kept.count
    }

    private static func heapBytesInUse() -> Int {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return Int(statistics.size_in_use)
    }

    private static let palette = DiagramPalette(background: CGColor(gray: 1, alpha: 1), foreground: CGColor(gray: 0.12, alpha: 1),
                                                line: CGColor(gray: 0.12, alpha: 1), surface: CGColor(gray: 0.95, alpha: 1),
                                                border: CGColor(gray: 0.54, alpha: 1))

    /// A bitmap at two pixels per point, its y running down as a layout's does.
    private static func bitmapContext(for layout: FlowchartLayout) -> CGContext? {
        let scale: CGFloat = 2
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(layout.size.width * scale), height: Int(layout.size.height * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: layout.size.height * scale)
        context.scaleBy(x: scale, y: -scale)
        return context
    }
}
