import CoreGraphics

/// Where relations meet their boxes, as Pele spreads them on a class: the ends that meet one side spread along it in
/// the order of where they come from, 24 points apart on the top and bottom and 20 on the left and right, farther
/// where a cardinality sits between two of them, and closer when the side is short, 24 points of it kept clear.
/// A lone end meets the middle of its side.
struct ClassDiagramEdgePorts {
    static let horizontalSideGap: CGFloat = 24
    static let verticalSideGap: CGFloat = 20
    /// The part of a side kept clear of ends.
    static let sideClearance: CGFloat = 24
    /// Between a cardinality's row and the next end on a left or right side.
    static let cardinalityClearance: CGFloat = 6

    /// One end of an edge on a side of a node.
    struct End {
        let edgeIndex: Int
        let isSourceEnd: Bool
        let node: Int
        let side: DiagramSide
        /// Where, along the side, the route's next point is: the order the ends take.
        let neighborAlongSide: CGFloat
        /// The width of the cardinality at this end, or 0.
        let cardinalityWidth: CGFloat
        /// Whether the end's cardinality sits after its line along the side (to its right, or below it): on the side
        /// the line then bends toward.
        let isTextAfter: Bool
    }

    /// The page points of each edge's ends, by edge index; nil for an edge with no end placed.
    private(set) var sourcePoints: [CGPoint?]
    private(set) var targetPoints: [CGPoint?]

    init(ends: [End], edgeCount: Int, nodeCenters: [CGPoint], sizes: [CGSize], markRowHeight: CGFloat) {
        sourcePoints = Array(repeating: nil, count: edgeCount)
        targetPoints = Array(repeating: nil, count: edgeCount)
        var endsBySide = [[End]](repeating: [], count: nodeCenters.count * DiagramSide.allCases.count)
        for end in ends { endsBySide[end.node * DiagramSide.allCases.count + Self.sideNumber(end.side)].append(end) }
        for sideEnds in endsBySide where !sideEnds.isEmpty {
            let ordered = sideEnds.sorted { first, second in (first.neighborAlongSide, first.edgeIndex) < (second.neighborAlongSide, second.edgeIndex) }
            let node = ordered[0].node
            let side = ordered[0].side
            let offsets = Self.offsets(of: ordered, sideLength: side.isHorizontal ? sizes[node].width : sizes[node].height, markRowHeight: markRowHeight)
            for (end, offset) in zip(ordered, offsets) {
                let point = Self.sidePoint(center: nodeCenters[node], size: sizes[node], side: side, offset: offset)
                if end.isSourceEnd { sourcePoints[end.edgeIndex] = point } else { targetPoints[end.edgeIndex] = point }
            }
        }
    }

    /// Each end's distance from the middle of its side, in their order along it.
    private static func offsets(of ends: [End], sideLength: CGFloat, markRowHeight: CGFloat) -> [CGFloat] {
        guard ends.count > 1, let side = ends.first?.side else { return Array(repeating: 0, count: ends.count) }
        let textExtent = { (end: End) in side.isHorizontal ? end.cardinalityWidth : markRowHeight + cardinalityClearance }
        let gaps = zip(ends, ends.dropFirst()).map { before, after in
            var gap = side.isHorizontal ? horizontalSideGap : verticalSideGap
            if before.cardinalityWidth > 0, before.isTextAfter { gap += textExtent(before) }
            if after.cardinalityWidth > 0, !after.isTextAfter { gap += textExtent(after) }
            return gap
        }
        let total = gaps.reduce(0, +)
        let scale = min(1, (sideLength - sideClearance) / total)
        guard scale > 0 else { return Array(repeating: 0, count: ends.count) }
        var offset = -total * scale / 2
        var offsets = [offset]
        for gap in gaps {
            offset += gap * scale
            offsets.append(offset)
        }
        return offsets
    }

    /// The point of a box's side `offset` from its middle (rightward or downward).
    static func sidePoint(center: CGPoint, size: CGSize, side: DiagramSide, offset: CGFloat) -> CGPoint {
        switch side {
        case .top: CGPoint(x: center.x + offset, y: center.y - size.height / 2)
        case .bottom: CGPoint(x: center.x + offset, y: center.y + size.height / 2)
        case .left: CGPoint(x: center.x - size.width / 2, y: center.y + offset)
        case .right: CGPoint(x: center.x + size.width / 2, y: center.y + offset)
        }
    }

    private static func sideNumber(_ side: DiagramSide) -> Int {
        switch side {
        case .top: 0
        case .right: 1
        case .bottom: 2
        case .left: 3
        }
    }
}
