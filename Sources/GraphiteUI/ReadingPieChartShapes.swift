import SwiftUI
import MermaidDiagrams

/// A pie chart's shapes as SwiftUI paths and its text as placed lines, made off the main actor from the package's
/// `PieChartDrawingParts`, so that the view only paints them in the note's colors. Paths and text stay vector, on
/// screen and in a printed PDF, and draw without a `Canvas` and the graphics device a canvas starts.
struct ReadingPieChartShapes: Sendable {
    /// For each series color, the slices and legend swatches filled in it (`PieChartDrawingParts.seriesFills`).
    let seriesFills: [Path]
    /// The slices' edges, stroked in the background color.
    let sliceEdges: Path
    /// The pie's circle when no slice is drawn, stroked in the border color.
    let emptyPieOutline: Path
    /// The percentages inside their slices, drawn in the background color.
    let insidePercentageLines: [ReadingDiagramTextLine]
    /// The percentages outside the rim, the legend's labels and the title (bold, last), drawn in the text color.
    let textLines: [ReadingDiagramTextLine]

    init(parts: PieChartDrawingParts, font: DiagramFont) {
        seriesFills = parts.seriesFills.map { fill in Path(fill) }
        sliceEdges = Path(parts.sliceEdges)
        emptyPieOutline = Path(parts.emptyPieOutline)
        insidePercentageLines = parts.insidePercentages.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
        textLines = (parts.outsidePercentages + parts.legendTexts).flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
            + (parts.title.map { title in ReadingDiagramTextLine.lines(of: title, font: font, isBold: true) } ?? [])
    }
}
