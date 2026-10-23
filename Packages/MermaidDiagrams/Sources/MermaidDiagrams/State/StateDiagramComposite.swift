/// A composite state: a state written with a body (`state Id { … }`) that holds states of its own, divided into
/// concurrent regions by `--`. A composite named twice with a body is one composite whose bodies are read together.
public struct StateDiagramComposite: Equatable, Sendable {
    /// Index into `StateDiagram.states` of the composite state itself.
    public let stateIndex: Int
    /// Index into `StateDiagram.composites` of the composite whose body this one's first body is written in, or nil
    /// at the top level.
    public let parentCompositeIndex: Int?
    /// The way its body runs: its last `direction` statement, or nil when it has none.
    public internal(set) var direction: FlowchartDirection?
    /// How many concurrent regions its bodies hold: one, plus one for each `--` between them.
    public internal(set) var regionCount: Int

    init(stateIndex: Int, parentCompositeIndex: Int?, direction: FlowchartDirection? = nil, regionCount: Int = 1) {
        self.stateIndex = stateIndex
        self.parentCompositeIndex = parentCompositeIndex
        self.direction = direction
        self.regionCount = regionCount
    }
}
