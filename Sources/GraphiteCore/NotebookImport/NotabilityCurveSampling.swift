import CoreGraphics
import Foundation

/// Samples a Notability curve, a chain of cubic Bézier segments (knot, control, control, knot, …), into PencilKit
/// points on one page. The width, force, altitude and azimuth stored at each knot are interpolated linearly along
/// each segment. Samples beyond the page's top or bottom edge (by more than the stroke's width) are dropped, and the
/// stroke is cut there into pieces that each keep one sample past the edge, so the ink reaches it.
enum NotabilityCurveSampling {
    static let flatteningToleranceInPoints = 0.1

    static func strokes(for curve: NotabilityCurve, transform: (CGPoint) -> CGPoint, pointsPerUnit: Double,
                        pageHeightInPoints: Double) -> [ImportedStroke] {
        let samples = samples(of: curve, transform: transform, pointsPerUnit: pointsPerUnit)
        let ink: ImportedStroke.Ink = curve.style == .highlighter ? .highlighter : .pen
        return pieces(of: samples, pageHeightInPoints: pageHeightInPoints).compactMap { piece in
            ImportedStroke(ink: ink, color: curve.color, samples: piece, outline: nil).keepingFiniteSamples()
        }
    }

    private static func samples(of curve: NotabilityCurve, transform: (CGPoint) -> CGPoint, pointsPerUnit: Double) -> [ImportedStrokeSample] {
        let points = curve.points.map(transform)
        let knots = curve.knots.map { knot in sampleValues(knot, curveWidth: curve.width * pointsPerUnit) }
        guard let firstPoint = points.first, let firstKnot = knots.first else { return [] }
        var samples = [sample(at: firstPoint, firstKnot)]
        let segmentCount = min((points.count - 1) / 3, knots.count - 1)
        for segmentIndex in 0..<max(segmentCount, 0) {
            let start = points[3 * segmentIndex], control1 = points[3 * segmentIndex + 1]
            let control2 = points[3 * segmentIndex + 2], end = points[3 * segmentIndex + 3]
            let startKnot = knots[segmentIndex], endKnot = knots[segmentIndex + 1]
            for parameter in BezierFlattening.cubicParameters(start: start, control1: control1, control2: control2, end: end,
                                                              tolerance: flatteningToleranceInPoints) {
                let location = BezierFlattening.cubicPoint(start: start, control1: control1, control2: control2, end: end, at: parameter)
                samples.append(sample(at: location, startKnot.interpolated(to: endKnot, at: parameter)))
            }
        }
        return samples
    }

    /// A knot's values in page points and radians.
    private struct KnotValues {
        let width: Double
        let force: Double
        let azimuthRadians: Double?
        let altitudeRadians: Double?

        func interpolated(to end: KnotValues, at parameter: Double) -> KnotValues {
            KnotValues(width: width + (end.width - width) * parameter, force: force + (end.force - force) * parameter,
                       azimuthRadians: azimuthRadians.flatMap { start in
                           end.azimuthRadians.map { finish in remainder(start + remainder(finish - start, 2 * Double.pi) * parameter, 2 * Double.pi) }
                       },
                       altitudeRadians: altitudeRadians.flatMap { start in end.altitudeRadians.map { finish in start + (finish - start) * parameter } })
        }
    }

    private static func sampleValues(_ knot: NotabilityKnot, curveWidth: Double) -> KnotValues {
        KnotValues(width: curveWidth * knot.widthFactor, force: knot.force,
                   azimuthRadians: knot.azimuthUnitVector.map { vector in atan2(vector.vertical, vector.horizontal) },
                   altitudeRadians: knot.altitudeAngle)
    }

    private static func sample(at location: CGPoint, _ values: KnotValues) -> ImportedStrokeSample {
        ImportedStrokeSample(location: location, width: values.width, force: values.force, azimuthRadians: values.azimuthRadians,
                             altitudeRadians: values.altitudeRadians)
    }

    /// Runs of samples on the page, each extended by one sample past the edge where it leaves or enters.
    private static func pieces(of samples: [ImportedStrokeSample], pageHeightInPoints: Double) -> [[ImportedStrokeSample]] {
        let isOnPage = samples.map { sample in sample.location.y >= -sample.width && sample.location.y <= pageHeightInPoints + sample.width }
        var pieces: [[ImportedStrokeSample]] = []
        var sampleIndex = 0
        while sampleIndex < samples.count {
            guard isOnPage[sampleIndex] else {
                sampleIndex += 1
                continue
            }
            let runStart = sampleIndex
            while sampleIndex < samples.count && isOnPage[sampleIndex] { sampleIndex += 1 }
            let pieceStart = max(runStart - 1, 0), pieceEnd = min(sampleIndex + 1, samples.count)
            pieces.append(Array(samples[pieceStart..<pieceEnd]))
        }
        return pieces
    }
}
