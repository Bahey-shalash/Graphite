#if canImport(UIKit)
import Foundation
import PencilKit

/// Graphite's even highlighter. PencilKit's marker draws as a felt tip does: broader as
/// Apple Pencil tilts, and broader or finer as it turns, so the same highlight over a line
/// of text comes out a different height each time. With the even highlighter, a marker
/// stroke just drawn is drawn again through the same points with one tip as wide as the tool,
/// at an even pressure, turned across the stroke at every point, whatever the angle the
/// Pencil was held at: a highlight is as tall across a line of text as the tool is wide, and
/// as wide in any other direction.
///
/// PencilKit gives no way to change a stroke while it is drawn, and its live stroke follows
/// the Pencil's tilt. So while the even highlighter is in use, the canvas draws with an
/// invisible stand-in of the tool (`invisibleStandIn(for:)`) and shows the stroke itself, as
/// the band the even stroke will draw (`bandPath(through:width:)`), until the even stroke
/// replaces the invisible one at the lift (`HistoryCanvasView`).
public enum EvenHighlighter {
    /// The angle of an upright tip: the Pencil held straight up from the page.
    static let uprightAltitude: CGFloat = .pi / 2
    /// The direction of the tip on a stroke along the page's rows: PencilKit's marker tip is
    /// a chisel, and turned this way its long side stands across the rows, as an upright
    /// Pencil's and a finger's do. On a stroke in any other direction the tip turns with it.
    static let tipAzimuth: CGFloat = .pi / 2
    /// How much longer than a point's size the marker's chisel draws, measured on PencilKit
    /// (iOS 27, macOS 27): a point of size 38 draws a band 57 to 58 points tall across a
    /// horizontal stroke, and PencilKit gives a finger's or an upright Pencil's points two
    /// thirds of the tool's width. An earlier version gave the points the whole width,
    /// lengthwise, which drew highlights about 40 percent thinner than the tool.
    public static let chiselLengthPerPointSize: CGFloat = 1.5
    /// The opacity of every point. PencilKit gives a marker's points more than 1, and less the
    /// faster the Pencil moves (1.5 down to about 1.3 for a quick finger stroke), and draws
    /// them stronger the more they have: 1 draws the color at about four fifths, 1.5 at about
    /// nine tenths. The even stroke takes the value of a slow, steady stroke everywhere.
    public static let tipOpacity: CGFloat = 1.5

    /// The stroke with every point's tip drawing a band `width` points across in the
    /// drawing, turned across the stroke and at the stroke's average pressure, in `ink`
    /// (the stroke's own when nil). Nil for a stroke that is not marker ink or has no points,
    /// and for a width that is not a positive number.
    public static func evenStroke(_ stroke: PKStroke, width: CGFloat, ink: PKInk? = nil) -> PKStroke? {
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
        let azimuths = tipAzimuths(along: controlPoints.map(\.location), reach: tipSide)
        let evenPoints = zip(controlPoints, azimuths).map { point, azimuth in
            PKStrokePoint(location: point.location, timeOffset: point.timeOffset, size: tipSize, opacity: tipOpacity,
                          force: averageForce, azimuth: azimuth, altitude: uprightAltitude)
        }
        // The same random seed keeps the ink's texture as it was drawn.
        return PKStroke(ink: ink ?? stroke.ink, path: PKStrokePath(controlPoints: evenPoints, creationDate: stroke.path.creationDate),
                        transform: transform, mask: stroke.mask, randomSeed: stroke.randomSeed)
    }

    /// The tip's direction at each point: across the stroke there, from the points `reach`
    /// before and after it, so a hand's tremble does not turn it. A stroke too short to have
    /// a direction, as a dot, has the tip of a stroke along the rows.
    static func tipAzimuths(along locations: [CGPoint], reach: CGFloat) -> [CGFloat] {
        func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat { hypot(second.x - first.x, second.y - first.y) }
        let directedAzimuths: [CGFloat?] = locations.indices.map { pointIndex in
            let location = locations[pointIndex]
            var earlierIndex = pointIndex
            while earlierIndex > 0, distance(locations[earlierIndex], location) < reach { earlierIndex -= 1 }
            var laterIndex = pointIndex
            while laterIndex < locations.count - 1, distance(locations[laterIndex], location) < reach { laterIndex += 1 }
            let earlier = locations[earlierIndex], later = locations[laterIndex]
            guard distance(earlier, later) > 0 else { return nil }
            return atan2(later.y - earlier.y, later.x - earlier.x) + tipAzimuth
        }
        // A point without a direction of its own takes the one before it, or the first.
        var lastAzimuth = directedAzimuths.compactMap { azimuth in azimuth }.first ?? tipAzimuth
        return directedAzimuths.map { azimuth in
            if let azimuth { lastAzimuth = azimuth }
            return lastAzimuth
        }
    }

