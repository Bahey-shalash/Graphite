/// A participant of a sequence diagram: the identifier messages name it by, the text drawn for it and how it is drawn.
public struct SequenceParticipant: Equatable, Sendable {
    public let identifier: String
    /// The text drawn for the participant: its alias (`participant A as Alice`), else its identifier.
    public internal(set) var label: DiagramLabel
    public internal(set) var kind: SequenceParticipantKind

    init(identifier: String, label: DiagramLabel, kind: SequenceParticipantKind = .participant) {
        self.identifier = identifier
        self.label = label
        self.kind = kind
    }
}

/// How a participant is drawn at the top and the bottom of its lifeline.
public enum SequenceParticipantKind: Equatable, Sendable, CaseIterable {
    /// `participant`, and a participant only named by a message or a note: a box around its text.
    case participant
    /// `actor`: a stick figure above its text.
    case actor
}
