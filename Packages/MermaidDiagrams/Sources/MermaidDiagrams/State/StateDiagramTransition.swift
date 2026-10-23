/// A transition of a state diagram, from one state to another as written (`A --> B` runs from A to B), drawn as a line
/// with an arrow at its target.
public struct StateDiagramTransition: Equatable, Sendable {
    /// Index into `StateDiagram.states` of the state the transition leaves.
    public let sourceIndex: Int
    /// Index into `StateDiagram.states` of the state the transition arrives at.
    public let targetIndex: Int
    /// The text on the transition (`A --> B : text`), or nil.
    public let label: DiagramLabel?
}
