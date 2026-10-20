import CoreGraphics
import Foundation

/// Samples one Goodnotes stroke into the strokes Graphite writes: one per subpath, in page points, the lasso offset
/// applied. Ball pen and highlighter keep one width; the fountain and brush pens take the width stored at each
/// center-line point and keep Goodnotes' outline for the PDF appearance; the pencil keeps the Pencil's force, azimuth
/// and altitude. Shapes, tape and the older varying-width ink are counted in the report instead (design steps 4 and
/// later).
enum GoodnotesStrokePlanner {
    /// How far a sampled piece may depart from the curve, in points.
    static let flatteningToleranceInPoints = 0.1

    private struct PageTransform {
        let offset: CGVector

        func point(_ unitPoint: CGPoint) -> CGPoint {
            CGPoint(x: (unitPoint.x + offset.dx) * GoodnotesPagePlanner.pointsPerUnit, y: (unitPoint.y + offset.dy) * GoodnotesPagePlanner.pointsPerUnit)
        }

        func length(_ unitLength: Double) -> Double { unitLength * GoodnotesPagePlanner.pointsPerUnit }
    }

    static func strokes(for stroke: GoodnotesStroke, tally: inout ImportReportTally) -> [ImportedStroke] {
        if let shape = stroke.shape {
            guard let geometry = shape.geometry, let width = shape.width ?? pathWidth(stroke.path) else {
                tally.count(.element(.shape))
                return []
            }
            tally.count(.shapeAsInk)
            if stroke.isHighlighter { tally.count(.highlighter) }
            if case .constantWidth(let path) = stroke.path, !path.dashPattern.isEmpty { tally.count(.dashes) }
            return [shapeStroke(geometry, width: width, stroke: stroke)]
        }
        if stroke.isTape {
            tally.count(.tape)
            return []
        }
        let transform = PageTransform(offset: stroke.offset)
        switch stroke.path {
        case .constantWidth(let path):
            if stroke.isHighlighter { tally.count(.highlighter) }
            if !path.dashPattern.isEmpty { tally.count(.dashes) }
            return constantWidthStrokes(path, ink: stroke.isHighlighter ? .highlighter : .monoline, color: stroke.color, transform: transform)
        case .varyingWidth(let path):
            guard let centerLine = path.centerLine else {
                tally.count(.olderVaryingWidthInk)
                return []
            }
            return [varyingWidthStroke(centerLine, outline: path.outline, color: stroke.color, transform: transform)]
        case .olderVaryingWidth:
            tally.count(.olderVaryingWidthInk)
            return []
        case .pencil(let path):
            tally.count(.pencil)
            return pencilStrokes(path, color: stroke.color, transform: transform)
        case .unknownLayout:
            tally.count(.element(.strokeInUnknownLayout))
            return []
        }
    }

    private static func constantWidthStrokes(_ path: GoodnotesConstantWidthPath, ink: ImportedStroke.Ink, color: NotebookImportColor,
                                             transform: PageTransform) -> [ImportedStroke] {
        let width = transform.length(path.width)
        return path.subpaths.map { subpath in
            var current = transform.point(subpath.start)
            var samples = [ImportedStrokeSample(location: current, width: width, force: nil, azimuthRadians: nil, altitudeRadians: nil)]
            for curve in subpath.curves {
                let control = transform.point(curve.control), end = transform.point(curve.end)
                for parameter in BezierFlattening.quadraticParameters(start: current, control: control, end: end, tolerance: flatteningToleranceInPoints) {
                    samples.append(ImportedStrokeSample(location: BezierFlattening.quadraticPoint(start: current, control: control, end: end, at: parameter),
                                                        width: width, force: nil, azimuthRadians: nil, altitudeRadians: nil))
                }
                current = end
            }
            return ImportedStroke(ink: ink, color: color, samples: samples, outline: nil)
        }
    }

    /// The width at each sample follows the same quadratic as the position, between the widths stored at the
    /// curve's start, control and end points.
    private static func varyingWidthStroke(_ centerLine: GoodnotesCenterLine, outline: [[GoodnotesOutlineCommand]], color: NotebookImportColor,
                                           transform: PageTransform) -> ImportedStroke {
        var current = (point: transform.point(centerLine.start.point), width: transform.length(centerLine.start.width))
        var samples = [ImportedStrokeSample(location: current.point, width: current.width, force: nil, azimuthRadians: nil, altitudeRadians: nil)]
        for curve in centerLine.curves {
            let control = (point: transform.point(curve.control.point), width: transform.length(curve.control.width))
            let end = (point: transform.point(curve.end.point), width: transform.length(curve.end.width))
            for parameter in BezierFlattening.quadraticParameters(start: current.point, control: control.point, end: end.point,
                                                                  tolerance: flatteningToleranceInPoints) {
                samples.append(ImportedStrokeSample(
                    location: BezierFlattening.quadraticPoint(start: current.point, control: control.point, end: end.point, at: parameter),
                    width: BezierFlattening.quadraticValue(current.width, control.width, end.width, at: parameter),
                    force: nil, azimuthRadians: nil, altitudeRadians: nil))
            }
            current = end
        }
        return ImportedStroke(ink: .fountainPen, color: color, samples: samples,
                              outline: GoodnotesOutlineFlattening.subpaths(outline, transform: transform.point, length: transform.length))
    }

