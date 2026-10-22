import CoreGraphics

/// A state diagram laid out on a page whose origin is the top left corner and whose y runs down, in points. Drawing
/// it needs only colors: every position, path and text measurement is here.
public struct StateDiagramLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the states' names were measured in; descriptions, transition text and notes are in the same font at
    /// their own `fontSize`.
    public let font: DiagramFont
    /// The states in the diagram's order.
    public let states: [StateDiagramLayoutState]
    /// The transitions in the order they are written, transitions to a state itself included.
    public let transitions: [StateDiagramLayoutTransition]
    public let notes: [StateDiagramLayoutNote]
    /// The diagram's title above it, or nil.
    public let title: DiagramTextBlock?
}

public struct StateDiagramLayoutState: Equatable, Sendable {
    public let kind: StateDiagramStateKind
    /// The shape's bounding box.
    public let frame: CGRect
    /// The name, in the top of a box; nil for a start, an end, a choice, a fork or a join.
    public let name: DiagramTextBlock?
    /// The descriptions after the first, under a line below the name, in smaller type; nil when there are none.
    public let details: DiagramTextBlock?
}

public struct StateDiagramLayoutTransition: Equatable, Sendable {
    /// The line, which stops where the arrow begins.
    public let path: DiagramPath
    public let arrow: DiagramEdgeMark
    /// The transition's text, drawn on a patch of the background, or nil.
    public let text: DiagramTextBlock?
}

public struct StateDiagramLayoutNote: Equatable, Sendable {
    /// The note's sheet, whose top right corner is folded.
    public let frame: CGRect
    public let text: DiagramTextBlock
    /// The dashed line from the note's state to the note.
    public let connector: DiagramPath
}

extension StateDiagramLayoutState {
    func translated(by offset: CGVector) -> StateDiagramLayoutState {
        StateDiagramLayoutState(kind: kind, frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), name: name?.translated(by: offset),
                                details: details?.translated(by: offset))
    }
}

extension StateDiagramLayoutTransition {
    func translated(by offset: CGVector) -> StateDiagramLayoutTransition {
        StateDiagramLayoutTransition(path: path.translated(by: offset), arrow: arrow.translated(by: offset), text: text?.translated(by: offset))
    }
}

extension StateDiagramLayoutNote {
    func translated(by offset: CGVector) -> StateDiagramLayoutNote {
        StateDiagramLayoutNote(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), text: text.translated(by: offset),
                               connector: connector.translated(by: offset))
    }
}
