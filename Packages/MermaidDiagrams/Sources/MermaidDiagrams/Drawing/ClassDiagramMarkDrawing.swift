import CoreGraphics

/// The geometry of a relation's marks, Pele's: a hollow triangle, a diamond filled for composition and hollow for
/// aggregation, the flowchart's filled arrow, and a hollow ring.
enum ClassDiagramMarkDrawing {
    /// Adds a mark to the paths that are filled in the line color (an arrow, a composition's diamond) and those
    /// stroked in it (a triangle, both diamonds, a ring).
    static func addMark(_ mark: ClassDiagramRelationMark, filled: CGMutablePath, stroked: CGMutablePath) {
        let direction = mark.direction
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        let tip = mark.tip
        func point(back distance: CGFloat, across offset: CGFloat) -> CGPoint {
            CGPoint(x: tip.x - direction.dx * distance + normal.dx * offset, y: tip.y - direction.dy * distance + normal.dy * offset)
        }
        switch mark.end {
        case .none: break
        case .inheritance:
            let length = ClassDiagramMarkGeometry.triangleLength
            let halfWidth = ClassDiagramMarkGeometry.triangleHalfWidth
            stroked.addLines(between: [tip, point(back: length, across: halfWidth), point(back: length, across: -halfWidth)])
            stroked.closeSubpath()
        case .composition:
            let diamond = diamondPath(tip: tip, point: point)
            filled.addPath(diamond)
            stroked.addPath(diamond)
        case .aggregation:
            stroked.addPath(diamondPath(tip: tip, point: point))
        case .arrow:
            DiagramEdgeDrawing.addMark(DiagramEdgeMark(arrowhead: .arrow, tip: tip, direction: direction), filled: filled, stroked: stroked)
        case .lollipop:
            let radius = ClassDiagramMarkGeometry.ringRadius
            let center = point(back: radius, across: 0)
            stroked.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        }
    }

    /// A diamond from the tip back along the line, its widest at half its length.
    private static func diamondPath(tip: CGPoint, point: (_ distance: CGFloat, _ offset: CGFloat) -> CGPoint) -> CGPath {
        let length = ClassDiagramMarkGeometry.diamondLength
        let halfWidth = ClassDiagramMarkGeometry.diamondHalfWidth
        let diamond = CGMutablePath()
        diamond.addLines(between: [tip, point(length / 2, halfWidth), point(length, 0), point(length / 2, -halfWidth)])
        diamond.closeSubpath()
        return diamond
    }
}
