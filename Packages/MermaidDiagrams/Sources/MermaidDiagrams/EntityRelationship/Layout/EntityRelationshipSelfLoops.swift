import CoreGraphics

/// Relationships of an entity with itself, as Pele draws them: each leaves the box straight for a mark's length,
/// turns in a curve and comes back beside where it left, out of the side across the flow (the right when ranks run
/// down, the bottom when they run across), with its label beyond it. The loops of one box share that side, each
/// taking a band of it, squeezed together when the side is too short.
enum EntityRelationshipSelfLoops {
    /// How far a loop's turn reaches beyond its straight runs: Pele's.
    static let turnReach: CGFloat = 28
    /// The least stretch of the side one loop takes.
    static let minimumBand: CGFloat = 38
    /// How far the side is kept free of loops at its two ends together.
    static let sideMargin: CGFloat = 8
    /// The room beyond a loop's farthest point and its label's.
    static let outerRoom: CGFloat = 10
    /// The gap between a loop and its label.
    static let labelGap: CGFloat = 6
    /// The largest half distance between where a loop leaves and where it comes back.
    static let largestSpread: CGFloat = 13
    /// How far inside its band's ends a loop leaves and comes back, where the band is narrow.
    static let spreadInset: CGFloat = 6
    /// The room a label takes beyond its size in a band: across it when loops leave the bottom, along it otherwise.
    static let labelBandPadding = CGSize(width: 12, height: 6)
    /// How far a turn's curve reaches, as a fraction of its controls' distance: a cubic peaks at three quarters.
    static let turnPeakRatio: CGFloat = 0.75

    /// The stretch of the side a loop takes: at least the minimum band, and room for its label along the side.
    static func band(labelSize: CGSize?, leavesBelow: Bool) -> CGFloat {
        let labelExtent = labelSize.map { size in leavesBelow ? size.width + labelBandPadding.width : size.height + labelBandPadding.height } ?? 0
        return max(minimumBand, labelExtent)
    }

    /// The room on each side of a box, across the flow, that its loops and their labels take: the layout keeps a box
    /// centered in its place, so its place is widened on both sides.
    static func room(labelSizes: [CGSize?], leavesBelow: Bool) -> CGFloat {
        let reach = labelSizes.map { labelSize in labelSize.map { size in leavesBelow ? size.height : size.width } ?? 0 }.max() ?? 0
        return EntityRelationshipCardinalityMark.length + turnReach * turnPeakRatio + outerRoom + reach
    }

    /// One loop: its path, where it leaves and comes back, the direction into the box there, and its label's center.
    struct Loop {
        let path: DiagramPath
        let leave: CGPoint
        let back: CGPoint
        let intoBox: CGVector
        let labelCenter: CGPoint?
    }

    /// The loops of a box centered on `center`, one per band, in the order given.
    static func loops(center: CGPoint, boxSize: CGSize, bands: [CGFloat], labelSizes: [CGSize?], leavesBelow: Bool) -> [Loop] {
        let total = bands.reduce(0, +)
        let sideLength = leavesBelow ? boxSize.width : boxSize.height
        let scale = total > 0 ? min(1, max(sideLength - sideMargin, 0) / total) : 1
        var along = -total * scale / 2
        var loops: [Loop] = []
        for (band, labelSize) in zip(bands, labelSizes) {
            let scaledBand = band * scale
            loops.append(loop(center: center, boxSize: boxSize, offsetAlongSide: along + scaledBand / 2, band: scaledBand, labelSize: labelSize,
                              leavesBelow: leavesBelow))
            along += scaledBand
        }
        return loops
    }

    /// The loop whose middle is `offsetAlongSide` from the middle of its side.
    private static func loop(center: CGPoint, boxSize: CGSize, offsetAlongSide: CGFloat, band: CGFloat, labelSize: CGSize?, leavesBelow: Bool) -> Loop {
        // `outward` leaves the box through the side; `alongSide` runs along it.
        let outward = leavesBelow ? CGVector(dx: 0, dy: 1) : CGVector(dx: 1, dy: 0)
        let alongSide = leavesBelow ? CGVector(dx: 1, dy: 0) : CGVector(dx: 0, dy: 1)
        let sideMiddle = leavesBelow ? CGPoint(x: center.x + offsetAlongSide, y: center.y + boxSize.height / 2)
                                     : CGPoint(x: center.x + boxSize.width / 2, y: center.y + offsetAlongSide)
        func point(outwardBy distance: CGFloat, alongBy shift: CGFloat) -> CGPoint {
            CGPoint(x: sideMiddle.x + outward.dx * distance + alongSide.dx * shift, y: sideMiddle.y + outward.dy * distance + alongSide.dy * shift)
        }
        let spread = max(min(band / 2 - spreadInset, largestSpread), 1)
        let straight = EntityRelationshipCardinalityMark.length
        let turn = straight + turnReach
        let path = DiagramPath(start: point(outwardBy: 0, alongBy: -spread), segments: [
            .line(to: point(outwardBy: straight, alongBy: -spread)),
            .curve(to: point(outwardBy: straight, alongBy: spread), control1: point(outwardBy: turn, alongBy: -spread),
                   control2: point(outwardBy: turn, alongBy: spread)),
            .line(to: point(outwardBy: 0, alongBy: spread)),
        ])
        let labelDistance = straight + turnReach * turnPeakRatio + labelGap
        let labelCenter = labelSize.map { size in point(outwardBy: labelDistance + (leavesBelow ? size.height : size.width) / 2, alongBy: 0) }
        return Loop(path: path, leave: point(outwardBy: 0, alongBy: -spread), back: point(outwardBy: 0, alongBy: spread),
                    intoBox: CGVector(dx: -outward.dx, dy: -outward.dy), labelCenter: labelCenter)
    }
}
