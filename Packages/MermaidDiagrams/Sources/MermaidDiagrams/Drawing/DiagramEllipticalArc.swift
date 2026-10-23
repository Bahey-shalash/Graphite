import CoreGraphics
import Foundation

/// An elliptical arc as SVG draws one from its end points (the small arc, swept with increasing angle, unrotated),
/// added to a Core Graphics path as cubic curves.
enum DiagramEllipticalArc {
    /// The most a single cubic curve sweeps: a quarter turn, which it follows closely.
    private static let largestCurveSweep = CGFloat.pi / 2

    /// Adds the arc from `start`, the path's current point, to `end`. Radii too small to reach are scaled up until
    /// they do, as SVG does.
    static func addArc(to path: CGMutablePath, from start: CGPoint, to end: CGPoint, radii: CGSize) {
        var radiusAcross = abs(radii.width)
        var radiusDown = abs(radii.height)
        guard radiusAcross > 0, radiusDown > 0, start != end else {
            path.addLine(to: end)
            return
        }
        let halfChordAcross = (start.x - end.x) / 2
        let halfChordDown = (start.y - end.y) / 2
        let reach = (halfChordAcross * halfChordAcross) / (radiusAcross * radiusAcross) + (halfChordDown * halfChordDown) / (radiusDown * radiusDown)
        if reach > 1 {
            radiusAcross *= reach.squareRoot()
            radiusDown *= reach.squareRoot()
        }
        let acrossSquared = radiusAcross * radiusAcross
        let downSquared = radiusDown * radiusDown
        let numerator = acrossSquared * downSquared - acrossSquared * halfChordDown * halfChordDown - downSquared * halfChordAcross * halfChordAcross
        let denominator = acrossSquared * halfChordDown * halfChordDown + downSquared * halfChordAcross * halfChordAcross
        // The small arc swept with increasing angle has its center on this side of the chord.
        let centerScale = (max(0, numerator) / denominator).squareRoot()
        let centerOffset = CGPoint(x: centerScale * radiusAcross * halfChordDown / radiusDown, y: -centerScale * radiusDown * halfChordAcross / radiusAcross)
        let center = CGPoint(x: centerOffset.x + (start.x + end.x) / 2, y: centerOffset.y + (start.y + end.y) / 2)
        let startAngle = atan2((halfChordDown - centerOffset.y) / radiusDown, (halfChordAcross - centerOffset.x) / radiusAcross)
        var sweep = atan2((-halfChordDown - centerOffset.y) / radiusDown, (-halfChordAcross - centerOffset.x) / radiusAcross) - startAngle
        if sweep < 0 { sweep += 2 * CGFloat.pi }
        addCurves(to: path, center: center, radii: CGSize(width: radiusAcross, height: radiusDown), startAngle: startAngle, sweep: sweep)
    }

    /// The arc as cubic curves of at most a quarter turn each.
    private static func addCurves(to path: CGMutablePath, center: CGPoint, radii: CGSize, startAngle: CGFloat, sweep: CGFloat) {
        let curveCount = max(1, Int((sweep / largestCurveSweep).rounded(.up)))
        let curveSweep = sweep / CGFloat(curveCount)
        // The distance along the tangent at which a cubic's control points make it follow a circle of radius 1.
        let controlDistance = 4 / 3 * tan(curveSweep / 4)
        func point(at angle: CGFloat) -> CGPoint { CGPoint(x: center.x + radii.width * cos(angle), y: center.y + radii.height * sin(angle)) }
        func tangent(at angle: CGFloat) -> CGVector { CGVector(dx: -radii.width * sin(angle), dy: radii.height * cos(angle)) }
        var angle = startAngle
        for _ in 0..<curveCount {
            let nextAngle = angle + curveSweep
            let from = point(at: angle)
            let to = point(at: nextAngle)
            let leaving = tangent(at: angle)
            let arriving = tangent(at: nextAngle)
            path.addCurve(to: to, control1: CGPoint(x: from.x + leaving.dx * controlDistance, y: from.y + leaving.dy * controlDistance),
                          control2: CGPoint(x: to.x - arriving.dx * controlDistance, y: to.y - arriving.dy * controlDistance))
            angle = nextAngle
        }
    }
}
