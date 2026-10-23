import SwiftUI
import MermaidDiagrams

/// A quadrant chart's shapes as SwiftUI paths and its text as placed lines, made off the main actor from the package's
/// `QuadrantChartDrawingParts`, so that the view only paints them: the points in Pele's first series color or the
/// colors the chart writes, the rest in the note's colors. Paths and text stay vector, on screen and in a printed PDF,
/// and draw without a `Canvas`.
struct ReadingQuadrantChartShapes: Sendable {
    /// Points painted alike (`QuadrantChartDrawingParts.PointGroup`), back to front.
    struct PointGroup: Sendable {
        let circles: Path
        let fill: QuadrantChartPaint
        let stroke: QuadrantChartStroke?
    }

    let quadrants: Path
    let pointGroups: [PointGroup]
    /// The quadrants' texts, the points' texts and the title (bold, last), in the text color.
    let textLines: [ReadingDiagramTextLine]
    /// The x axis's texts, in the muted color.
    let axisTextLines: [ReadingDiagramTextLine]
    /// The y axis's texts, in the muted color, each line turned a quarter anticlockwise about its own middle, which is
    /// where the turned text puts it.
    let turnedAxisTextLines: [ReadingDiagramTextLine]

    init(parts: QuadrantChartDrawingParts, font: DiagramFont) {
        quadrants = Path(parts.quadrants)
        pointGroups = parts.pointGroups.map { group in PointGroup(circles: Path(group.circles), fill: group.fill, stroke: group.stroke) }
        textLines = (parts.quadrantTexts + parts.pointTexts).flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
            + (parts.title.map { title in ReadingDiagramTextLine.lines(of: title, font: font, isBold: true) } ?? [])
        axisTextLines = parts.axisTexts.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
        turnedAxisTextLines = parts.turnedAxisTexts.flatMap { block in Self.turnedLines(of: block, font: font) }
    }

    /// A turned text's lines, each moved to where turning the block a quarter anticlockwise about its middle puts it:
    /// a line below the middle in the text goes right of it on the page.
    private static func turnedLines(of block: DiagramTextBlock, font: DiagramFont) -> [ReadingDiagramTextLine] {
        ReadingDiagramTextLine.lines(of: block, font: font, isBold: false).map { line in
            ReadingDiagramTextLine(text: line.text, center: CGPoint(x: block.center.x + line.center.y - block.center.y, y: block.center.y), font: line.font,
                                   isBold: line.isBold)
        }
    }
}
