/// A Mermaid sequence diagram (`sequenceDiagram`) as its text describes it: the participants in the order they first
/// appear, and what happens between them, top to bottom, in the order it is written.
public struct SequenceDiagram: Equatable, Sendable {
    public internal(set) var participants: [SequenceParticipant]
    /// Messages, notes, activations, blocks and numbering, in the order they are written. A message written with `+`
    /// or `-` is followed by the activation it starts or ends, as in Mermaid.
    public internal(set) var events: [SequenceEvent]
    /// `title …` in the diagram, else `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?
    /// The kinds of statement read whose meaning the model does not hold yet. A diagram with any is not laid out:
    /// drawn without them it would look complete and be wrong. What the model can hold of such a statement is kept
    /// (a participant in a box or created later is a participant); a message with a half arrow is left out of `events`.
    public internal(set) var statementsNotLaidOut: Set<SequenceStatementNotLaidOut>

    init(participants: [SequenceParticipant] = [], events: [SequenceEvent] = [], title: String? = nil, accessibilityTitle: String? = nil,
         accessibilityDescription: String? = nil, statementsNotLaidOut: Set<SequenceStatementNotLaidOut> = []) {
        self.participants = participants
        self.events = events
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
        self.statementsNotLaidOut = statementsNotLaidOut
    }
}

/// A kind of statement a sequence diagram may hold that is read but not laid out yet.
public enum SequenceStatementNotLaidOut: Hashable, Sendable, CaseIterable {
    /// `box … end`: participants grouped under a title and a color.
    case box
    /// `create participant` or `create actor`: a participant that appears at its first message.
    case participantCreation
    /// `destroy`: a participant whose lifeline ends in a cross at its last message.
    case participantDestruction
    /// `link`, `links`, `properties` and `details`: a participant's menu of links.
    case participantMenu
    /// `participant A@{ … }`: a participant's shape (`boundary`, `database`, `queue`, …) or name set in attributes.
    case participantAttributes
    /// The half arrows (`-|\`, `-//`, `/|-`, …), whose head is on one side of the line.
    case halfArrow
    /// `()` at an end of a message: a circle where the message meets the lifeline.
    case centralConnection
}
