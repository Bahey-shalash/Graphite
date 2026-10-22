import SwiftUI
import MermaidDiagrams

/// A sequence diagram's shapes as SwiftUI paths and its text as placed lines, made off the main actor from the
/// package's `SequenceDrawingParts`, so that the view only paints them in the note's colors. Paths and text stay
/// vector, on screen and in a printed PDF, and draw without a `Canvas` and the graphics device a canvas starts.
struct ReadingSequenceShapes: Sendable {
    /// The `rect` backgrounds, back to front, each with its own color or nil for the default shade.
    let highlights: [ReadingSequenceHighlight]
    let lifelines: Path
    /// Activation bars, back to front: a nested one over the one it is in.
    let activations: [Path]
    let blockOutlines: Path
    let blockSectionLines: Path
    let blockTextPatches: Path
    let blockTabs: Path
    let solidMessageLines: Path
    let dottedMessageLines: Path
    let filledHeads: Path
    let strokedHeads: Path
    let numberBadges: Path
    let messageTextPatches: Path
    let notes: Path
    let participantShapes: Path
    let participantFigureLines: Path
    /// Block titles and section texts, in the muted color.
    let blockTextLines: [ReadingDiagramTextLine]
    /// Block keywords, bold in the muted color.
    let blockKeywordLines: [ReadingDiagramTextLine]
    /// Message numbers, in the background color over their badges.
    let numberTextLines: [ReadingDiagramTextLine]
    /// Messages' texts, over their patches.
    let messageTextLines: [ReadingDiagramTextLine]
    /// Notes', participants' and the title's text, drawn last.
    let topTextLines: [ReadingDiagramTextLine]

    init(parts: SequenceDrawingParts, font: DiagramFont) {
        highlights = parts.highlights.map { highlight in ReadingSequenceHighlight(path: Path(highlight.path), color: highlight.color) }
        lifelines = Path(parts.lifelines)
        activations = parts.activations.map { activation in Path(activation) }
        blockOutlines = Path(parts.blockOutlines)
        blockSectionLines = Path(parts.blockSectionLines)
        blockTextPatches = Path(parts.blockTextPatches)
        blockTabs = Path(parts.blockTabs)
        solidMessageLines = Path(parts.solidMessageLines)
        dottedMessageLines = Path(parts.dottedMessageLines)
        filledHeads = Path(parts.filledHeads)
        strokedHeads = Path(parts.strokedHeads)
        numberBadges = Path(parts.numberBadges)
        messageTextPatches = Path(parts.messageTextPatches)
        notes = Path(parts.notes)
        participantShapes = Path(parts.participantShapes)
        participantFigureLines = Path(parts.participantFigureLines)
        func lines(_ blocks: [DiagramTextBlock], isBold: Bool = false) -> [ReadingDiagramTextLine] {
            blocks.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: isBold) }
        }
        blockTextLines = lines(parts.blockTexts)
        blockKeywordLines = lines(parts.blockKeywords, isBold: true)
        numberTextLines = lines(parts.numberTexts)
        messageTextLines = lines(parts.messageTexts)
        topTextLines = lines(parts.noteTexts) + lines(parts.participantTexts) + lines([parts.title].compactMap { title in title }, isBold: true)
    }
}

/// A `rect` background's shape and its color, or nil for the default shade.
struct ReadingSequenceHighlight: Sendable {
    let path: Path
    let color: SequenceHighlightColor?
}
