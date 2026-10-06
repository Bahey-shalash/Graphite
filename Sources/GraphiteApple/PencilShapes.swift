#if canImport(UIKit)
import Foundation
import PencilKit
import GraphiteCore

/// Graphite's shape tool: a stroke just drawn becomes the line, arc, arrow, ellipse, or
/// polygon it was meant to be (`ShapeRecognizer`), in the same ink, width, and pressure.
public enum PencilShapes {
    /// The drawing with its newest stroke replaced by its shape, when `drawing` differs
    /// from `previousDrawing` by that one stroke and the stroke is recognized; nil otherwise.
    public static func replacingNewStroke(in drawing: PKDrawing, previousDrawing: PKDrawing) -> PKDrawing? {
        guard let change = PencilDrawingChange(from: previousDrawing, to: drawing), let newStrokeIndex = change.appendedStrokeIndex else { return nil }
        var strokes = drawing.strokes
        guard newStrokeIndex < strokes.count, let shapeStroke = shapeStroke(for: strokes[newStrokeIndex]) else { return nil }
        strokes[newStrokeIndex] = shapeStroke
        return PKDrawing(strokes: strokes)
    }

    /// The stroke redrawn as its recognized shape, or nil when it is not a shape.
    public static func shapeStroke(for stroke: PKStroke) -> PKStroke? {
        guard let footprint = StrokeFootprint(averaging: stroke) else { return nil }
        // Interpolated points follow the drawn curve evenly, whatever the drawing speed.
        let drawnPoints = stroke.path.interpolatedPoints(by: .distance(3)).map { point in point.location.applying(stroke.transform) }
        guard let shape = ShapeRecognizer.recognize(drawnPoints) else { return nil }
        return shapeStroke(shape, ink: stroke.ink, footprint: footprint, creationDate: stroke.path.creationDate)
    }

    /// A stroke along the shape's outline, in drawing coordinates, as the ink would have
    /// drawn it with an even hand.
    public static func shapeStroke(_ shape: RecognizedShape, ink: PKInk, footprint: StrokeFootprint, creationDate: Date = Date()) -> PKStroke {
        let outline = shape.outlinePoints(spacing: max(2, min(footprint.size.width, 6)))
        let shapePoints = outline.enumerated().map { pointIndex, location in
            PKStrokePoint(location: location, timeOffset: Double(pointIndex) * timeBetweenPoints, size: footprint.size,
                          opacity: footprint.opacity, force: footprint.force, azimuth: footprint.azimuth, altitude: footprint.altitude)
        }
        // The outline is in drawing coordinates, so the stroke needs no transform of its own.
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: shapePoints, creationDate: creationDate), transform: .identity, mask: nil)
    }

    /// Even timing, as if the shape were drawn at a steady speed; PencilKit uses it only
    /// for rendering effects that depend on speed.
    private static let timeBetweenPoints = 0.008
}
/// How an ink marks the page under an even hand: the size, opacity and pressure of a
/// stroke's points, averaged, and the angle the Pencil was held at. A tool's width does not
/// tell this (a pencil set to four points draws a line under two), so it is taken from a
/// stroke drawn with the tool.
public struct StrokeFootprint: Equatable, Sendable {
    public var size: CGSize
    public var opacity: CGFloat
    public var force: CGFloat
    public var azimuth: CGFloat
    public var altitude: CGFloat

    public init(size: CGSize, opacity: CGFloat, force: CGFloat, azimuth: CGFloat, altitude: CGFloat) {
        self.size = size
        self.opacity = opacity
        self.force = force
        self.azimuth = azimuth
        self.altitude = altitude
    }

    /// Nil for a stroke without points.
    public init?(averaging stroke: PKStroke) {
        let controlPoints = Array(stroke.path)
        guard let firstPoint = controlPoints.first else { return nil }
        let pointCount = CGFloat(controlPoints.count)
        size = CGSize(width: controlPoints.map(\.size.width).reduce(0, +) / pointCount, height: controlPoints.map(\.size.height).reduce(0, +) / pointCount)
        opacity = controlPoints.map(\.opacity).reduce(0, +) / pointCount
        force = controlPoints.map(\.force).reduce(0, +) / pointCount
        azimuth = firstPoint.azimuth
        altitude = firstPoint.altitude
    }
}
#endif
