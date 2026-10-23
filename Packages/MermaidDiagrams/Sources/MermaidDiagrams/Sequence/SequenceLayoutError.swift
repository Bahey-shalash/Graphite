/// Why a sequence diagram was not laid out.
public enum SequenceLayoutError: Error, Equatable, Sendable {
    /// The diagram holds statements that are read but not laid out yet (`SequenceDiagram.statementsNotLaidOut`):
    /// drawn without them it would look complete and be wrong.
    case statementsNotLaidOut(Set<SequenceStatementNotLaidOut>)
}
