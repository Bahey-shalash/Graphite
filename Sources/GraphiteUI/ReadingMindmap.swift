import MermaidDiagrams

/// A mindmap laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingMindmap: Sendable {
    let layout: MindmapLayout
    let shapes: ReadingMindmapShapes
    /// `accTitle`, else the front matter's title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// The text of each node, the root first, in the order the diagram writes them.
    let nodeTexts: [String]

    init(diagram: MindmapDiagram, layout: MindmapLayout) {
        self.layout = layout
        shapes = ReadingMindmapShapes(parts: MindmapDrawingParts(layout: layout), font: layout.font)
        title = diagram.accessibilityTitle ?? diagram.title
        description = diagram.accessibilityDescription
        nodeTexts = diagram.nodes.map(\.label.spokenText)
    }
}
