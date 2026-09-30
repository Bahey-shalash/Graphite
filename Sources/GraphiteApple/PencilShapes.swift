#if canImport(UIKit)
import Foundation
import PencilKit
import GraphiteCore

/// Graphite's shape tool: a stroke just drawn becomes the line, ellipse, or polygon it was
/// meant to be (`ShapeRecognizer`), in the same ink, width, and pressure.
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
        let controlPoints = Array(stroke.path)
        guard !controlPoints.isEmpty else { return nil }
        // Interpolated points follow the drawn curve evenly, whatever the drawing speed.
        let drawnPoints = stroke.path.interpolatedPoints(by: .distance(3)).map { point in point.location.applying(stroke.transform) }
        guard let shape = ShapeRecognizer.recognize(drawnPoints) else { return nil }
        let pointCount = Double(controlPoints.count)
        let averageSize = CGSize(width: controlPoints.map(\.size.width).reduce(0, +) / pointCount,
                                 height: controlPoints.map(\.size.height).reduce(0, +) / pointCount)
        let averageOpacity = controlPoints.map(\.opacity).reduce(0, +) / pointCount
        let averageForce = controlPoints.map(\.force).reduce(0, +) / pointCount
        let firstPoint = controlPoints[0]
        let outline = shape.outlinePoints(spacing: max(2, min(averageSize.width, 6)))
        let shapePoints = outline.enumerated().map { pointIndex, location in
            PKStrokePoint(location: location, timeOffset: Double(pointIndex) * timeBetweenPoints, size: averageSize,
                          opacity: averageOpacity, force: averageForce, azimuth: firstPoint.azimuth, altitude: firstPoint.altitude)
        }
        let path = PKStrokePath(controlPoints: shapePoints, creationDate: stroke.path.creationDate)
        // The outline is in drawing coordinates, so the stroke needs no transform of its own.
        return PKStroke(ink: stroke.ink, path: path, transform: .identity, mask: nil)
    }

    /// Even timing, as if the shape were drawn at a steady speed; PencilKit uses it only
    /// for rendering effects that depend on speed.
    private static let timeBetweenPoints = 0.008
}
#endif
