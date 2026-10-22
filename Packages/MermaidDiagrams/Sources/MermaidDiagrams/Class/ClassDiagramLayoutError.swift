/// Why a class diagram was not laid out.
public enum ClassDiagramLayoutError: Error, Equatable, Sendable {
    /// The diagram has `namespace` groups, which are not laid out yet: drawn without them it would look complete and
    /// be wrong.
    case namespacesNotLaidOut
    /// The nodes and the points relations pass through would be more than the limit.
    case tooManyLayoutPoints(limit: Int)
}
