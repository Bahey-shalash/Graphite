import Foundation
import CoreGraphics

/// Tidying handwriting chosen with the lasso: straightening a line of writing that runs
/// uphill or downhill, and smoothing the tremor out of strokes. Apple Notes refines
/// handwriting with a model that has no public API; this is plain geometry, applied only
/// when asked, and undoable like any change of the ink.
public enum HandwritingTidying {
    /// A line of writing is straightened only when it runs within this angle of the
    /// horizontal: steeper ink is a drawing or a note written sideways on purpose.
    public static let maximumStraightenedAngle = CGFloat.pi / 6
    /// Ink reads as one line of writing when it spreads at least this much more along its
    /// direction than across it.
    public static let minimumLineSpreadRatio: CGFloat = 2.5
    /// Slants smaller than this, about half a degree, are left alone.
    public static let smallestStraightenedAngle: CGFloat = 0.008
    /// How many neighbours on each side a smoothed point is averaged with.
    public static let smoothingRadius = 2

    /// The angle from the horizontal of the line of writing the points make, measured in
    /// coordinates whose y axis points down, as a canvas's does: positive when the line
    /// runs downhill to the right. Nil when the points do not read as a line of writing, or
    /// already run level.
    public static func slantOfLine(through points: [CGPoint]) -> CGFloat? {
        guard points.count >= 3 else { return nil }
        let count = CGFloat(points.count)
        let meanX = points.reduce(0) { sum, point in sum + point.x } / count
        let meanY = points.reduce(0) { sum, point in sum + point.y } / count
        var varianceX: CGFloat = 0, varianceY: CGFloat = 0, covariance: CGFloat = 0
        for point in points {
            let deltaX = point.x - meanX, deltaY = point.y - meanY
            varianceX += deltaX * deltaX
            varianceY += deltaY * deltaY
            covariance += deltaX * deltaY
        }
        guard varianceX > 0, varianceX.isFinite, varianceY.isFinite, covariance.isFinite else { return nil }
        // The direction the points spread most along (their principal axis).
        let angle = 0.5 * atan2(2 * covariance, varianceX - varianceY)
        let alongSpread = spread(of: points, alongAngle: angle)
        let acrossSpread = spread(of: points, alongAngle: angle + .pi / 2)
        guard acrossSpread == 0 || alongSpread / acrossSpread >= minimumLineSpreadRatio else { return nil }
        guard abs(angle) <= maximumStraightenedAngle, abs(angle) >= smallestStraightenedAngle else { return nil }
        return angle
    }

    /// How far the points reach along a direction, from the first to the last of them.
    private static func spread(of points: [CGPoint], alongAngle angle: CGFloat) -> CGFloat {
        let directionX = cos(angle), directionY = sin(angle)
        let projections = points.map { point in point.x * directionX + point.y * directionY }
        guard let smallest = projections.min(), let largest = projections.max() else { return 0 }
        return largest - smallest
    }

    /// The points of a stroke with its tremor smoothed out: each point is the average of
    /// itself and its neighbours, fewer near the ends. The first and last points stay where
    /// they are, so strokes that met still meet; a stroke too short to smooth is returned as
    /// it is.
    public static func smoothed(_ points: [CGPoint], radius: Int = smoothingRadius) -> [CGPoint] {
        guard radius > 0, points.count > 2 * radius + 1 else { return points }
        return points.indices.map { index in
            guard index > 0, index < points.count - 1 else { return points[index] }
            let reach = min(radius, index, points.count - 1 - index)
            let neighbours = points[(index - reach)...(index + reach)]
            let count = CGFloat(neighbours.count)
            return CGPoint(x: neighbours.reduce(0) { sum, point in sum + point.x } / count,
                           y: neighbours.reduce(0) { sum, point in sum + point.y } / count)
        }
    }
}
