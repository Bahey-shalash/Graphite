import CoreGraphics

/// A mindmap laid out on a page whose origin is the top left corner and whose y runs down, in points. Drawing it
/// needs only colors: every position, path and text measurement is here.
public struct MindmapLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the text was measured in.
    public let font: DiagramFont
    /// The nodes in the diagram's order, the root first.
    public let nodes: [MindmapLayoutNode]
    /// The link from each node but the root to its parent, in the order of the nodes they lead to.
    public let edges: [MindmapLayoutEdge]
    /// The diagram's title above it, or nil.
    public let title: DiagramTextBlock?
}

public struct MindmapLayoutNode: Equatable, Sendable {
    public let outline: MindmapNodeOutline
    /// The outline's bounding box, or the room the text takes for a node drawn as text alone.
    public let frame: CGRect
    public let text: DiagramTextBlock
    /// The first-level branch whose color the node takes (`MindmapNode.branchIndex`), or nil for the root.
    public let branchIndex: Int?
}

/// A link from a node to one of its children, in the color of the child's branch.
public struct MindmapLayoutEdge: Equatable, Sendable {
    /// An S curve from the parent's side to the child's.
    public let path: DiagramPath
    public let branchIndex: Int
}

/// What a mindmap node is drawn as: its written shape, or for a node written without delimiters, what Pele makes of it.
public enum MindmapNodeOutline: Equatable, Sendable, CaseIterable {
    /// The root written without delimiters.
    case stadium
    case rectangle
    case roundedRectangle
    case circle
    case cloud
    case bang
    case hexagon
    /// A node written without delimiters that has children: its text in a pill, which sets the levels apart.
    case pill
    /// A node written without delimiters that ends a branch: its text alone.
    case text
}

extension MindmapLayoutNode {
    func translated(by offset: CGVector) -> MindmapLayoutNode {
        MindmapLayoutNode(outline: outline, frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), text: text.translated(by: offset), branchIndex: branchIndex)
    }
}

extension MindmapLayoutEdge {
    func translated(by offset: CGVector) -> MindmapLayoutEdge {
        MindmapLayoutEdge(path: path.translated(by: offset), branchIndex: branchIndex)
    }
}
