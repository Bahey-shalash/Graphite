import CoreGraphics

/// A flowchart laid out on a page whose origin is the top left corner and whose y runs down, in points. Drawing it
/// needs only colors: every position, path and text measurement is here.
public struct FlowchartLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the nodes' text was measured in; edge text is in the same font at its own `fontSize`.
    public let font: DiagramFont
    public let nodes: [FlowchartLayoutNode]
    /// The edges in the order they are written, edges to a node itself included.
    public let edges: [FlowchartLayoutEdge]
    /// The diagram's title above it, or nil.
    public let title: DiagramTextBlock?
}

public struct FlowchartLayoutNode: Equatable, Sendable {
    public let shape: FlowchartNodeShape
    /// The shape's bounding box.
    public let frame: CGRect
    public let text: DiagramTextBlock
}

public struct FlowchartLayoutEdge: Equatable, Sendable {
    public let stroke: FlowchartEdgeStroke
    /// The line, which stops where a mark begins.
    public let path: DiagramPath
    public let sourceMark: DiagramEdgeMark?
    public let targetMark: DiagramEdgeMark?
    /// The edge's text, drawn on a patch of the background, or nil.
    public let text: DiagramTextBlock?
}

extension FlowchartLayoutNode {
    func translated(by offset: CGVector) -> FlowchartLayoutNode {
        FlowchartLayoutNode(shape: shape, frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), text: text.translated(by: offset))
    }
}

extension FlowchartLayoutEdge {
    func translated(by offset: CGVector) -> FlowchartLayoutEdge {
        FlowchartLayoutEdge(stroke: stroke, path: path.translated(by: offset), sourceMark: sourceMark?.translated(by: offset),
                            targetMark: targetMark?.translated(by: offset), text: text?.translated(by: offset))
    }
}