    private static func pencilStrokes(_ path: GoodnotesPencilPath, color: NotebookImportColor, transform: PageTransform) -> [ImportedStroke] {
        let width = transform.length(path.width)
        return path.subpaths.map { subpath in
            var current = subpath.start
            var samples = [pencilSample(current, width: width, transform: transform)]
            for curve in subpath.curves {
                let start = transform.point(current.point), control = transform.point(curve.control.point), end = transform.point(curve.end.point)
                for parameter in BezierFlattening.quadraticParameters(start: start, control: control, end: end, tolerance: flatteningToleranceInPoints) {
                    samples.append(ImportedStrokeSample(
                        location: BezierFlattening.quadraticPoint(start: start, control: control, end: end, at: parameter), width: width,
                        force: BezierFlattening.quadraticValue(current.force, curve.control.force, curve.end.force, at: parameter),
                        azimuthRadians: azimuth(from: current.azimuthRadians, control: curve.control.azimuthRadians, end: curve.end.azimuthRadians,
                                                at: parameter),
                        altitudeRadians: BezierFlattening.quadraticValue(current.altitudeRadians, curve.control.altitudeRadians,
                                                                         curve.end.altitudeRadians, at: parameter)))
                }
                current = curve.end
            }
            return ImportedStroke(ink: .pencil, color: color, samples: samples, outline: nil)
        }
    }

    /// A shape's outline as one stroke of the shape's width, in page points with the stroke's offset.
    private static func shapeStroke(_ geometry: GoodnotesShape.Geometry, width: Double, stroke: GoodnotesStroke) -> ImportedStroke {
        let tolerance = flatteningToleranceInPoints / GoodnotesPagePlanner.pointsPerUnit
        let unitPoints: [CGPoint] = switch geometry {
        case .polyline(let points): ShapeOutlineSampling.polyline(points, closed: false)
        case .arcThroughThreePoints(let first, let second, let third): ShapeOutlineSampling.arc(through: first, second, third, tolerance: tolerance)
        case .rectangle(let center, let size, let angleRadians): ShapeOutlineSampling.rectangle(center: center, size: size, angleRadians: angleRadians)
        case .ellipse(let center, let radii, let angleRadians):
            ShapeOutlineSampling.ellipse(center: center, radii: radii, angleRadians: angleRadians, tolerance: tolerance)
        }
        let transform = PageTransform(offset: stroke.offset)
        let samples = unitPoints.map { point in
            ImportedStrokeSample(location: transform.point(point), width: transform.length(width), force: nil, azimuthRadians: nil, altitudeRadians: nil)
        }
        return ImportedStroke(ink: stroke.isHighlighter ? .highlighter : .monoline, color: stroke.color, samples: samples, outline: nil)
    }

    /// The one width a path stores, for a shape that stores none of its own; nil for a path with a width per point or
    /// a layout not known.
    private static func pathWidth(_ path: GoodnotesStrokePath) -> Double? {
        switch path {
        case .constantWidth(let path): path.width
        case .olderVaryingWidth(let path): path.width
        case .pencil(let path): path.width
        case .varyingWidth, .unknownLayout: nil
        }
    }

    /// Azimuths run from −π to π, so a turn across ±π is taken the short way round before interpolating.
    private static func azimuth(from start: Double, control: Double, end: Double, at parameter: Double) -> Double {
        let unwrappedControl = start + remainder(control - start, 2 * Double.pi)
        let unwrappedEnd = unwrappedControl + remainder(end - unwrappedControl, 2 * Double.pi)
        return remainder(BezierFlattening.quadraticValue(start, unwrappedControl, unwrappedEnd, at: parameter), 2 * Double.pi)
    }

    private static func pencilSample(_ sample: GoodnotesPencilSample, width: Double, transform: PageTransform) -> ImportedStrokeSample {
        ImportedStrokeSample(location: transform.point(sample.point), width: width, force: sample.force, azimuthRadians: sample.azimuthRadians,
                             altitudeRadians: sample.altitudeRadians)
    }
}
