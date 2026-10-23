import SwiftUI
import MermaidDiagrams

/// A mindmap's shapes as SwiftUI paths and its text as placed lines, made off the main actor from the package's
/// `MindmapDrawingParts`, so that the view only paints them: each branch in its series color, the root in the
/// note's colors. Paths and text stay vector, on screen and in a printed PDF, and draw without a `Canvas`.
struct ReadingMindmapShapes: Sendable {
    /// The links and node outlines of the branches that share one number, painted in that number's series color.
    struct Branch: Sendable {
        let branchIndex: Int
        let links: Path
        let nodeOutlines: Path
    }

    let branches: [Branch]
    let rootOutline: Path
    /// Every node's text, then the title, which is bold.
    let textLines: [ReadingDiagramTextLine]

    init(parts: MindmapDrawingParts, font: DiagramFont) {
        branches = parts.branches.map { branch in
            Branch(branchIndex: branch.branchIndex, links: Path(branch.links), nodeOutlines: Path(branch.nodeOutlines))
        }
        rootOutline = Path(parts.rootOutline)
        textLines = parts.nodeTexts.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
            + (parts.title.map { title in ReadingDiagramTextLine.lines(of: title, font: font, isBold: true) } ?? [])
    }
}
