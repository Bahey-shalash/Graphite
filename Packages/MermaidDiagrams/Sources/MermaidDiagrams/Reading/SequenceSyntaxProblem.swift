/// What the sequence diagram reader found where the syntax broke, beyond the problems every type shares.
public enum SequenceSyntaxProblem: Equatable, Sendable {
    /// A participant's name was expected: after an arrow, `participant`, `actor`, `activate`, `deactivate` or a note's
    /// placement.
    case expectedParticipant
    /// A participant's name is followed by no arrow (`->>`, `-->>`, `-x`, …).
    case expectedArrow
    /// A message or a note has no `:` before its text.
    case expectedText
    /// `Note` is not followed by `left of`, `right of` or `over`.
    case expectedNotePlacement
    /// `end` with no block open.
    case endWithoutBlock
    /// `else` outside an `alt` block, `and` outside a `par` block, or `option` outside a `critical` block, by keyword.
    case sectionOutsideItsBlock(keyword: String)
    /// The text ends inside a block, by the keyword that opened it (`loop`, `alt`, `box`, …).
    case unclosedBlock(keyword: String)
    /// `deactivate`, or `-` before a message's target, for a participant that has no activation to end.
    case inactiveParticipantDeactivated(identifier: String)
}
