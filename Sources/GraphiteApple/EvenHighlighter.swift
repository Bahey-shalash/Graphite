#if canImport(UIKit)
import Foundation
import PencilKit

/// Graphite's even highlighter. PencilKit's marker draws as a felt tip does: broader as
/// Apple Pencil tilts, and broader or finer as it turns, so the same highlight over a line
/// of text comes out a different height each time. With the even highlighter, a marker
/// stroke just drawn is drawn again through the same points with one tip, as wide as the
/// tool, held upright, at an even pressure, whatever the angle the Pencil was held at.
///
/// PencilKit gives no way to change a stroke while it is drawn (see `HistoryCanvasView`),
/// so the stroke takes its even width when the Pencil lifts.
public enum EvenHighlighter {
    /// The angle of an upright tip: the Pencil held straight up from the page.
    static let uprightAltitude: CGFloat = .pi / 2
    /// The direction of the tip, along the page's rows, so a highlight drawn across a line
    /// of text is exactly as tall as the tool is wide.
    static let tipAzimuth: CGFloat = 0

    /// The stroke with every point's tip `width` points across in the drawing, upright and
    /// at the stroke's average pressure. Nil for a stroke that is not marker ink or has no
    /// points, and for a width that is not a positive number.
    public static func evenStroke(_ stroke: PKStroke, width: CGFloat) -> PKStroke? {
        let controlPoints = Array(stroke.path)
        guard stroke.ink.inkType == .marker, !controlPoints.isEmpty, width.isFinite, width > 0 else { return nil }
        // A point's size is in the stroke's own coordinates, which its transform scales
        // into the drawing's.
        let transform = stroke.transform
        let transformScale = abs(transform.a * transform.d - transform.b * transform.c).squareRoot()
        guard transformScale.isFinite, transformScale > 0 else { return nil }
        let tipSize = CGSize(width: width / transformScale, height: width / transformScale)
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
