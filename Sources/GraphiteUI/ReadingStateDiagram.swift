import MermaidDiagrams

/// A state diagram laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingStateDiagram: Sendable {
    let layout: StateDiagramLayout
    let shapes: ReadingStateDiagramShapes
    /// `accTitle`, else the front matter's title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// The names of the states drawn as boxes, in the order the diagram names them.
    let stateNames: [String]

    init(diagram: StateDiagram, layout: StateDiagramLayout) {
        self.layout = layout
        shapes = ReadingStateDiagramShapes(parts: StateDiagramDrawingParts(layout: layout), font: layout.font)
        title = diagram.accessibilityTitle ?? diagram.title
        description = diagram.accessibilityDescription
        stateNames = layout.states.compactMap { state in state.name?.lines.joined(separator: " ") }
    }
}
