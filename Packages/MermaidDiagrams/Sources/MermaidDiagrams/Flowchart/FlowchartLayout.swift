import CoreGraphics

/// A flowchart laid out on a page whose origin is the top left corner and whose y runs down, in points. Drawing it
/// needs only colors: every position, path and text measurement is here.
public struct FlowchartLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the nodes' text was measured in; edge text is in the same font at its own `fontSize`.
    public let font: DiagramFont
    /// The nodes drawn, in the order the diagram names them. A node that stands for a group (`A --> group`) is the
    /// group's box, not a node, so a flowchart with subgraphs may have fewer nodes here than its diagram.
    public let nodes: [FlowchartLayoutNode]
    /// The edges in the order they are written, edges to a node itself included.
    public let edges: [FlowchartLayoutEdge]
    /// The diagram's title above it, or nil.
    public let title: DiagramTextBlock?
    /// The boxes of the diagram's groups (`subgraph … end`), in the order of `FlowchartDiagram.subgraphs`: each before
    /// the boxes inside it. Empty for a flowchart without groups.
    public let clusters: [FlowchartLayoutCluster]
}

/// A group's box, drawn behind everything else, in Pele's style: half of the alternate surface color over what is
/// behind it, so that a box inside another is darker, with an outline and its title along the top.
public struct FlowchartLayoutCluster: Equatable, Sendable {
    public let frame: CGRect
    /// The title, along the top of the box, or nil for a group without one.
    public let title: DiagramTextBlock?
    /// How many boxes this one is inside: 0 for a box at the top level.
    public let depth: Int
    /// Whether an edge runs through the title where it sits: it is then drawn over the edges, on a patch of the box's
    /// color, so that the edge stops short of its letters.
    public let isTitleCrossed: Bool
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

extension FlowchartLayoutCluster {
    func translated(by offset: CGVector) -> FlowchartLayoutCluster {
        FlowchartLayoutCluster(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), title: title?.translated(by: offset), depth: depth,
                               isTitleCrossed: isTitleCrossed)
    }
}

extension FlowchartLayoutEdge {
    func translated(by offset: CGVector) -> FlowchartLayoutEdge {
        FlowchartLayoutEdge(stroke: stroke, path: path.translated(by: offset), sourceMark: sourceMark?.translated(by: offset),
                            targetMark: targetMark?.translated(by: offset), text: text?.translated(by: offset))
    }
}
