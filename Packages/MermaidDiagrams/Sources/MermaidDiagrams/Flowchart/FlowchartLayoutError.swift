/// Why a flowchart was not laid out.
public enum FlowchartLayoutError: Error, Equatable, Sendable {
    /// The flowchart has `subgraph` groups, which are not laid out yet: drawn without them it would look complete
    /// and be wrong.
    case subgraphsNotLaidOut
    /// The nodes and the points edges pass through would be more than the limit.
    case tooManyLayoutPoints(limit: Int)
}
