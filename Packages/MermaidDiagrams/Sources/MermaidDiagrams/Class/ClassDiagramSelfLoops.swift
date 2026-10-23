import CoreGraphics

/// Relations from a class to itself, as Pele draws them: each loops out of the box's right side and back, the next
/// one reaching 8 points farther and leaving 6 points farther from the middle, with its text beyond it. The class's
/// place in its rank is widened on both sides by the room its loops take, so that it stays centered.
enum ClassDiagramSelfLoops {
    /// How far the first loop's control points reach beyond the box, and how much farther each next loop's.
    static let loopReach: CGFloat = 26
    static let reachStep: CGFloat = 8
    /// How far from the middle of the side the first loop leaves and comes back, and how much farther each next one.
    static let firstSpread: CGFloat = 8
    static let spreadStep: CGFloat = 6
    /// A loop stays this far inside the top and bottom of its box.
    static let spreadClearance: CGFloat = 4
    /// The room around a loop's text, and the gap between the loop's reach and its text's room.
    static let textRoom: CGFloat = 12
    static let textGap: CGFloat = 4

    /// The room beside its box that one loop with text `textWidth` wide takes.
    static func room(textWidth: CGFloat?) -> CGFloat {
        guard let textWidth, textWidth > 0 else { return loopReach }
        return loopReach + textWidth + textRoom
    }

    /// One loop: where it leaves the box and where it comes back (both on the right side), its path between the
    /// marks, and the center of its text.
    struct Loop {
        let leave: CGPoint
        let back: CGPoint
        let path: DiagramPath
        let textCenter: CGPoint
    }

    /// The `loopIndex`-th loop of a box at `center`.
    static func loop(center: CGPoint, boxSize: CGSize, loopIndex: Int, startTrim: CGFloat, endTrim: CGFloat, textWidth: CGFloat) -> Loop {
        let side = center.x + boxSize.width / 2
        let spread = min(boxSize.height / 2 - spreadClearance, firstSpread + CGFloat(loopIndex) * spreadStep)
        let reach = loopReach + CGFloat(loopIndex) * reachStep
        let leave = CGPoint(x: side, y: center.y - spread)
        let back = CGPoint(x: side, y: center.y + spread)
        let path = DiagramPath(start: CGPoint(x: side + startTrim, y: leave.y), segments: [
            .curve(to: CGPoint(x: side + endTrim, y: back.y), control1: CGPoint(x: side + reach + startTrim, y: leave.y),
                   control2: CGPoint(x: side + reach + endTrim, y: back.y)),
        ])
        return Loop(leave: leave, back: back, path: path, textCenter: CGPoint(x: side + reach + textGap + (textWidth + textRoom) / 2, y: center.y))
    }
}
