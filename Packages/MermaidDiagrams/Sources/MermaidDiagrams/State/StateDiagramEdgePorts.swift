import CoreGraphics

/// Where transitions meet their states, Pele's: on a box, the transitions meeting one side spread along it in the order
/// of where they come from, a port gap apart or closer when the side is short, clear of its rounded corners; on a fork
/// or a join, each meets the bar where its line comes from, short of the bar's ends; a start, an end and a choice are
/// met in the middle of the side.
struct StateDiagramEdgePorts {
    /// The gap between neighbouring transitions on a side of a box, where it has room.
    static let portSeparation: CGFloat = 20
    /// Kept clear at each end of a box's side, for its corner.
    static let cornerClearance: CGFloat = 12
    /// Kept clear at each end of a bar.
    static let barEndClearance: CGFloat = 6

    /// One end of a transition on a side of a state.
    struct End {
        let transitionIndex: Int
        let isSourceEnd: Bool
        let state: Int
        let side: DiagramSide
        /// The next point of the transition's route, on the page: the order the ends take along the side.
        let neighbor: CGPoint
    }

    /// The page points of each transition's ends, by transition index; nil for a transition with no end placed.
    private(set) var sourcePoints: [CGPoint?]
    private(set) var targetPoints: [CGPoint?]

    init(ends: [End], transitionCount: Int, stateCenters: [CGPoint], kinds: [StateDiagramStateKind], stateSizes: [CGSize]) {
        sourcePoints = Array(repeating: nil, count: transitionCount)
        targetPoints = Array(repeating: nil, count: transitionCount)
        var endsBySide = [[End]](repeating: [], count: stateCenters.count * DiagramSide.allCases.count)
        for end in ends { endsBySide[end.state * DiagramSide.allCases.count + Self.sideNumber(end.side)].append(end) }
        for sideEnds in endsBySide where !sideEnds.isEmpty {
            let ordered = sideEnds.sorted { first, second in
                (Self.coordinate(of: first.neighbor, along: first.side), first.transitionIndex)
                    < (Self.coordinate(of: second.neighbor, along: second.side), second.transitionIndex)
            }
            guard let side = ordered.first?.side, let state = ordered.first?.state else { continue }
            let center = stateCenters[state]
            let size = stateSizes[state]
            let sideLength = side.isHorizontal ? size.width : size.height
            let spread = Self.offsets(count: ordered.count, placement: kinds[state].portPlacement, sideLength: sideLength)
            for (position, end) in ordered.enumerated() {
                var offset = spread[position]
                if kinds[state].portPlacement == .facingTheirLines, Self.isLongSide(side, of: size) {
                    let reach = sideLength / 2 - Self.barEndClearance
                    offset = min(max(Self.coordinate(of: end.neighbor, along: side) - Self.coordinate(of: center, along: side), -reach), reach)
                }
                let point = Self.sidePoint(center: center, size: size, side: side, offset: offset)
                if end.isSourceEnd { sourcePoints[end.transitionIndex] = point } else { targetPoints[end.transitionIndex] = point }
            }
        }
    }

    /// Where `count` lines meeting one side of a state meet it, from the side's middle: spread along a box's side,
    /// at the middle of anything else.
    static func offsets(count: Int, placement: StateDiagramPortPlacement, sideLength: CGFloat) -> [CGFloat] {
        guard placement == .spread, count > 1 else { return Array(repeating: 0, count: count) }
        let step = min(portSeparation, max(0, sideLength - 2 * cornerClearance) / CGFloat(count - 1))
        return (0..<count).map { position in (CGFloat(position) - CGFloat(count - 1) / 2) * step }
    }

    /// The point of a state's bounding box on `side`, `offset` from the side's middle (rightward or downward). Every
    /// state's outline touches its box's sides at their middles, and a box's sides are straight away from its corners.
    static func sidePoint(center: CGPoint, size: CGSize, side: DiagramSide, offset: CGFloat) -> CGPoint {
        switch side {
        case .top: CGPoint(x: center.x + offset, y: center.y - size.height / 2)
        case .bottom: CGPoint(x: center.x + offset, y: center.y + size.height / 2)
        case .left: CGPoint(x: center.x - size.width / 2, y: center.y + offset)
        case .right: CGPoint(x: center.x + size.width / 2, y: center.y + offset)
        }
    }

    /// A point's position along a side: its x on the top or bottom, its y on the left or right.
    private static func coordinate(of point: CGPoint, along side: DiagramSide) -> CGFloat {
        side.isHorizontal ? point.x : point.y
    }

    private static func isLongSide(_ side: DiagramSide, of size: CGSize) -> Bool {
        side.isHorizontal ? size.width > size.height : size.height > size.width
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

/// How the lines meeting one side of a state meet it.
enum StateDiagramPortPlacement: Equatable {
    /// Spread along the side, clear of its corners: a box.
    case spread
    /// Each where its line comes from, short of the ends, on the bar's long sides: a fork or a join.
    case facingTheirLines
    /// At the side's middle: a start, an end, a choice.
    case middle
}

extension StateDiagramStateKind {
    var portPlacement: StateDiagramPortPlacement {
        switch self {
        case .state: .spread
        case .fork, .join: .facingTheirLines
        case .start, .end, .choice: .middle
        }
    }
}
