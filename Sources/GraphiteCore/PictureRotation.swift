import Foundation
import CoreGraphics

/// Pictures turned by any angle about their own middle, on a drawing or on a PDF page. A
/// turned picture keeps its frame, the upright rectangle it fills before it is turned, and
/// an angle; it covers that frame turned about the frame's middle.
///
/// Angles are in radians and turn the x axis toward the y axis of the coordinates they are
/// used in. Where y points down, as in a drawing and on screen, a positive angle turns
/// clockwise; where it points up, as on a PDF page, counterclockwise.
public enum PictureRotation {
    /// How close to a quarter turn (0°, 90°, 180° or 270°) a picture turned by hand is
    /// taken to be exactly that turn, so it can be put back straight.
    public static let snappingToleranceRadians = 5 * Double.pi / 180

    /// The same angle without whole turns, more than -π and at most π. An angle that is not
    /// a number is none.
    public static func normalized(_ radians: Double) -> Double {
        guard radians.isFinite else { return 0 }
        let angle = radians.truncatingRemainder(dividingBy: 2 * .pi)
        if angle > .pi { return angle - 2 * .pi }
        if angle <= -.pi { return angle + 2 * .pi }
        return angle
    }

    /// The angle, or the quarter turn it is within `snappingToleranceRadians` of.
    public static func snapped(_ radians: Double) -> Double {
        normalized(isNearQuarterTurn(radians) ? nearestQuarterTurn(to: radians) : radians)
    }

    /// Whether the angle is within `snappingToleranceRadians` of a quarter turn.
    public static func isNearQuarterTurn(_ radians: Double) -> Bool {
        radians.isFinite && abs(radians - nearestQuarterTurn(to: radians)) <= snappingToleranceRadians
    }

    private static func nearestQuarterTurn(to radians: Double) -> Double {
        let quarterTurn = Double.pi / 2
        return (radians / quarterTurn).rounded() * quarterTurn
    }

    /// `point` turned by `radians` about `pivot`.
    public static func point(_ point: CGPoint, turnedBy radians: Double, about pivot: CGPoint) -> CGPoint {
        guard radians != 0 else { return point }
        let cosine = cos(radians), sine = sin(radians)
        let offsetX = Double(point.x - pivot.x), offsetY = Double(point.y - pivot.y)
        return CGPoint(x: Double(pivot.x) + offsetX * cosine - offsetY * sine, y: Double(pivot.y) + offsetX * sine + offsetY * cosine)
    }

    /// `vector`, a distance and direction such as a drag, turned by `radians`.
    public static func vector(_ vector: CGPoint, turnedBy radians: Double) -> CGPoint {
        point(vector, turnedBy: radians, about: .zero)
    }

    /// The smallest upright rectangle around `rectangle` turned by `radians` about its middle.
    public static func boundingRectangle(of rectangle: CGRect, turnedBy radians: Double) -> CGRect {
        guard radians != 0 else { return rectangle }
        let cosine = abs(cos(radians)), sine = abs(sin(radians))
        let width = Double(rectangle.width) * cosine + Double(rectangle.height) * sine
        let height = Double(rectangle.width) * sine + Double(rectangle.height) * cosine
        return CGRect(x: Double(rectangle.midX) - width / 2, y: Double(rectangle.midY) - height / 2, width: width, height: height)
    }

    /// Whether `point` is inside `rectangle` turned by `radians` about its middle.
    public static func rectangle(_ rectangle: CGRect, turnedBy radians: Double, contains point: CGPoint) -> Bool {
        let middle = CGPoint(x: rectangle.midX, y: rectangle.midY)
        return rectangle.contains(Self.point(point, turnedBy: -radians, about: middle))
    }

    /// `rectangle`, the same size, with its middle turned by `radians` about `pivot`. Of a
    /// part of a turned picture, given upright in the picture's frame, it is the frame of
    /// the part as a picture of its own, turned as the picture is: what a crop keeps.
    public static func rectangle(_ rectangle: CGRect, withMiddleTurnedBy radians: Double, about pivot: CGPoint) -> CGRect {
        // Exactly the same rectangle, not one rebuilt from its middle, when nothing turns.
        guard radians != 0 else { return rectangle }
        let middle = point(CGPoint(x: rectangle.midX, y: rectangle.midY), turnedBy: radians, about: pivot)
        let width = Double(rectangle.width), height = Double(rectangle.height)
        return CGRect(x: Double(middle.x) - width / 2, y: Double(middle.y) - height / 2, width: width, height: height)
    }
}
