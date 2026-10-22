/// `Note left of A: …`, `Note right of A: …` or `Note over A,B: …`: text in a box beside or over lifelines.
public struct SequenceNote: Equatable, Sendable {
    public let placement: SequenceNotePlacement
    public let text: DiagramLabel
    /// Whether the text wraps to the width Mermaid gives it (`wrap:` before it).
    public let wrapsText: Bool
}

/// Where a note is drawn, by participant index into `SequenceDiagram.participants`.
public enum SequenceNotePlacement: Equatable, Sendable {
    case leftOf(participantIndex: Int)
    case rightOf(participantIndex: Int)
    /// Over one lifeline (`over A`, both indexes the same) or across the lifelines from one to the other (`over A,B`).
    case over(firstParticipantIndex: Int, lastParticipantIndex: Int)
}
