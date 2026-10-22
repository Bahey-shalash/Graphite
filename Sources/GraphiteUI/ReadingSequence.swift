import SwiftUI
import MermaidDiagrams

/// A sequence diagram laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingSequence: Sendable {
    let layout: SequenceLayout
    let shapes: ReadingSequenceShapes
    /// `accTitle`, else the diagram's title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// The participants' texts, in the order the diagram names them.
    let participantNames: [String]
    /// Each message as a sentence: who sends it to whom, and its text.
    let spokenMessages: [String]

    init(diagram: SequenceDiagram, layout: SequenceLayout) {
        self.layout = layout
        shapes = ReadingSequenceShapes(parts: SequenceDrawingParts(layout: layout), font: layout.font)
        title = diagram.accessibilityTitle ?? diagram.title
        description = diagram.accessibilityDescription
        let names = diagram.participants.map(\.label.spokenText)
        participantNames = names
        spokenMessages = diagram.events.compactMap { event in
            guard case .message(let message) = event else { return nil }
            let text = message.text.spokenText
            let route = "\(names[message.sourceIndex]) to \(names[message.targetIndex])"
            return text.isEmpty ? route : "\(route): \(text)"
        }
    }

    /// What a screen reader reads after the title: the description, else the participants and the messages.
    var accessibilityValue: String {
        description ?? ([participantNames.joined(separator: ", ")] + spokenMessages).joined(separator: ". ")
    }
}
