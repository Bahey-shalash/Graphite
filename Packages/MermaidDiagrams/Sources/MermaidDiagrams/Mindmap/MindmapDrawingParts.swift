import CoreGraphics

/// A laid-out mindmap's geometry grouped by how it is painted, so that drawing it in any colors is a few fills and
/// strokes per branch, by Core Graphics (`MindmapRenderer`) or by a view's own shapes. Back to front, as Pele draws:
/// each branch's links and then its nodes, the root over the links that leave it, the text, the title.
public struct MindmapDrawingParts {
    /// The links and node outlines of the branches that share one number (`MindmapNode.branchIndex`), painted in
    /// that number's series color.
    public struct Branch {
        public let branchIndex: Int
        /// The links into the branch's nodes, stroked `linkLineWidth` wide in the branch's color.
        public let links: CGPath
        /// The outlines of the branch's nodes, filled with the branch's color at `nodeFillOpacity` and stroked
        /// `outlineLineWidth` wide in it. A node drawn as text alone has none.
        public let nodeOutlines: CGPath
    }

    /// The branches with something to paint, by number.
    public let branches: [Branch]
    /// The root's outline, filled in the surface color and stroked in the border color.
    public let rootOutline: CGPath
    /// Every node's text, in the foreground color.
    public let nodeTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let linkLineWidth: CGFloat = 1.5
    public static let outlineLineWidth: CGFloat = 1
    /// How much of the branch color a node's fill takes, over the background: Pele's tint.
    public static let nodeFillOpacity: CGFloat = 0.22

    public init(layout: MindmapLayout) {
        let links = (0..<MindmapNode.branchCount).map { _ in CGMutablePath() }
        let outlines = (0..<MindmapNode.branchCount).map { _ in CGMutablePath() }
        let rootOutline = CGMutablePath()
        for edge in layout.edges {
            links[edge.branchIndex % MindmapNode.branchCount].addPath(DiagramEdgeDrawing.path(edge.path))
        }
        for node in layout.nodes {
            guard let outline = MindmapShapeDrawing.outline(of: node.outline, in: node.frame) else { continue }
            if let branchIndex = node.branchIndex {
                outlines[branchIndex % MindmapNode.branchCount].addPath(outline)
            } else {
                rootOutline.addPath(outline)
            }
        }
        branches = (0..<MindmapNode.branchCount).compactMap { branchIndex in
            links[branchIndex].isEmpty && outlines[branchIndex].isEmpty ? nil
                : Branch(branchIndex: branchIndex, links: links[branchIndex], nodeOutlines: outlines[branchIndex])
        }
        self.rootOutline = rootOutline
        nodeTexts = layout.nodes.map(\.text)
        title = layout.title
    }
}
