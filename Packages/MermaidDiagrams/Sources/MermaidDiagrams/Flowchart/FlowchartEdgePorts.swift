import CoreGraphics

/// Where edges meet their nodes. The edges that meet one side of a node spread along it, in the order of where they
/// come from, a port gap apart or closer when the side is short, so that they do not all meet in one point; each end
/// is then moved from the bounding box onto the shape's outline.
struct FlowchartEdgePorts {
    /// The gap between neighbouring edges on a side, where it has room: Pele's.
    static let portSeparation: CGFloat = 20

    /// One end of an edge on a side of a node.
    struct End {
        let edgeIndex: Int
        let isSourceEnd: Bool
        let node: Int
        let side: DiagramSide
        /// Where, across the flow, the route's next point is: the order the ends take along the side.
        let neighborAcross: CGFloat
    }

    /// The page points of each edge's ends, by edge index; nil for an edge with no end placed.
    private(set) var sourcePoints: [CGPoint?]
    private(set) var targetPoints: [CGPoint?]

    init(ends: [End], edgeCount: Int, nodeCenters: [CGPoint], shapes: [FlowchartNodeShape], shapeSizes: [CGSize]) {
        sourcePoints = Array(repeating: nil, count: edgeCount)
        targetPoints = Array(repeating: nil, count: edgeCount)
        var endsBySide = [[End]](repeating: [], count: nodeCenters.count * DiagramSide.allCases.count)
        for end in ends { endsBySide[end.node * DiagramSide.allCases.count + Self.sideNumber(end.side)].append(end) }
        for sideEnds in endsBySide where !sideEnds.isEmpty {
            let ordered = sideEnds.sorted { first, second in (first.neighborAcross, first.edgeIndex) < (second.neighborAcross, second.edgeIndex) }
            guard let side = ordered.first?.side, let node = ordered.first?.node else { continue }
            let span = FlowchartShapeGeometry.span(of: shapes[node], size: shapeSizes[node], side: side)
            let step = ordered.count > 1 ? min(Self.portSeparation, span / CGFloat(ordered.count - 1)) : 0
            for (position, end) in ordered.enumerated() {
                let offset = (CGFloat(position) - CGFloat(ordered.count - 1) / 2) * step
                let point = Self.outlinePoint(center: nodeCenters[node], shape: shapes[node], size: shapeSizes[node], side: side, offset: offset)
                if end.isSourceEnd { sourcePoints[end.edgeIndex] = point } else { targetPoints[end.edgeIndex] = point }
            }
        }
    }

    /// The point of a shape's outline on `side`, `offset` from the side's middle (rightward or downward).
    static func outlinePoint(center: CGPoint, shape: FlowchartNodeShape, size: CGSize, side: DiagramSide, offset: CGFloat) -> CGPoint {
        let inset = FlowchartShapeGeometry.inset(of: shape, size: size, side: side, offset: offset)
        switch side {
        case .top: return CGPoint(x: center.x + offset, y: center.y - size.height / 2 + inset)
        case .bottom: return CGPoint(x: center.x + offset, y: center.y + size.height / 2 - inset)
        case .left: return CGPoint(x: center.x - size.width / 2 + inset, y: center.y + offset)
        case .right: return CGPoint(x: center.x + size.width / 2 - inset, y: center.y + offset)
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
