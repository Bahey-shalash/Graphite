import SwiftUI
import MermaidDiagrams

/// A Sankey diagram's shapes as SwiftUI paths and its text as placed lines, made off the main actor from the package's
/// `SankeyDrawingParts`, so that the view only paints them: bands and bars in Pele's series colors, text in the note's
/// colors. Paths and text stay vector, on screen and in a printed PDF, and draw without a `Canvas`.
struct ReadingSankeyShapes: Sendable {
    /// A band and where its gradient runs, as unit points of the diagram's frame.
    struct Band: Sendable {
        let outline: Path
        let gradientStart: UnitPoint
        let gradientEnd: UnitPoint
        let sourceSeriesIndex: Int
        let targetSeriesIndex: Int
    }

    let bands: [Band]
    /// For each series color, the bars filled in it (`SankeyDrawingParts.nodeFills`).
    let nodeFills: [Path]
    /// The nodes' names and the bold title, in the text color.
    let textLines: [ReadingDiagramTextLine]
    /// The nodes' values, in the muted color.
    let valueLines: [ReadingDiagramTextLine]

    /// `size` is the layout's, which the paths are painted in: the bands' gradients run across it.
    init(parts: SankeyDrawingParts, size: CGSize, font: DiagramFont) {
        bands = parts.bands.map { band in
            Band(outline: Path(band.outline), gradientStart: UnitPoint(x: band.startX / size.width, y: 0),
                 gradientEnd: UnitPoint(x: band.endX / size.width, y: 0), sourceSeriesIndex: band.sourceSeriesIndex,
                 targetSeriesIndex: band.targetSeriesIndex)
        }
        nodeFills = parts.nodeFills.map { fill in Path(fill) }
        textLines = parts.names.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
            + (parts.title.map { title in ReadingDiagramTextLine.lines(of: title, font: font, isBold: true) } ?? [])
        valueLines = parts.values.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
    }
}
