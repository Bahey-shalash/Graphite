import MermaidDiagrams

/// A user journey laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingUserJourney: Sendable {
    let layout: UserJourneyLayout
    let shapes: ReadingUserJourneyShapes
    /// `accTitle`, else the title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// Each task with the level its face shows when it has a score, and the actors who take part, in the order the
    /// diagram writes them: “Do work: 1 (Me, Cat)”.
    let taskTexts: [String]

    init(diagram: UserJourneyDiagram, layout: UserJourneyLayout) {
        self.layout = layout
        shapes = ReadingUserJourneyShapes(parts: UserJourneyDrawingParts(layout: layout), font: layout.font)
        title = diagram.accessibilityTitle ?? diagram.title
        description = diagram.accessibilityDescription
        taskTexts = zip(diagram.tasks, layout.tasks).map { task, placed in
            var text = task.label.spokenText
            if task.score != nil { text += ": " + Self.writtenLevel(task.level) }
            let actors = placed.actorDots.compactMap { dot in
                layout.legend.indices.contains(dot.seriesIndex) ? layout.legend[dot.seriesIndex].text.lines.joined(separator: " ") : nil
            }
            return actors.isEmpty ? text : text + " (" + actors.joined(separator: ", ") + ")"
        }
    }

    /// A level as the scale writes it: a whole number without a fraction (`5`), else with its fraction (`3.5`).
    private static func writtenLevel(_ level: Double) -> String {
        level == level.rounded() ? String(Int(level)) : String(level)
    }
}
