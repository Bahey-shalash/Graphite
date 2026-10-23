import SwiftUI
import MermaidDiagrams

/// A state diagram's shapes as SwiftUI paths and its text as placed lines, made off the main actor from the package's
/// `StateDiagramDrawingParts`, so that the view only paints them in the note's colors. Paths and text stay vector, on
/// screen and in a printed PDF, and draw without a `Canvas` and the graphics device a canvas starts.
struct ReadingStateDiagramShapes: Sendable {
    let transitionLines: Path
    let noteConnectors: Path
    let arrows: Path
    let transitionTextPatches: Path
    let stateFills: Path
    let stateOutlines: Path
    let endRings: Path
    let solidMarks: Path
    let noteSheets: Path
    let noteFolds: Path
    /// Transition text, drawn over the patches and under the states.
    let transitionTextLines: [ReadingDiagramTextLine]
    /// The states' names and descriptions, and the title, drawn over the states.
    let stateTextLines: [ReadingDiagramTextLine]
    /// Note text, drawn last, in the notes' own color.
    let noteTextLines: [ReadingDiagramTextLine]

    init(parts: StateDiagramDrawingParts, font: DiagramFont) {
        transitionLines = Path(parts.transitionLines)
        noteConnectors = Path(parts.noteConnectors)
        arrows = Path(parts.arrows)
        transitionTextPatches = Path(parts.transitionTextPatches)
        stateFills = Path(parts.stateFills)
        stateOutlines = Path(parts.stateOutlines)
        endRings = Path(parts.endRings)
        solidMarks = Path(parts.solidMarks)
        noteSheets = Path(parts.noteSheets)
        noteFolds = Path(parts.noteFolds)
        transitionTextLines = parts.transitionTexts.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
        stateTextLines = parts.stateTexts.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
            + (parts.title.map { title in ReadingDiagramTextLine.lines(of: title, font: font, isBold: true) } ?? [])
        noteTextLines = parts.noteTexts.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
    }
}
