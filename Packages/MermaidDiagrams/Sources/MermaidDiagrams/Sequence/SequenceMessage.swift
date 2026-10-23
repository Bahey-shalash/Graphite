/// A message from one participant to another, or to itself, drawn as an arrow between their lifelines.
public struct SequenceMessage: Equatable, Sendable {
    /// Index into `SequenceDiagram.participants` of the participant the message is written from.
    public let sourceIndex: Int
    /// Index into `SequenceDiagram.participants` of the participant the message is written to.
    public let targetIndex: Int
    public let arrow: SequenceArrow
    /// The text after the colon, which may be empty.
    public let text: DiagramLabel
    /// Whether the text wraps to the width Mermaid gives it (`wrap:` before it) rather than staying on its lines.
    public let wrapsText: Bool
}

/// How a message's arrow is drawn: its line and its head.
public struct SequenceArrow: Equatable, Sendable {
    public let stroke: SequenceLineStroke
    public let head: SequenceArrowhead
    /// Whether the head is at both ends (`<<->>`, `<<-->>`) rather than at the target only.
    public let pointsBothWays: Bool

    init(stroke: SequenceLineStroke, head: SequenceArrowhead, pointsBothWays: Bool = false) {
        self.stroke = stroke
        self.head = head
        self.pointsBothWays = pointsBothWays
    }
}

/// How a message's line is drawn.
public enum SequenceLineStroke: Equatable, Sendable, CaseIterable {
    /// `-`: a solid line.
    case solid
    /// `--`: a dashed line, an answer by convention.
    case dotted
}

/// The mark at the end of a message's line.
public enum SequenceArrowhead: Equatable, Sendable, CaseIterable {
    /// `->`, `-->`: a line without a head.
    case none
    /// `->>`, `-->>`: a filled arrowhead.
    case arrow
    /// `-x`, `--x`: a cross, a message that is lost or refused.
    case cross
    /// `-)`, `--)`: an open arrowhead, an asynchronous message.
    case open
}
