import SwiftUI
import MermaidDiagrams

/// A user journey's shapes as SwiftUI paths and its text as placed lines, made off the main actor from the package's
/// `UserJourneyDrawingParts`, so that the view only paints them: the actors' dots in their series colors, the rest in
/// the note's colors. Paths and text stay vector, on screen and in a printed PDF, and draw without a `Canvas`.
struct ReadingUserJourneyShapes: Sendable {
    let scaleLines: Path
    let stems: Path
    let scoreLine: Path
    let faces: Path
    let eyes: Path
    let mouths: Path
    let sectionBands: Path
    let cards: Path
    /// For each series color, the actors' dots on the cards in it (`UserJourneyDrawingParts.cardDotsBySeries`).
    let cardDotsBySeries: [Path]
    /// For each series color, the legend's dots in it.
    let legendDotsBySeries: [Path]
    /// The scale's numbers, drawn in the muted color.
    let scaleTextLines: [ReadingDiagramTextLine]
    /// The bands' headings, bold, then the cards' text, the legend's names and the title, bold, in the text color.
    let textLines: [ReadingDiagramTextLine]

    init(parts: UserJourneyDrawingParts, font: DiagramFont) {
        scaleLines = Path(parts.scaleLines)
        stems = Path(parts.stems)
        scoreLine = Path(parts.scoreLine)
        faces = Path(parts.faces)
        eyes = Path(parts.eyes)
        mouths = Path(parts.mouths)
        sectionBands = Path(parts.sectionBands)
        cards = Path(parts.cards)
        cardDotsBySeries = parts.cardDotsBySeries.map { dots in Path(dots) }
        legendDotsBySeries = parts.legendDotsBySeries.map { dots in Path(dots) }
        scaleTextLines = parts.scaleTexts.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
        textLines = parts.sectionTexts.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: true) }
            + (parts.taskTexts + parts.legendTexts).flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
            + (parts.title.map { title in ReadingDiagramTextLine.lines(of: title, font: font, isBold: true) } ?? [])
    }
}
