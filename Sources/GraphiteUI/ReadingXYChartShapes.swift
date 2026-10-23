import SwiftUI
import MermaidDiagrams

/// An XY chart's shapes as SwiftUI paths and its text as placed lines, made off the main actor from the package's
/// `XYChartDrawingParts`, so that the view only paints them in the note's colors. Paths and text stay vector, on
/// screen and in a printed PDF, and draw without a `Canvas` and the graphics device a canvas starts.
struct ReadingXYChartShapes: Sendable {
    /// A line series' line and legend swatch, and its dots, in its series color.
    struct Line: Sendable {
        let seriesIndex: Int
        let stroke: Path
        let dots: Path
    }

    /// The grid, stroked in the alternate surface color.
    let gridLines: Path
    /// For each series color, the bars and bar swatches filled in it (`XYChartDrawingParts.barFills`).
    let barFills: [Path]
    let lines: [Line]
    /// The axes, ticks and the line bars stand on, stroked in the border color.
    let axisLines: Path
    /// The marks' labels, in the muted color.
    let axisLabelLines: [ReadingDiagramTextLine]
    /// The bottom axis' title, point labels, legend titles and the title (bold, last), in the text color.
    let textLines: [ReadingDiagramTextLine]
    /// The left axis' title, each line turned a quarter turn counterclockwise about its own center, which is where
    /// the turned block puts it.
    let turnedTextLines: [ReadingDiagramTextLine]

    init(parts: XYChartDrawingParts, font: DiagramFont) {
        gridLines = Path(parts.gridLines)
        barFills = parts.barFills.map { fill in Path(fill) }
        lines = parts.lines.map { line in Line(seriesIndex: line.seriesIndex, stroke: Path(line.stroke), dots: Path(line.dots)) }
        axisLines = Path(parts.axisLines)
        axisLabelLines = parts.axisLabels.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
        textLines = parts.texts.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
            + (parts.title.map { title in ReadingDiagramTextLine.lines(of: title, font: font, isBold: true) } ?? [])
        turnedTextLines = parts.turnedText.map { block in Self.turnedLines(of: block, font: font) } ?? []
    }

    /// The lines of `block` turned a quarter turn counterclockwise about its center: a line below another in the
    /// block is right of it once turned.
    private static func turnedLines(of block: DiagramTextBlock, font: DiagramFont) -> [ReadingDiagramTextLine] {
        ReadingDiagramTextLine.lines(of: block, font: font, isBold: false).map { line in
            let offset = CGVector(dx: line.center.x - block.center.x, dy: line.center.y - block.center.y)
            return ReadingDiagramTextLine(text: line.text, center: CGPoint(x: block.center.x + offset.dy, y: block.center.y - offset.dx),
                                          font: line.font, isBold: line.isBold)
        }
    }
}
