import SwiftUI
import MermaidDiagrams

/// An entity relationship diagram's shapes as SwiftUI paths and its text as placed lines, made off the main actor from
/// the package's `EntityRelationshipDrawingParts`, so that the view only paints them in the note's colors. Paths and
/// text stay vector, on screen and in a printed PDF, and draw without a `Canvas` and the graphics device a canvas
/// starts.
struct ReadingEntityRelationshipShapes: Sendable {
    let identifyingLines: Path
    let nonIdentifyingLines: Path
    let markFills: Path
    let markOutlines: Path
    let labelPatches: Path
    let boxFills: Path
    let rowStripes: Path
    let boxOutlines: Path
    /// Relationship labels, drawn over their patches and under the boxes.
    let labelLines: [ReadingDiagramTextLine]
    /// Entity names and attribute names, then the title in bold, in the text color.
    let textLines: [ReadingDiagramTextLine]
    /// Attribute types, keys and comments, in the muted text color.
    let mutedLines: [ReadingDiagramTextLine]

    init(parts: EntityRelationshipDrawingParts, font: DiagramFont) {
        identifyingLines = Path(parts.identifyingLines)
        nonIdentifyingLines = Path(parts.nonIdentifyingLines)
        markFills = Path(parts.markFills)
        markOutlines = Path(parts.markOutlines)
        labelPatches = Path(parts.labelPatches)
        boxFills = Path(parts.boxFills)
        rowStripes = Path(parts.rowStripes)
        boxOutlines = Path(parts.boxOutlines)
        labelLines = parts.labels.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
        textLines = parts.entityTexts.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
            + (parts.title.map { title in ReadingDiagramTextLine.lines(of: title, font: font, isBold: true) } ?? [])
        mutedLines = parts.attributeDetails.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
    }
}
