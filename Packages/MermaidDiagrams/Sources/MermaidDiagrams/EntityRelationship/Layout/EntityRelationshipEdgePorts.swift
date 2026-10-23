import CoreGraphics

/// Where relationships meet their boxes. Those that meet one side of a box spread along it, in the order of where
/// they go, 18 points apart, or closer when the side is short, keeping 14 points from its ends, so that their marks
/// do not cover each other: Pele's.
struct EntityRelationshipEdgePorts {
    static let portSeparation: CGFloat = 18
    static let sideMargin: CGFloat = 14

    /// One end of a relationship on a side of a box.
    struct End {
        let relationshipIndex: Int
        let isFirstEntityEnd: Bool
        let entity: Int
        let side: DiagramSide
        /// Where, across the flow, the route's next point is: the order the ends take along the side.
        let neighborAcross: CGFloat
    }

    /// The page points of each relationship's ends, by relationship index; nil for an end not placed.
    private(set) var firstEntityPoints: [CGPoint?]
    private(set) var secondEntityPoints: [CGPoint?]

    init(ends: [End], relationshipCount: Int, boxCenters: [CGPoint], boxSizes: [CGSize]) {
        firstEntityPoints = Array(repeating: nil, count: relationshipCount)
        secondEntityPoints = Array(repeating: nil, count: relationshipCount)
        var endsBySide = [[End]](repeating: [], count: boxCenters.count * DiagramSide.allCases.count)
        for end in ends { endsBySide[end.entity * DiagramSide.allCases.count + Self.sideNumber(end.side)].append(end) }
        for sideEnds in endsBySide where !sideEnds.isEmpty {
            let ordered = sideEnds.sorted { first, second in
                (first.neighborAcross, first.relationshipIndex) < (second.neighborAcross, second.relationshipIndex)
            }
            let entity = ordered[0].entity
            let side = ordered[0].side
            let length = side.isHorizontal ? boxSizes[entity].width : boxSizes[entity].height
            let step = ordered.count > 1 ? max(min(Self.portSeparation, (length - 2 * Self.sideMargin) / CGFloat(ordered.count - 1)), 0) : 0
            for (position, end) in ordered.enumerated() {
                let offset = (CGFloat(position) - CGFloat(ordered.count - 1) / 2) * step
                let point = Self.sidePoint(center: boxCenters[entity], size: boxSizes[entity], side: side, offset: offset)
                if end.isFirstEntityEnd { firstEntityPoints[end.relationshipIndex] = point } else { secondEntityPoints[end.relationshipIndex] = point }
            }
        }
    }

    /// The point of a box's `side`, `offset` from the side's middle (rightward or downward).
    static func sidePoint(center: CGPoint, size: CGSize, side: DiagramSide, offset: CGFloat) -> CGPoint {
        switch side {
        case .top: CGPoint(x: center.x + offset, y: center.y - size.height / 2)
        case .bottom: CGPoint(x: center.x + offset, y: center.y + size.height / 2)
        case .left: CGPoint(x: center.x - size.width / 2, y: center.y + offset)
        case .right: CGPoint(x: center.x + size.width / 2, y: center.y + offset)
        }
    }

    /// The unit vector out of a box through `side`.
    static func outward(from side: DiagramSide) -> CGVector {
        switch side {
        case .top: CGVector(dx: 0, dy: -1)
        case .bottom: CGVector(dx: 0, dy: 1)
        case .left: CGVector(dx: -1, dy: 0)
        case .right: CGVector(dx: 1, dy: 0)
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
