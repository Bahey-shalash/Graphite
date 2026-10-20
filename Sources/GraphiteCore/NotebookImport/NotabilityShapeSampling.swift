import CoreGraphics
import Foundation

/// A Notability shape (`Docs/Notability-format.md`, Shapes) as ink: a straight line from start to end, or a quadratic
/// Bézier through the control point, at the shape's width, in page points, cut at the page's top and bottom edges as
/// a curve is (`NotabilityCurveSampling`). Graphite has no editable shapes yet, so a shape arrives as ink drawn just
/// before the curve it precedes.
enum NotabilityShapeSampling {
    /// Nil when the shape is not a line or stores no width; no stroke when none of it is on the page.
    static func strokes(for shape: NotabilityShape, transform: (CGPoint) -> CGPoint, pointsPerUnit: Double,
                        pageHeightInPoints: Double) -> [ImportedStroke]? {
        guard shape.kind == .line, let unitWidth = shape.width, unitWidth.isFinite, unitWidth > 0 else { return nil }
        let start = transform(shape.start), end = transform(shape.end)
        let points: [CGPoint]
        if let control = shape.quadraticControlPoint.map(transform) {
            points = [start] + BezierFlattening.quadraticParameters(start: start, control: control, end: end,
                                                                    tolerance: NotabilityCurveSampling.flatteningToleranceInPoints).map { parameter in
                BezierFlattening.quadraticPoint(start: start, control: control, end: end, at: parameter)
            }
        } else {
            points = ShapeOutlineSampling.polyline([start, end], closed: false)
        }
        let width = unitWidth * pointsPerUnit
        let samples = points.map { point in
            ImportedStrokeSample(location: point, width: width, force: nil, azimuthRadians: nil, altitudeRadians: nil)
        }
        return NotabilityCurveSampling.pieces(of: samples, pageHeightInPoints: pageHeightInPoints).compactMap { piece in
            ImportedStroke(ink: .monoline, color: shape.color, samples: piece, outline: nil).keepingFiniteSamples()
        }
    }
}
