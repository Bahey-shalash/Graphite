import CoreGraphics
import Foundation

/// The center line of a drawn shape as points, so that a shape can arrive as ink until Graphite has editable shapes.
/// Straight sides get a point at least every `maximumStraightSpacing`, because PencilKit draws a smooth curve through a
/// stroke's points and would bow a long side with only its two ends; curves are sampled within `tolerance`.
enum ShapeOutlineSampling {
    static let maximumStraightSpacing = 2.0

    /// The polyline through `points`, each side filled in with points.
    static func polyline(_ points: [CGPoint], closed: Bool) -> [CGPoint] {
        guard let first = points.first else { return [] }
        var sampled = [first]
        let corners = closed ? points + [first] : points
        for (start, end) in zip(corners, corners.dropFirst()) { sampled += straightSide(from: start, to: end) }
        return sampled
    }

    /// A rectangle of `size` centered at `center`, turned by `angleRadians` (clockwise with y downwards), starting at
    /// its top-left corner and closed.
    static func rectangle(center: CGPoint, size: CGSize, angleRadians: Double) -> [CGPoint] {
        let halfWidth = size.width / 2, halfHeight = size.height / 2
        let corners = [CGPoint(x: -halfWidth, y: -halfHeight), CGPoint(x: halfWidth, y: -halfHeight),
                       CGPoint(x: halfWidth, y: halfHeight), CGPoint(x: -halfWidth, y: halfHeight)]
        return polyline(corners.map { corner in turned(corner, by: angleRadians, about: center) }, closed: true)
    }

    /// An ellipse of `radii` centered at `center`, turned by `angleRadians`, closed.
    static func ellipse(center: CGPoint, radii: CGSize, angleRadians: Double, tolerance: Double) -> [CGPoint] {
        let largestRadius = max(abs(radii.width), abs(radii.height))
        guard largestRadius.isFinite, largestRadius > 0 else { return [center] }
        // Steps that keep a chord of the largest circle within the tolerance, as for an arc.
        let step = 2 * (2 * min(tolerance, largestRadius) / largestRadius).squareRoot()
        let pointCount = min(BezierFlattening.maximumPiecesPerSegment * 4, max(8, Int((2 * Double.pi / step).rounded(.up))))
        let points = (0..<pointCount).map { pointIndex in
            let angle = 2 * Double.pi * Double(pointIndex) / Double(pointCount)
            return turned(CGPoint(x: radii.width * cos(angle), y: radii.height * sin(angle)), by: angleRadians, about: center)
        }
        // Closed on the first point itself: the angle 2π computes a point a rounding error away.
        return points + points.prefix(1)
    }

    /// The arc of the circle through three points, from the first through the second to the third; a straight line
    /// when the three points are in a line.
    static func arc(through first: CGPoint, _ second: CGPoint, _ third: CGPoint, tolerance: Double) -> [CGPoint] {
        guard let center = circleCenter(first, second, third) else { return polyline([first, third], closed: false) }
        let radius = hypot(first.x - center.x, first.y - center.y)
        let startAngle = atan2(first.y - center.y, first.x - center.x)
        let middleAngle = atan2(second.y - center.y, second.x - center.x)
        let endAngle = atan2(third.y - center.y, third.x - center.x)
        // The sweep from the first to the third point that passes the second.
        var sweep = positiveAngle(endAngle - startAngle)
        if positiveAngle(middleAngle - startAngle) > sweep { sweep -= 2 * Double.pi }
        return [first] + BezierFlattening.arcPoints(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle + sweep,
                                                    tolerance: tolerance)
    }

    private static func straightSide(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length.isFinite else { return [end] }
        let pieceCount = min(BezierFlattening.maximumPiecesPerSegment, max(1, Int((length / maximumStraightSpacing).rounded(.up))))
        return (1...pieceCount).map { pieceIndex in
            let fraction = Double(pieceIndex) / Double(pieceCount)
            return CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
        }
    }

    private static func turned(_ offset: CGPoint, by angle: Double, about center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + offset.x * cos(angle) - offset.y * sin(angle), y: center.y + offset.x * sin(angle) + offset.y * cos(angle))
    }

    private static func circleCenter(_ first: CGPoint, _ second: CGPoint, _ third: CGPoint) -> CGPoint? {
        let determinant = 2 * (first.x * (second.y - third.y) + second.x * (third.y - first.y) + third.x * (first.y - second.y))
        guard abs(determinant) > 1e-9 else { return nil }
        let firstSquare = first.x * first.x + first.y * first.y
        let secondSquare = second.x * second.x + second.y * second.y
        let thirdSquare = third.x * third.x + third.y * third.y
        let centerX = (firstSquare * (second.y - third.y) + secondSquare * (third.y - first.y) + thirdSquare * (first.y - second.y)) / determinant
        let centerY = (firstSquare * (third.x - second.x) + secondSquare * (first.x - third.x) + thirdSquare * (second.x - first.x)) / determinant
        return CGPoint(x: centerX, y: centerY)
    }

    private static func positiveAngle(_ angle: Double) -> Double {
        let wrapped = fmod(angle, 2 * Double.pi)
        return wrapped < 0 ? wrapped + 2 * Double.pi : wrapped
    }
}
