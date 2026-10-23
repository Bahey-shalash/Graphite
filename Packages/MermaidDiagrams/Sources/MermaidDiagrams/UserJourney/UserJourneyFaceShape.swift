import CoreGraphics
import Foundation

/// Pele's face for a user journey's score: a circle 11 points in radius, two eyes, and a mouth that smiles, stays
/// straight or frowns. Measured from the face's center, y running down.
enum UserJourneyFaceShape {
    /// Where the right eye is; the left one mirrors it.
    static let eyeOffset = CGVector(dx: 3.6, dy: -2.8)
    static let eyeRadius: CGFloat = 1.3
    /// A smile or a frown is an arc of a circle this wide between corners this far apart.
    static let curvedMouthRadius: CGFloat = 6
    static let curvedMouthHalfWidth: CGFloat = 5
    /// How far below the center a smile's corners are, and a frown's.
    static let smileCornerDepth: CGFloat = 2
    static let frownCornerDepth: CGFloat = 6.5
    /// A straight mouth's half width and depth below the center.
    static let straightMouthHalfWidth: CGFloat = 4.5
    static let straightMouthDepth: CGFloat = 4.5

    /// Adds the face's circle at `center` to `circles`, its eyes to `eyes` and its mouth to `mouths`.
    static func add(_ mood: UserJourneyMood, at center: CGPoint, circles: CGMutablePath, eyes: CGMutablePath, mouths: CGMutablePath) {
        let radius = UserJourneyGeometry.faceRadius
        circles.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        for side in [-1.0, 1.0] {
            let eye = CGPoint(x: center.x + side * eyeOffset.dx, y: center.y + eyeOffset.dy)
            eyes.addEllipse(in: CGRect(x: eye.x - eyeRadius, y: eye.y - eyeRadius, width: 2 * eyeRadius, height: 2 * eyeRadius))
        }
        switch mood {
        case .happy: addCurvedMouth(at: center, cornerDepth: smileCornerDepth, bulgesDown: true, to: mouths)
        case .sad: addCurvedMouth(at: center, cornerDepth: frownCornerDepth, bulgesDown: false, to: mouths)
        case .neutral:
            mouths.move(to: CGPoint(x: center.x - straightMouthHalfWidth, y: center.y + straightMouthDepth))
            mouths.addLine(to: CGPoint(x: center.x + straightMouthHalfWidth, y: center.y + straightMouthDepth))
        }
    }

    /// The shorter arc between the corners, below them for a smile and above them for a frown, from left to right.
    private static func addCurvedMouth(at center: CGPoint, cornerDepth: CGFloat, bulgesDown: Bool, to mouths: CGMutablePath) {
        let rise = (curvedMouthRadius * curvedMouthRadius - curvedMouthHalfWidth * curvedMouthHalfWidth).squareRoot()
        let arcCenter = CGPoint(x: center.x, y: center.y + cornerDepth + (bulgesDown ? -rise : rise))
        let cornerAngle = atan2(bulgesDown ? rise : -rise, curvedMouthHalfWidth)
        let leftAngle = bulgesDown ? CGFloat.pi - cornerAngle : -CGFloat.pi - cornerAngle
        mouths.move(to: CGPoint(x: center.x - curvedMouthHalfWidth, y: center.y + cornerDepth))
        // Angles grow from the x axis toward the y axis, which runs down here: a smile runs from the left corner down
        // through the bottom to the right one by decreasing angles, a frown up through the top by increasing ones.
        mouths.addArc(center: arcCenter, radius: curvedMouthRadius, startAngle: leftAngle, endAngle: cornerAngle, clockwise: bulgesDown)
    }
}
