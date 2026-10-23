import SwiftUI
import MermaidDiagrams

/// A flowchart's group boxes as SwiftUI paths and placed lines, from the package's `FlowchartClusterDrawingParts`:
/// the fills by depth, the outlines, the titles painted with the boxes, and the titles painted over the edges on
/// their patches.
struct ReadingFlowchartClusterShapes: Sendable {
    /// The boxes at each depth, the top level first, each filled with the alternate surface at half its opacity.
    let fillsByDepth: [Path]
    let outlines: Path
    /// The titles no edge runs through.
    let titleLines: [ReadingDiagramTextLine]
    /// The patches behind the titles edges run through, by the depth of their box.
    let crossedTitlePatchesByDepth: [Path]
    let crossedTitleLines: [ReadingDiagramTextLine]

    init(parts: FlowchartClusterDrawingParts, font: DiagramFont) {
        fillsByDepth = parts.fillsByDepth.map { fill in Path(fill) }
        outlines = Path(parts.outlines)
        titleLines = parts.titles.flatMap { title in ReadingDiagramTextLine.lines(of: title, font: font, isBold: false) }
        crossedTitlePatchesByDepth = parts.crossedTitlePatchesByDepth.map { patches in Path(patches) }
        crossedTitleLines = parts.crossedTitles.flatMap { title in ReadingDiagramTextLine.lines(of: title, font: font, isBold: false) }
    }
}
