import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and drawing class diagrams, as the flowchart's are timed: Mermaid's documentation
/// examples that are laid out (those with namespaces are not yet), Pele's four-class diagram and generated
/// hierarchies, and the memory a layout holds.
extension MermaidDiagramsBenchmark {
    static func reportClassDiagrams(typography: DiagramTypography) throws {
        let documentationExamples = try ClassDiagramCorpus.documentationExamples()
        let drawable = documentationExamples.filter { source in (try? classLayout(source, typography)) != nil } // Namespaces are not laid out yet.
        print("class diagram documentation examples drawn: \(drawable.count) of \(documentationExamples.count)")
        let cases: [(name: String, sources: [String])] = [
            ("class diagram documentation examples", drawable),
            ("4-class diagram", [ClassDiagramCorpus.fourClassDiagram]),
            ("class hierarchy, 50 classes", [ClassDiagramCorpus.hierarchy(classCount: 50)]),
            ("class hierarchy, 250 classes", [ClassDiagramCorpus.hierarchy(classCount: 250)]),
        ]
        for (name, sources) in cases { try reportClassDiagrams(name, sources: sources, typography: typography) }
        let diagram = try readClassDiagram(ClassDiagramCorpus.fourClassDiagram)
        var kept: [ClassDiagramLayout] = []
        kept.reserveCapacity(keptLayoutCount)
        let before = heapBytesInUse()
        for _ in 0..<keptLayoutCount { kept.append(try ClassDiagramLayoutEngine.layout(diagram, typography: typography, limits: .standard)) }
        print("memory of one laid-out 4-class diagram: \((heapBytesInUse() - before) / kept.count) bytes")
    }

    private static func reportClassDiagrams(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(readClassDiagram)
        let layouts = try diagrams.map { diagram in try ClassDiagramLayoutEngine.layout(diagram, typography: typography, limits: .standard) }
        let count = sources.count
        let reading = measure(perDiagramOf: count) { for source in sources { _ = try? readClassDiagram(source) } } // Each read above.
        let layingOut = measure(perDiagramOf: count) {
            for diagram in diagrams { _ = try? ClassDiagramLayoutEngine.layout(diagram, typography: typography, limits: .standard) } // Laid out above.
        }
        let both = measure(perDiagramOf: count) { for source in sources { _ = try? classLayout(source, typography) } } // Laid out above.
        let parts = measure(perDiagramOf: count) { for layout in layouts { _ = ClassDiagramDrawingParts(layout: layout) } }
        let contexts = layouts.compactMap { layout in bitmapContext(size: layout.size) }
        let painting = contexts.count < layouts.count ? "not measured (a bitmap past \(maximumPaintedPixelCount) pixels)" : measure(perDiagramOf: count) {
            for (layout, context) in zip(layouts, contexts) { ClassDiagramRenderer.draw(layout, in: context, palette: classPalette) }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func readClassDiagram(_ source: String) throws -> ClassDiagram {
        guard case .classDiagram(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotAClassDiagram() }
        return diagram
    }

    private static func classLayout(_ source: String, _ typography: DiagramTypography) throws -> ClassDiagramLayout {
        try ClassDiagramLayoutEngine.layout(readClassDiagram(source), typography: typography, limits: .standard)
    }

    /// A class diagram's input read as a diagram of another type.
    struct NotAClassDiagram: Error {}

    private static let classPalette = ClassDiagramPalette(diagram: palette, muted: CGColor(gray: 0.43, alpha: 1), noteSurface: CGColor(gray: 0.9, alpha: 1))

    /// The largest bitmap painted into: a wide generated hierarchy would take more memory than the Mac has.
    static let maximumPaintedPixelCount = 16_000_000

    /// A bitmap at two pixels per point, its y running down as a layout's does, or nil past the largest painted.
    private static func bitmapContext(size: CGSize) -> CGContext? {
        let scale: CGFloat = 2
        guard Int(size.width * scale) * Int(size.height * scale) <= maximumPaintedPixelCount, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -scale)
        return context
    }
}
