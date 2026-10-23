/// A note beside a state (`note left of Id : text`, or over several lines up to `end note`).
public struct StateDiagramNote: Equatable, Sendable {
    /// Index into `StateDiagram.states` of the state the note is written for.
    public let stateIndex: Int
    public let side: StateDiagramNoteSide
    public let text: DiagramLabel
}

/// The side of its state a note is written on. Notes sit beside their state across the flow: `left of` to the left of
/// a diagram that runs down or up, above one that runs across.
public enum StateDiagramNoteSide: Equatable, Sendable, CaseIterable {
    case left
    case right
}
