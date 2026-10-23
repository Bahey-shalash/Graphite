import SwiftUI
import MermaidDiagrams

/// A Git graph's shapes as SwiftUI paths and its text as placed lines, made off the main actor from the package's
/// `GitGraphDrawingParts`, so that the view only paints them: lanes, lines and symbols in Pele's series colors, the rest
/// in the note's colors. Paths and text stay vector, on screen and in a printed PDF, and draw without a `Canvas`.
struct ReadingGitGraphShapes: Sendable {
    /// What is painted in one series color.
    struct ColorGroup: Sendable {
        let seriesIndex: Int
        let laneLines: Path
        let nameBoxes: Path
        let curves: Path
        let cherryPickCurves: Path
        let straightLines: Path
        let rings: Path
        let symbols: Path
    }

    /// A line of a commit's id, centered where it is drawn and turned by `angle` radians about its center.
    struct TurnedLine: Sendable {
        let line: ReadingDiagramTextLine
        let angle: Double
    }

    let colorGroups: [ColorGroup]
    let reverseCrosses: Path
    let cherryStems: Path
    let cherryFruits: Path
    let labelPatches: Path
    /// The ids, in the muted color.
    let labelLines: [TurnedLine]
    let tagBoxes: Path
    let tagHoles: Path
    /// The branch names, in the background color on their boxes.
    let nameLines: [ReadingDiagramTextLine]
    /// The tags' text, then the title, bold, in the foreground color.
    let textLines: [ReadingDiagramTextLine]

    init(parts: GitGraphDrawingParts, font: DiagramFont) {
        colorGroups = parts.colorGroups.map { group in
            ColorGroup(seriesIndex: group.seriesIndex, laneLines: Path(group.laneLines), nameBoxes: Path(group.nameBoxes), curves: Path(group.curves),
                       cherryPickCurves: Path(group.cherryPickCurves), straightLines: Path(group.straightLines), rings: Path(group.rings),
                       symbols: Path(group.symbols))
        }
        reverseCrosses = Path(parts.reverseCrosses)
        cherryStems = Path(parts.cherryStems)
        cherryFruits = Path(parts.cherryFruits)
        labelPatches = Path(parts.labelPatches)
        labelLines = parts.labels.flatMap { label in Self.turnedLines(of: label, font: font) }
        tagBoxes = Path(parts.tagBoxes)
        tagHoles = Path(parts.tagHoles)
        nameLines = parts.names.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
        textLines = parts.tagTexts.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
            + (parts.title.map { title in ReadingDiagramTextLine.lines(of: title, font: font, isBold: true) } ?? [])
    }

    /// An id's lines, each moved where the turn about the id's center takes it.
    private static func turnedLines(of label: GitGraphLayoutCommitLabel, font: DiagramFont) -> [TurnedLine] {
        let center = label.text.center
        let turn = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: label.angle).translatedBy(x: -center.x, y: -center.y)
        return ReadingDiagramTextLine.lines(of: label.text, font: font, isBold: false).map { line in
            TurnedLine(line: ReadingDiagramTextLine(text: line.text, center: line.center.applying(turn), font: line.font, isBold: line.isBold),
                       angle: Double(label.angle))
        }
    }
}
