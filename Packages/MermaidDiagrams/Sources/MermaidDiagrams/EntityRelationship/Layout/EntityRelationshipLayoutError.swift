/// Why an entity relationship diagram was not laid out.
public enum EntityRelationshipLayoutError: Error, Equatable, Sendable {
    /// The diagram has `subgraph` groups, which are not laid out yet: drawn without them it would look complete and
    /// be wrong.
    case subgraphsNotLaidOut
    /// The entities and the points relationships pass through would be more than the limit.
    case tooManyLayoutPoints(limit: Int)
}
