import CoreGraphics

/// The height each subtree of a mindmap takes, as Pele stacks branches: a node's children are stacked top to bottom
/// in a band, and the node sits level with the middle of its first and last child; its band is as tall as that
/// stack or as the node, whichever reaches further. Each subtree is measured once, children before their parent.
struct MindmapSubtreeBands {
    /// The height of each subtree's band.
    private(set) var extents: [CGFloat]
    /// Each subtree's offset from the top of the stack it is in.
    private(set) var stackOffsets: [CGFloat]
    /// How far below the top of its band each node's top is.
    private(set) var nodeOffsets: [CGFloat]
    /// How far below the top of its band each node's stack of children starts.
    private(set) var childrenOffsets: [CGFloat]
    private let heights: [CGFloat]
    /// Whether each node has children: a gap next to a subtree with children of its own is wider.
    private let hasChildren: [Bool]

    /// Between two subtrees stacked in a band.
    static let siblingGap: CGFloat = 8
    /// Between two subtrees of which at least one has children of its own.
    static let groupGap: CGFloat = 18

    /// The bands of every subtree but the root's, whose branches the placement stacks on two sides.
    init(diagram: MindmapDiagram, heights: [CGFloat]) {
        let count = diagram.nodes.count
        self.heights = heights
        hasChildren = diagram.nodes.map { node in !node.childIndices.isEmpty }
        extents = heights
        stackOffsets = Array(repeating: 0, count: count)
        nodeOffsets = Array(repeating: 0, count: count)
        childrenOffsets = Array(repeating: 0, count: count)
        // Nodes come in depth-first order, so going backwards measures every child before its parent.
        for index in stride(from: count - 1, to: 0, by: -1) {
            let children = diagram.nodes[index].childIndices
            guard !children.isEmpty else { continue }
            let stack = stack(children[...], gap: Self.siblingGap)
            let nodeTop = stack.anchorMiddle - heights[index] / 2
            let bandTop = min(0, nodeTop)
            extents[index] = max(stack.height, nodeTop + heights[index]) - bandTop
            nodeOffsets[index] = nodeTop - bandTop
            childrenOffsets[index] = -bandTop
        }
    }

    /// Stacks `subtrees` top to bottom, `gap` apart, or `groupGap` where a subtree beside the gap has children.
    /// Returns the stack's height and how far below its top the middle between its first and last node's centers is.
    mutating func stack(_ subtrees: ArraySlice<Int>, gap: CGFloat) -> (height: CGFloat, anchorMiddle: CGFloat) {
        guard let first = subtrees.first, let last = subtrees.last else { return (0, 0) }
        var offset: CGFloat = 0
        var lastGap: CGFloat = 0
        for position in subtrees.indices {
            let subtree = subtrees[position]
            stackOffsets[subtree] = offset
            let nextHasChildren = position + 1 < subtrees.endIndex && hasChildren[subtrees[position + 1]]
            lastGap = hasChildren[subtree] || nextHasChildren ? max(gap, Self.groupGap) : gap
            offset += extents[subtree] + lastGap
        }
        return (offset - lastGap, (center(of: first) + center(of: last)) / 2)
    }

    /// How far below the top of its stack a subtree's node's center is.
    private func center(of subtree: Int) -> CGFloat {
        stackOffsets[subtree] + nodeOffsets[subtree] + heights[subtree] / 2
    }
}
