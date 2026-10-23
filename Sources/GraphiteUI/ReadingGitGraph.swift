import MermaidDiagrams

/// A Git graph laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingGitGraph: Sendable {
    let layout: GitGraphLayout
    let shapes: ReadingGitGraphShapes
    /// `accTitle`, else the title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// Each branch with the ids written for its commits and their tags, in the order of the lanes: “main: init, v1.0”.
    let branchTexts: [String]

    init(diagram: GitGraphDiagram, layout: GitGraphLayout) {
        self.layout = layout
        shapes = ReadingGitGraphShapes(parts: GitGraphDrawingParts(layout: layout), font: layout.font)
        title = diagram.accessibilityTitle ?? diagram.title
        description = diagram.accessibilityDescription
        var commitTextsByBranch = diagram.branches.map { _ in [String]() }
        for commit in diagram.commits {
            commitTextsByBranch[commit.branchIndex] += (commit.hasWrittenIdentifier ? [commit.identifier] : []) + commit.tags.map(\.spokenText)
        }
        branchTexts = zip(diagram.branches, commitTextsByBranch).map { branch, commitTexts in
            commitTexts.isEmpty ? branch.label.spokenText : branch.label.spokenText + ": " + commitTexts.joined(separator: ", ")
        }
    }

    /// The reading view's diagram for a Git graph, or nil to show it as code when it sets options of Git graphs, which
    /// are not applied (`GitGraphLayoutError.optionsNotApplied`).
    static func diagram(_ diagram: GitGraphDiagram, typography: DiagramTypography) -> ReadingDiagram? {
        do {
            return .gitGraph(ReadingGitGraph(diagram: diagram, layout: try GitGraphLayoutEngine.layout(diagram, typography: typography)))
        } catch {
            switch error {
            case .optionsNotApplied: return nil
            }
        }
    }
}
