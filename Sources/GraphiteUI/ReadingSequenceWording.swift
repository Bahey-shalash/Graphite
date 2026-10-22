import MermaidDiagrams

extension SequenceSyntaxProblem {
    /// What is wrong on the line, as the end of the sentence `ReadingDiagramFailure.explanation` starts.
    var explanation: String {
        switch self {
        case .expectedParticipant: "a participant’s name is missing"
        case .expectedArrow: "a message has no arrow (such as ->> or -->>)"
        case .expectedText: "a message or a note has no “:” before its text"
        case .expectedNotePlacement: "a note does not say “left of”, “right of” or “over”"
        case .endWithoutBlock: "“end” closes no block"
        case .sectionOutsideItsBlock(let keyword): "“\(keyword)” is outside the block it belongs to"
        case .unclosedBlock(let keyword): "the “\(keyword)” block has no “end”"
        case .inactiveParticipantDeactivated(let identifier): "“\(identifier)” is deactivated while it is not active"
        }
    }
}
