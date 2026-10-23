import SwiftUI
import MermaidDiagrams

/// A flowchart's shapes as SwiftUI paths and its text as placed lines, made off the main actor from the package's
/// `FlowchartDrawingParts`, so that the view only paints them in the note's colors. Paths and text stay vector, on
/// screen and in a printed PDF, and draw without a `Canvas` and the graphics device a canvas starts.
struct ReadingFlowchartShapes: Sendable {
    /// The groups' boxes, painted first, and the titles edges cross, painted over the edges.
    let clusters: ReadingFlowchartClusterShapes
    let solidEdges: Path
    let thickEdges: Path
    let dottedEdges: Path
    let filledMarks: Path
    let strokedMarks: Path
    let edgeTextPatches: Path
    let nodeFills: Path
    let nodeOutlines: Path
    /// Edge text, drawn over the patches and under the nodes.
    let edgeTextLines: [ReadingDiagramTextLine]
    /// Node text and the title, drawn last.
    let nodeTextLines: [ReadingDiagramTextLine]

    init(parts: FlowchartDrawingParts, font: DiagramFont) {
        clusters = ReadingFlowchartClusterShapes(parts: parts.clusters, font: font)
        solidEdges = Path(parts.solidEdges)
        thickEdges = Path(parts.thickEdges)
        dottedEdges = Path(parts.dottedEdges)
        filledMarks = Path(parts.filledMarks)
        strokedMarks = Path(parts.strokedMarks)
        edgeTextPatches = Path(parts.edgeTextPatches)
        nodeFills = Path(parts.nodeFills)
        nodeOutlines = Path(parts.nodeOutlines)
        edgeTextLines = parts.edgeTexts.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
        nodeTextLines = parts.nodeTexts.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
            + (parts.title.map { title in ReadingDiagramTextLine.lines(of: title, font: font, isBold: true) } ?? [])
    }
}

/// One line of a diagram's text: what it says, the center of its line box, and its font.
struct ReadingDiagramTextLine: Sendable {
    let text: String
    let center: CGPoint
    let font: DiagramFont
    let isBold: Bool

    static func lines(of block: DiagramTextBlock, font: DiagramFont, isBold: Bool) -> [ReadingDiagramTextLine] {
        let top = block.center.y - block.size.height / 2
        let lineFont = DiagramFont(postScriptName: font.postScriptName, size: block.fontSize)
        return block.lines.enumerated().map { index, line in
            ReadingDiagramTextLine(text: line, center: CGPoint(x: block.center.x, y: top + (CGFloat(index) + 0.5) * block.lineHeight),
                                   font: lineFont, isBold: isBold)
        }
    }

    /// The SwiftUI font the line was measured in: the system font, or the installed font by its PostScript name.
    var swiftUIFont: Font {
        let font = self.font.postScriptName.map { name in Font.custom(name, fixedSize: self.font.size) } ?? .system(size: self.font.size)
        return isBold ? font.bold() : font
    }
}
