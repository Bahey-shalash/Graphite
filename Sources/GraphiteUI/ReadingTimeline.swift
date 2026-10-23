import MermaidDiagrams

/// A timeline laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingTimeline: Sendable {
    let layout: TimelineLayout
    let shapes: ReadingTimelineShapes
    /// `accTitle`, else the title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// Each period with its events, in the order the diagram writes them: “2004: Facebook, Google”.
    let periodTexts: [String]

    init(diagram: TimelineDiagram, layout: TimelineLayout) {
        self.layout = layout
        shapes = ReadingTimelineShapes(parts: TimelineDrawingParts(layout: layout), font: layout.font)
        title = diagram.accessibilityTitle ?? diagram.title
        description = diagram.accessibilityDescription
        periodTexts = diagram.periods.map { period in
            period.events.isEmpty ? period.label.spokenText
                : period.label.spokenText + ": " + period.events.map(\.spokenText).joined(separator: ", ")
        }
    }
}
