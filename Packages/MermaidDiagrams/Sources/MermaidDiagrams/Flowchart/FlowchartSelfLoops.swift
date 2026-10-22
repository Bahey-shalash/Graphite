import CoreGraphics

/// Edges from a node to itself: each loops out of the node's side across the flow and back, the next one around the
/// last, with its text beyond it. The node's place in its rank is widened on both sides by the room its loops take,
/// so that it stays centered on its edges.
enum FlowchartSelfLoops {
    /// How far a loop reaches beyond the node, and how much farther each next loop: Pele's.
    static let loopReach: CGFloat = 26
    /// The gap between a loop and its text.
    static let textGap: CGFloat = 6
    /// How far out a loop's control points are, as a multiple of its reach: a cubic peaks at three quarters of the
    /// distance of its controls, so the loop's farthest point is about its reach.
    static let controlReachRatio: CGFloat = 1.3
    /// How far along the side, beyond where the loop leaves and comes back, its control points are, as a fraction
    /// of their distance out: it rounds the loop.
    static let controlSpreadRatio: CGFloat = 0.4

    /// The room across the flow, on each side of the node, that its loops and their texts take.
    static func room(textSizes: [CGSize?], loopSide: DiagramSide) -> CGFloat {
        textSizes.reduce(0) { room, textSize in
            let textExtent = textSize.map { size in (loopSide.isHorizontal ? size.height : size.width) + 2 * textGap } ?? 0
            return room + loopReach + textExtent
        }
    }

    /// One loop: the cubic from where it leaves the node to where it comes back, and the center of its text.
    struct Loop {
        let leave: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let back: CGPoint
        let textCenter: CGPoint?
    }

    /// The `loopIndex`-th loop of a node.
    static func loop(center: CGPoint, shape: FlowchartNodeShape, size: CGSize, loopSide: DiagramSide, loopIndex: Int,
                     textSize: CGSize?) -> Loop {
        // `outward` points away from the node through `loopSide`; `alongSide` runs along that side.
        let outward = loopSide == .right ? CGVector(dx: 1, dy: 0) : CGVector(dx: 0, dy: 1)
        let alongSide = loopSide == .right ? CGVector(dx: 0, dy: 1) : CGVector(dx: 1, dy: 0)
        let sideLength = loopSide == .right ? size.height : size.width
        let attachOffset = sideLength / 4
        let leave = FlowchartEdgePorts.outlinePoint(center: center, shape: shape, size: size, side: loopSide, offset: -attachOffset)
        let back = FlowchartEdgePorts.outlinePoint(center: center, shape: shape, size: size, side: loopSide, offset: attachOffset)
        let reach = loopReach * CGFloat(loopIndex + 1) * controlReachRatio
        func moved(_ point: CGPoint, outwardBy distance: CGFloat, alongBy shift: CGFloat) -> CGPoint {
            CGPoint(x: point.x + outward.dx * distance + alongSide.dx * shift, y: point.y + outward.dy * distance + alongSide.dy * shift)
        }
        let control1 = moved(leave, outwardBy: reach, alongBy: -reach * controlSpreadRatio)
        let control2 = moved(back, outwardBy: reach, alongBy: reach * controlSpreadRatio)
        let sideEdge = moved(center, outwardBy: loopSide == .right ? size.width / 2 : size.height / 2, alongBy: 0)
        let textCenter = textSize.map { textSize in
            let textExtent = loopSide == .right ? textSize.width : textSize.height
            return moved(sideEdge, outwardBy: loopReach * CGFloat(loopIndex + 1) + textGap + textExtent / 2, alongBy: 0)
        }
        return Loop(leave: leave, control1: control1, control2: control2, back: back, textCenter: textCenter)
    }
}
