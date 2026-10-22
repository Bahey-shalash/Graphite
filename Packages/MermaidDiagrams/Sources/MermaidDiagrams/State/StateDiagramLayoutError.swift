/// Why a state diagram was not laid out.
public enum StateDiagramLayoutError: Error, Equatable, Sendable {
    /// The diagram has composite states (`state Id { … }`, with or without concurrent regions), which are not laid out
    /// yet: drawn without their boxes, it would look complete and be wrong.
    case compositeStatesNotLaidOut
    /// The states and the points transitions pass through would be more than the limit.
    case tooManyLayoutPoints(limit: Int)
}
