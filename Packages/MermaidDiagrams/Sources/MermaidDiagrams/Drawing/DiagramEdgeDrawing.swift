import CoreGraphics

/// The geometry of an edge's line and marks, Pele's: a filled arrow, a filled circle, a cross.
enum DiagramEdgeDrawing {
    /// An arrow's half width as a fraction of its length.
    static let arrowHalfWidthRatio: CGFloat = 0.42
    /// How far back from the tip a circle's or a cross's center is.
    static let markCenterSetback: CGFloat = 4
    /// A circle's radius, and the length of each arm of a cross from its center.
    static let markRadius: CGFloat = 3.5

    static func path(_ path: DiagramPath) -> CGPath {
        let drawn = CGMutablePath()
        drawn.move(to: path.start)
        for segment in path.segments {
            switch segment {
            case .line(let end): drawn.addLine(to: end)
            case .curve(let end, let firstControl, let secondControl): drawn.addCurve(to: end, control1: firstControl, control2: secondControl)
            }
        }
        return drawn
    }

    /// Adds a mark to the paths that are filled (an arrow, a circle) or stroked (a cross).
    static func addMark(_ mark: DiagramEdgeMark, filled: CGMutablePath, stroked: CGMutablePath) {
        let direction = mark.direction
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        let tip = mark.tip
        let center = CGPoint(x: tip.x - direction.dx * markCenterSetback, y: tip.y - direction.dy * markCenterSetback)
        switch mark.arrowhead {
        case .none: break
        case .arrow:
            let length = DiagramEdgeMark.arrowLength
            let halfWidth = length * arrowHalfWidthRatio
            let base = CGPoint(x: tip.x - direction.dx * length, y: tip.y - direction.dy * length)
            filled.addLines(between: [tip, CGPoint(x: base.x + normal.dx * halfWidth, y: base.y + normal.dy * halfWidth),
                                      CGPoint(x: base.x - normal.dx * halfWidth, y: base.y - normal.dy * halfWidth)])
            filled.closeSubpath()
        case .circle:
            filled.addEllipse(in: CGRect(x: center.x - markRadius, y: center.y - markRadius, width: 2 * markRadius, height: 2 * markRadius))
        case .cross:
            let arms = [CGVector(dx: direction.dx + normal.dx, dy: direction.dy + normal.dy),
                        CGVector(dx: direction.dx - normal.dx, dy: direction.dy - normal.dy)]
            for arm in arms {
                stroked.move(to: CGPoint(x: center.x - arm.dx * markRadius, y: center.y - arm.dy * markRadius))
                stroked.addLine(to: CGPoint(x: center.x + arm.dx * markRadius, y: center.y + arm.dy * markRadius))
            }
        }
    }
}
