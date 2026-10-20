import CoreGraphics
import Foundation

/// Turns a varying-width stroke's outline (`Docs/Goodnotes-format.md`, Varying width) into closed polygons in page
/// points: one per center-line segment, each starting at its move, cubics and arcs flattened, and a flat cap a
/// straight edge through its point. An arc continues from the current point, which lies on its circle at the start
/// angle, to the end angle, turning by their difference.
enum GoodnotesOutlineFlattening {
    static func subpaths(_ outline: [[GoodnotesOutlineCommand]], transform: (CGPoint) -> CGPoint,
                         length: (Double) -> Double) -> [[CGPoint]] {
        outline.compactMap { commands in
            let polygon = polygon(commands, transform: transform, length: length)
            return polygon.count > 2 ? polygon : nil
        }
    }

    private static func polygon(_ commands: [GoodnotesOutlineCommand], transform: (CGPoint) -> CGPoint, length: (Double) -> Double) -> [CGPoint] {
        let tolerance = GoodnotesStrokePlanner.flatteningToleranceInPoints
        var points: [CGPoint] = []
        for command in commands {
            switch command {
            case .move(let point):
                points.append(transform(point))
            case .cubic(let control1, let control2, let end):
                guard let start = points.last else { continue }
                let first = transform(control1), second = transform(control2), last = transform(end)
                for parameter in BezierFlattening.cubicParameters(start: start, control1: first, control2: second, end: last, tolerance: tolerance) {
                    points.append(BezierFlattening.cubicPoint(start: start, control1: first, control2: second, end: last, at: parameter))
                }
            case .arc(let center, let radius, let startAngle, let endAngle):
                points += BezierFlattening.arcPoints(center: transform(center), radius: length(radius), startAngle: startAngle,
                                                     endAngle: endAngle, tolerance: tolerance)
            case .flatCap(let point):
                points.append(transform(point))
            }
        }
        return points
    }
}
