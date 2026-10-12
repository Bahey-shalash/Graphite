#if canImport(UIKit)
import Foundation
import PencilKit

/// Graphite's even highlighter. PencilKit's marker draws as a felt tip does: broader as
/// Apple Pencil tilts, and broader or finer as it turns, so the same highlight over a line
/// of text comes out a different height each time. With the even highlighter, a marker
/// stroke just drawn is drawn again through the same points with one tip, the tip an upright
/// Pencil or a finger draws with, at an even pressure, whatever the angle the Pencil was
/// held at: a stroke across a line of text is as tall as the tool is wide.
///
/// PencilKit gives no way to change a stroke while it is drawn (see `HistoryCanvasView`),
/// so the stroke takes its even width when the Pencil lifts. Drawn upright, or with a
/// finger, it does not change at the lift; drawn tilted, it changes to the upright stroke
/// there. A dissolve over that change was tried and left out: the canvas as it was, laid
/// over the canvas as it became, darkened every translucent highlight on the page while
/// it faded.
public enum EvenHighlighter {
    /// The angle of an upright tip: the Pencil held straight up from the page.
    static let uprightAltitude: CGFloat = .pi / 2
    /// The direction of the tip: PencilKit's marker tip is a chisel, and turned this way its
    /// long side stands across the page's rows, as an upright Pencil's and a finger's do.
    static let tipAzimuth: CGFloat = .pi / 2
    /// How much longer than a point's size the marker's chisel draws, measured on PencilKit
    /// (iOS 27, macOS 27): a point of size 38 draws a band 57 to 58 points tall across a
    /// horizontal stroke, and PencilKit gives a finger's or an upright Pencil's points two
    /// thirds of the tool's width. An earlier version gave the points the whole width,
    /// lengthwise, which drew highlights about 40 percent thinner than the tool.
    static let chiselLengthPerPointSize: CGFloat = 1.5

    /// The stroke with every point's tip drawing a band `width` points across in the
    /// drawing, upright and at the stroke's average pressure. Nil for a stroke that is not
    /// marker ink or has no points, and for a width that is not a positive number.
    public static func evenStroke(_ stroke: PKStroke, width: CGFloat) -> PKStroke? {
        let controlPoints = Array(stroke.path)
        guard stroke.ink.inkType == .marker, !controlPoints.isEmpty, width.isFinite, width > 0 else { return nil }
        // A point's size is in the stroke's own coordinates, which its transform scales
        // into the drawing's.
        let transform = stroke.transform
        let transformScale = abs(transform.a * transform.d - transform.b * transform.c).squareRoot()
        guard transformScale.isFinite, transformScale > 0 else { return nil }
        let tipSide = width / chiselLengthPerPointSize / transformScale
        let tipSize = CGSize(width: tipSide, height: tipSide)
        let averageForce = controlPoints.map(\.force).reduce(0, +) / CGFloat(controlPoints.count)
        let evenPoints = controlPoints.map { point in
            PKStrokePoint(location: point.location, timeOffset: point.timeOffset, size: tipSize, opacity: point.opacity,
                          force: averageForce, azimuth: tipAzimuth, altitude: uprightAltitude)
        }
        // The same random seed keeps the ink's texture as it was drawn.
        return PKStroke(ink: stroke.ink, path: PKStrokePath(controlPoints: evenPoints, creationDate: stroke.path.creationDate),
                        transform: transform, mask: stroke.mask, randomSeed: stroke.randomSeed)
    }
}
#endif
