import CoreGraphics
import Foundation

/// Splits quadratic and cubic Bézier segments into straight pieces no farther than a tolerance from the curve, for
/// stroke samples and outlines. The piece count follows from the curve's second derivative (a chord of a segment
/// whose parameter spans `h` departs from the curve by at most `max |B''| × h² / 8`), so straight segments give one
/// piece and the count never exceeds `maximumPiecesPerSegment`.
enum BezierFlattening {
    static let maximumPiecesPerSegment = 256

    /// The parameters (0 excluded, 1 included) at which to sample a quadratic segment.
    static func quadraticParameters(start: CGPoint, control: CGPoint, end: CGPoint, tolerance: Double) -> [Double] {
        let secondDifference = length(start.x - 2 * control.x + end.x, start.y - 2 * control.y + end.y)
        return parameters(pieceCount: pieceCount(maximumSecondDerivative: 2 * secondDifference, tolerance: tolerance))
    }

    /// The parameters (0 excluded, 1 included) at which to sample a cubic segment.
    static func cubicParameters(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint, tolerance: Double) -> [Double] {
        let firstDifference = length(start.x - 2 * control1.x + control2.x, start.y - 2 * control1.y + control2.y)
        let secondDifference = length(control1.x - 2 * control2.x + end.x, control1.y - 2 * control2.y + end.y)
        return parameters(pieceCount: pieceCount(maximumSecondDerivative: 6 * max(firstDifference, secondDifference), tolerance: tolerance))
    }

    static func quadraticPoint(start: CGPoint, control: CGPoint, end: CGPoint, at parameter: Double) -> CGPoint {
        CGPoint(x: quadraticValue(start.x, control.x, end.x, at: parameter), y: quadraticValue(start.y, control.y, end.y, at: parameter))
    }

    static func cubicPoint(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint, at parameter: Double) -> CGPoint {
        CGPoint(x: cubicValue(start.x, control1.x, control2.x, end.x, at: parameter),
                y: cubicValue(start.y, control1.y, control2.y, end.y, at: parameter))
    }

    static func quadraticValue(_ start: Double, _ control: Double, _ end: Double, at parameter: Double) -> Double {
        let remaining = 1 - parameter
        return remaining * remaining * start + 2 * remaining * parameter * control + parameter * parameter * end
    }

    static func cubicValue(_ start: Double, _ control1: Double, _ control2: Double, _ end: Double, at parameter: Double) -> Double {
        let remaining = 1 - parameter
        return remaining * remaining * remaining * start + 3 * remaining * remaining * parameter * control1
            + 3 * remaining * parameter * parameter * control2 + parameter * parameter * parameter * end
    }

    /// Points of a circular arc from `startAngle` to `endAngle` (radians, y downwards), the start excluded, spaced so
    /// no chord departs from the arc by more than the tolerance.
    static func arcPoints(center: CGPoint, radius: Double, startAngle: Double, endAngle: Double, tolerance: Double) -> [CGPoint] {
        let sweep = endAngle - startAngle
        guard radius.isFinite, sweep.isFinite, radius > 0 else { return [] }
        // A chord spanning the angle θ departs from the arc by r (1 − cos(θ / 2)) ≈ r θ² / 8.
        let largestStep = 2 * (2 * min(tolerance, radius) / radius).squareRoot()
        let pieceCount = min(maximumPiecesPerSegment, max(1, Int((abs(sweep) / largestStep).rounded(.up))))
        return (1...pieceCount).map { pieceIndex in
            let angle = startAngle + sweep * Double(pieceIndex) / Double(pieceCount)
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
    }

    private static func pieceCount(maximumSecondDerivative: Double, tolerance: Double) -> Int {
        guard maximumSecondDerivative.isFinite, tolerance > 0 else { return 1 }
        let pieces = (maximumSecondDerivative / (8 * tolerance)).squareRoot().rounded(.up)
        return min(maximumPiecesPerSegment, max(1, Int(pieces)))
    }

    private static func parameters(pieceCount: Int) -> [Double] {
        (1...pieceCount).map { pieceIndex in Double(pieceIndex) / Double(pieceCount) }
    }

    private static func length(_ horizontal: Double, _ vertical: Double) -> Double {
        (horizontal * horizontal + vertical * vertical).squareRoot()
    }
}
