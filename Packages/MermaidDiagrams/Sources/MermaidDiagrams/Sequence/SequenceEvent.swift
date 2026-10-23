/// One thing a sequence diagram shows, in the order its text writes it. Blocks are flat: a block's start, its sections
/// and its end are events of their own, and the events between them are inside it.
public enum SequenceEvent: Equatable, Sendable {
    case message(SequenceMessage)
    case note(SequenceNote)
    /// `activate A`, or `+` before a message's target: the participant's lifeline widens into an activation bar.
    case activationStart(participantIndex: Int)
    /// `deactivate A`, or `-` before a message's target, which ends the source's innermost activation.
    case activationEnd(participantIndex: Int)
    /// `loop`, `alt`, `opt`, `par`, `critical`, `break` or `rect`, with the text written after the keyword.
    case blockStart(kind: SequenceBlockKind, label: DiagramLabel)
    /// `else`, `and` or `option`: the next section of the innermost block, with its text.
    case blockSection(label: DiagramLabel)
    /// `end`: the innermost block closes.
    case blockEnd
    /// `autonumber`: how the messages after it are numbered.
    case numbering(SequenceNumbering)
}

/// The kinds of block a sequence diagram frames its messages in.
public enum SequenceBlockKind: Equatable, Sendable {
    /// `loop`.
    case loop
    /// `alt … else … end`: one of several sections happens.
    case alternatives
    /// `opt`: the section may happen.
    case optional
    /// `par … and … end` (and `par_over`, which Pele draws the same way): the sections happen at once.
    case parallel
    /// `critical … option … end`: a section that must happen, and what happens when it does not.
    case critical
    /// `break`: the sequence stops here.
    case `break`
    /// `rect`: a shaded background behind the messages, in the color its line names, or nil for the default shade.
    case highlight(SequenceHighlightColor?)

    /// The word drawn in the block's tab, as Mermaid writes it; nil for a highlight, which has no tab.
    var keyword: String? {
        switch self {
        case .loop: "loop"
        case .alternatives: "alt"
        case .optional: "opt"
        case .parallel: "par"
        case .critical: "critical"
        case .break: "break"
        case .highlight: nil
        }
    }
}

/// `autonumber`, `autonumber 10`, `autonumber 10 5` or `autonumber off`. Numbers have at most two decimals, so they are
/// kept in hundredths and counted without rounding.
public struct SequenceNumbering: Equatable, Sendable {
    /// The number the next message takes, in hundredths, or nil to go on from the last one. Zero goes on too, as in
    /// Mermaid.
    public let firstNumberInHundredths: Int?
    /// What each message adds to the number, in hundredths, or nil to keep the step (1 at first).
    public let stepInHundredths: Int?
    /// Whether the numbers are drawn from here on: false after `autonumber off`.
    public let isVisible: Bool
}
