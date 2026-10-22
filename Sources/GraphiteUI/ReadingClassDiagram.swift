import SwiftUI
import MermaidDiagrams

/// A class diagram laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingClassDiagram: Sendable {
    let layout: ClassDiagramLayout
    let shapes: ReadingClassDiagramShapes
    /// `accTitle`, else the front matter's title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// The name of each class as its box shows it, in the order the diagram names them.
    let classNames: [String]

    init(diagram: ClassDiagram, layout: ClassDiagramLayout) {
        self.layout = layout
        shapes = ReadingClassDiagramShapes(parts: ClassDiagramDrawingParts(layout: layout), font: layout.font)
        title = diagram.accessibilityTitle ?? diagram.title
        description = diagram.accessibilityDescription
        classNames = diagram.classes.map(\.displayedName.spokenText)
    }
}