    /// A tool that draws nothing, with the highlighter's width and ink type, for the canvas
    /// to draw with while the even highlighter is in use: its live stroke would follow the
    /// Pencil's tilt and then change at the lift.
    public static func invisibleStandIn(for highlighter: PKInkingTool) -> PKInkingTool {
        let invisibleColor = highlighter.color.withAlphaComponent(0)
        return PKInkingTool(highlighter.inkType, color: invisibleColor, width: highlighter.width, azimuth: highlighter.azimuth)
    }

    /// Whether ink is the invisible stand-in's, which no stroke may keep.
    public static func isInvisible(_ ink: PKInk) -> Bool {
        ink.inkType == .marker && ink.color.cgColor.alpha == 0
    }

    /// How tall the band of an even stroke is for the tool's width, and how far it reaches
    /// past the stroke's ends, measured on PencilKit (iOS 27): a highlight 24 points wide
    /// draws 22 points tall, and about 3 points past each end, where its corners soften.
    public static let bandHeightPerWidth: CGFloat = 22.0 / 24
    public static let bandEndPerWidth: CGFloat = 3.0 / 24

    /// How strongly the canvas draws an even stroke's band, for a band of the tool's width
    /// in the canvas's points, as a fraction of the ink's color: PencilKit softens a
    /// marker's edges over a few points, so a narrow band never reaches its full color.
    /// Measured on a PencilKit canvas (iOS 27) for highlights 8, 20 and 50 points wide, at
    /// opacities from 0.4 to 1: their middles are 0.86, 0.90 and 0.99 of the color.
    public static func bandOpacity(forWidth width: CGFloat) -> CGFloat {
        let measuredOpacities: [(width: CGFloat, opacity: CGFloat)] = [(8, 0.86), (20, 0.90), (50, 0.99)]
        guard let first = measuredOpacities.first, let last = measuredOpacities.last else { return 1 }
        if width <= first.width { return first.opacity }
        if width >= last.width { return last.opacity }
        for (narrower, wider) in zip(measuredOpacities, measuredOpacities.dropFirst()) where width <= wider.width {
            let fraction = (width - narrower.width) / (wider.width - narrower.width)
            return narrower.opacity + (wider.opacity - narrower.opacity) * fraction
        }
        return last.opacity
    }

    /// The band an even stroke through these points draws, `width` being the tool's width in
    /// the same coordinates, as a path to stroke `bandHeightPerWidth` times as wide with butt
    /// ends: the stroke's line, carried past each end as far as the band reaches.
    public static func bandPath(through points: [CGPoint], width: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard let firstPoint = points.first, let lastPoint = points.last else { return path }
        let reach = width * bandEndPerWidth
        func extended(from endPoint: CGPoint, awayFrom innerPoint: CGPoint) -> CGPoint {
            let length = hypot(endPoint.x - innerPoint.x, endPoint.y - innerPoint.y)
            guard length > 0 else { return endPoint }
            return CGPoint(x: endPoint.x + (endPoint.x - innerPoint.x) / length * reach, y: endPoint.y + (endPoint.y - innerPoint.y) / length * reach)
        }
        // A dot, which has no direction, reaches along the rows, as its tip does.
        let secondPoint = points.dropFirst().first { point in point != firstPoint } ?? CGPoint(x: firstPoint.x + 1, y: firstPoint.y)
        let secondToLastPoint = points.dropLast().last { point in point != lastPoint } ?? CGPoint(x: lastPoint.x - 1, y: lastPoint.y)
        // Rounded through the points, as PencilKit smooths a stroke: a curve from the middle of
        // each segment to the middle of the next, bending at the point between them.
        let startPoint = extended(from: firstPoint, awayFrom: secondPoint)
        path.move(to: startPoint)
        path.addLine(to: firstPoint)
        let innerPoints = Array(points.dropFirst().dropLast())
        var previousPoint = firstPoint
        for (pointIndex, point) in innerPoints.enumerated() {
            let nextPoint = pointIndex + 1 < innerPoints.count ? innerPoints[pointIndex + 1] : lastPoint
            if pointIndex == 0 { path.addLine(to: CGPoint(x: (previousPoint.x + point.x) / 2, y: (previousPoint.y + point.y) / 2)) }
            path.addQuadCurve(to: CGPoint(x: (point.x + nextPoint.x) / 2, y: (point.y + nextPoint.y) / 2), control: point)
            previousPoint = point
        }
        path.addLine(to: lastPoint)
        path.addLine(to: extended(from: lastPoint, awayFrom: secondToLastPoint))
        return path
    }
}
#endif
