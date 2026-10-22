import CoreGraphics

/// Transitions from a state to itself, Pele's: each loops out of the state's side across the flow (its right in a
/// diagram that runs down or up, its bottom in one that runs across) and back, the next one wider and reaching
/// further, with the loops' texts stacked beyond the outermost.
enum StateDiagramSelfLoops {
    /// How far the first loop reaches beyond the state, and how much further each next one.
    static let loopReach: CGFloat = 26
    static let reachStep: CGFloat = 8
    /// Half the distance along the side between where the first loop leaves and comes back, and how much more for
    /// each next one; never closer than `sideClearance` to the side's corners, nor under `minimumSpread`.
    static let spreadBase: CGFloat = 8
    static let spreadStep: CGFloat = 6
    static let sideClearance: CGFloat = 4
    static let minimumSpread: CGFloat = 2
    /// Between the outermost loop and its texts.
    static let textGap: CGFloat = 4
    /// Below a state, the texts start this fraction of the outermost loop's reach away, which its curve peaks at.
    static let belowReachRatio: CGFloat = 0.75
    /// The room a loop's text takes across beyond its lines, for the patch drawn behind it.
    static let textRoomWidth: CGFloat = 12

    /// The room a state's loops take across the flow on each side, so that the state stays centered in its place,
    /// and how far along the flow their stacked texts reach.
    static func extent(textSizes: [CGSize?], flowIsVertical: Bool) -> (room: CGFloat, textAlong: CGFloat) {
        guard !textSizes.isEmpty else { return (0, 0) }
        let reach = outermostReach(loopCount: textSizes.count)
        let widestText = textSizes.map { size in size.map { size in size.width + textRoomWidth } ?? 0 }.max() ?? 0
        let stackedTextHeight = textSizes.reduce(0) { total, size in total + (size?.height ?? 0) }
        return flowIsVertical ? (reach + widestText, stackedTextHeight)
                              : (reach * belowReachRatio + textGap + stackedTextHeight, widestText)
    }

    /// One loop: its line, its arrow, and the center of its text.
    struct Loop {
        let path: DiagramPath
        let arrow: DiagramEdgeMark
        let textCenter: CGPoint?
    }

    /// The loops of a state centered at `center`, drawn `size`, one per text size (nil for a loop without text).
    static func loops(center: CGPoint, size: CGSize, flowIsVertical: Bool, textSizes: [CGSize?]) -> [Loop] {
        let side = LoopSide(center: center, size: size, flowIsVertical: flowIsVertical)
        let textCenters = stackedTextCenters(side: side, textSizes: textSizes)
        return textSizes.indices.map { loopIndex in
            let reach = loopReach + CGFloat(loopIndex) * reachStep
            let spread = max(min(side.halfLength - sideClearance, spreadBase + CGFloat(loopIndex) * spreadStep), minimumSpread)
            let trim = DiagramEdgeMark.lineTrim(for: .arrow) / max((reach * reach + spread * spread).squareRoot(), 1)
            let path = DiagramPath(start: side.point(outward: 0, along: -spread), segments: [
                .curve(to: side.point(outward: reach * trim, along: spread + spread * trim), control1: side.point(outward: reach, along: -2 * spread),
                       control2: side.point(outward: reach, along: 2 * spread)),
            ])
            let arrow = DiagramEdgeMark(arrowhead: .arrow, tip: side.point(outward: 0, along: spread),
                                        direction: side.unitVector(outward: -reach, along: -spread))
            return Loop(path: path, arrow: arrow, textCenter: textCenters[loopIndex])
        }
    }

    /// The centers of the loops' texts, stacked beyond the outermost loop: down the page, centered on the state, beside
    /// a diagram that runs down or up; down from below the loops in one that runs across.
    private static func stackedTextCenters(side: LoopSide, textSizes: [CGSize?]) -> [CGPoint?] {
        let furthestReach = outermostReach(loopCount: textSizes.count)
        let stackedTextHeight = textSizes.reduce(0) { total, size in total + (size?.height ?? 0) }
        var stacked: CGFloat = 0
        return textSizes.map { textSize in
            guard let textSize else { return nil }
            let stackedCenter = stacked + textSize.height / 2
            stacked += textSize.height
            guard side.flowIsVertical else {
                return CGPoint(x: side.center.x, y: side.edgePoint.y + furthestReach * belowReachRatio + textGap + stackedCenter)
            }
            return CGPoint(x: side.edgePoint.x + furthestReach + textGap + (textSize.width + textRoomWidth) / 2,
                           y: side.center.y - stackedTextHeight / 2 + stackedCenter)
        }
    }

    private static func outermostReach(loopCount: Int) -> CGFloat {
        loopReach + CGFloat(max(loopCount - 1, 0)) * reachStep
    }

    /// The side loops leave from. Offsets are given for a loop on the right (`outward` to the right, `along` down the
    /// side) and turned a quarter for one below.
    private struct LoopSide {
        let center: CGPoint
        let flowIsVertical: Bool
        /// Half the state's extent across the side, from its center to the side.
        let outwardHalf: CGFloat
        /// Half the side's length.
        let halfLength: CGFloat

        init(center: CGPoint, size: CGSize, flowIsVertical: Bool) {
            self.center = center
            self.flowIsVertical = flowIsVertical
            outwardHalf = (flowIsVertical ? size.width : size.height) / 2
            halfLength = (flowIsVertical ? size.height : size.width) / 2
        }

        /// The middle of the side.
        var edgePoint: CGPoint { point(outward: 0, along: 0) }

        func point(outward: CGFloat, along: CGFloat) -> CGPoint {
            flowIsVertical ? CGPoint(x: center.x + outwardHalf + outward, y: center.y + along)
                           : CGPoint(x: center.x - along, y: center.y + outwardHalf + outward)
        }

        func unitVector(outward: CGFloat, along: CGFloat) -> CGVector {
            let length = max((outward * outward + along * along).squareRoot(), 1)
            return flowIsVertical ? CGVector(dx: outward / length, dy: along / length) : CGVector(dx: -along / length, dy: outward / length)
        }
    }
}
