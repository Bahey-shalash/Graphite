import CoreGraphics

/// Where each node of a mindmap goes, as Pele places them: the root at the origin, its first branches to the right
/// and the rest to the left, split where the two sides are closest in height, each side's stack of branches
/// centered on the root; every child one column further out than its parent, in its band.
struct MindmapPlacement {
    /// The center of each node across.
    private(set) var centersAcross: [CGFloat]
    /// The top of each node.
    private(set) var tops: [CGFloat]
    /// +1 for a node right of the root, -1 for one left of it, 0 for the root.
    private(set) var sides: [CGFloat]

    /// Between two first-level branches stacked on one side.
    static let branchGap: CGFloat = 28
    /// Across, between the root and its children.
    static let rootChildGap: CGFloat = 52
    /// Across, between any other node and its children.
    static let childGap: CGFloat = 36

    init(diagram: MindmapDiagram, sizes: [CGSize], bands: inout MindmapSubtreeBands) {
        let count = diagram.nodes.count
        centersAcross = Array(repeating: 0, count: count)
        tops = Array(repeating: 0, count: count)
        sides = Array(repeating: 0, count: count)
        guard let root = diagram.nodes.first else { return }
        var bandTops = Array(repeating: CGFloat(0), count: count)
        let branches = root.childIndices
        let split = Self.rightBranchCount(branches, extents: bands.extents)
        for (range, side) in [(0..<split, CGFloat(1)), (split..<branches.count, CGFloat(-1))] where !range.isEmpty {
            let middle = bands.stack(branches[range], gap: Self.branchGap).anchorMiddle
            for branch in branches[range] {
                bandTops[branch] = bands.stackOffsets[branch] - middle
                sides[branch] = side
            }
        }
        tops[0] = -sizes[0].height / 2
        for (index, node) in diagram.nodes.enumerated() {
            if index > 0 { tops[index] = bandTops[index] + bands.nodeOffsets[index] }
            for child in node.childIndices {
                if index > 0 {
                    sides[child] = sides[index]
                    bandTops[child] = bandTops[index] + bands.childrenOffsets[index] + bands.stackOffsets[child]
                }
                let gap = index > 0 ? Self.childGap : Self.rootChildGap
                centersAcross[child] = centersAcross[index] + sides[child] * (sizes[index].width / 2 + gap + sizes[child].width / 2)
            }
        }
    }

    /// How many of the root's branches, from the first, go right: the split where the heights of the two sides,
    /// gaps included, are closest. One branch goes right; with more, at least one goes left.
    static func rightBranchCount(_ branches: [Int], extents: [CGFloat]) -> Int {
        let count = branches.count
        let total = branches.reduce(CGFloat(0)) { sum, branch in sum + extents[branch] }
        var split = count
        var smallestDifference = CGFloat.infinity
        var right: CGFloat = 0
        for rightCount in stride(from: 1, to: count, by: 1) {
            right += extents[branches[rightCount - 1]]
            let difference = abs(2 * right - total + CGFloat(2 * rightCount - count) * branchGap)
            if difference < smallestDifference {
                smallestDifference = difference
                split = rightCount
            }
        }
        return split
    }
}
