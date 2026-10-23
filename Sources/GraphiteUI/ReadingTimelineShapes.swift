import SwiftUI
import MermaidDiagrams

/// A timeline's shapes as SwiftUI paths and its text as placed lines, made off the main actor from the package's
/// `TimelineDrawingParts`, so that the view only paints them: boxes and dots in their series or muted colors, lines
/// and text in the note's colors. Paths and text stay vector, on screen and in a printed PDF, and draw without a `Canvas`.
struct ReadingTimelineShapes: Sendable {
    /// The boxes and dots painted in one color.
    struct ColorGroup: Sendable {
        let color: TimelineColor
        let boxes: Path
        let eventBoxes: Path
        let dots: Path
    }

    let colorGroups: [ColorGroup]
    let axis: Path
    let axisArrow: Path
    let connectors: Path
    /// Sections' text, bold, and periods' text, drawn in the background color on their boxes.
    let textLinesOnBoxes: [ReadingDiagramTextLine]
    /// Events' text, then the title, bold, in the foreground color.
    let textLines: [ReadingDiagramTextLine]

    init(parts: TimelineDrawingParts, font: DiagramFont) {
        colorGroups = parts.colorGroups.map { group in
            ColorGroup(color: group.color, boxes: Path(group.boxes), eventBoxes: Path(group.eventBoxes), dots: Path(group.dots))
        }
        axis = Path(parts.axis)
        axisArrow = Path(parts.axisArrow)
        connectors = Path(parts.connectors)
        textLinesOnBoxes = parts.sectionTexts.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: true) }
            + parts.periodTexts.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
        textLines = parts.eventTexts.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
            + (parts.title.map { title in ReadingDiagramTextLine.lines(of: title, font: font, isBold: true) } ?? [])
    }
}
