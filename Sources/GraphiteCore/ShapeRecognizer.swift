import Foundation
import CoreGraphics

/// The shape a hand-drawn stroke was meant to be.
public enum RecognizedShape: Equatable, Sendable {
    case line(start: CGPoint, end: CGPoint)
    /// `rotation` is in radians; a circle has equal radii and no rotation.
    case ellipse(center: CGPoint, horizontalRadius: Double, verticalRadius: Double, rotation: Double)
    /// A closed outline through its corners, in drawing order: a triangle, a rectangle, or
    /// another polygon of up to six sides.
    case polygon(corners: [CGPoint])

    /// Points along the outline about `spacing` apart. Corners are repeated, so a stroke
    /// that smooths between its points keeps them sharp. Closed outlines end where they start.
    public func outlinePoints(spacing: Double) -> [CGPoint] {
        let step = max(spacing, 0.5)
        switch self {
        case .line(let start, let end):
            return Self.segmentPoints(from: start, to: end, step: step, includesEnd: true)
        case .ellipse(let center, let horizontalRadius, let verticalRadius, let rotation):
            // Ramanujan's approximation of the perimeter.
            let perimeter = Double.pi * (3 * (horizontalRadius + verticalRadius)
                - ((3 * horizontalRadius + verticalRadius) * (horizontalRadius + 3 * verticalRadius)).squareRoot())
            let pointCount = max(Self.minimumEllipsePointCount, Int((perimeter / step).rounded(.up)))
            return (0...pointCount).map { pointIndex in
                let angle = 2 * Double.pi * Double(pointIndex) / Double(pointCount)
                let localX = horizontalRadius * cos(angle), localY = verticalRadius * sin(angle)
                return CGPoint(x: center.x + localX * cos(rotation) - localY * sin(rotation),
                               y: center.y + localX * sin(rotation) + localY * cos(rotation))
            }
        case .polygon(let corners):
            guard let firstCorner = corners.first else { return [] }
            var points: [CGPoint] = []
            for (cornerIndex, corner) in corners.enumerated() {
                let nextCorner = corners[(cornerIndex + 1) % corners.count]
                points += Array(repeating: corner, count: Self.cornerRepetitionCount)
                points += Self.segmentPoints(from: corner, to: nextCorner, step: step, includesEnd: false).dropFirst()
            }
            return points + Array(repeating: firstCorner, count: Self.cornerRepetitionCount)
        }
    }

    private static let minimumEllipsePointCount = 32
    private static let cornerRepetitionCount = 3

    private static func segmentPoints(from start: CGPoint, to end: CGPoint, step: Double, includesEnd: Bool) -> [CGPoint] {
        let length = hypot(end.x - start.x, end.y - start.y)
        let segmentCount = max(1, Int((length / step).rounded(.up)))
        let lastIndex = includesEnd ? segmentCount : segmentCount - 1
        return (0...max(lastIndex, 0)).map { pointIndex in
            let fraction = Double(pointIndex) / Double(segmentCount)
            return CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
        }
    }
}

/// Recognizes lines, circles and ellipses, triangles, rectangles, and simple polygons in a
/// hand-drawn stroke, for Graphite's shape tool. A stroke that is none of them, such as
/// handwriting or an open curve, is not recognized and stays as drawn.
///
/// The thresholds are relative to the stroke's size, so a shape is recognized the same
/// way at any zoom. They favour leaving a stroke alone over replacing it with a shape the
/// writer did not mean.
public enum ShapeRecognizer {
    /// Strokes smaller than this, in points, are marks or dots, never shapes.
    static let minimumShapeSize = 16.0
    /// A closed stroke ends within this fraction of its length of where it started.
    static let maximumClosingGapFraction = 0.14
    /// A line's points stay within this fraction of its length from the straight segment.
    static let maximumLineDeviationFraction = 0.05
    /// A line is at most this much longer than the distance between its ends; waves and
    /// handwriting are longer.
    static let minimumLineStraightness = 0.93
    /// Mean distance of the points from a fitted ellipse, relative to its size.
    static let maximumEllipseResidual = 0.085
    /// Radii this close to each other make a circle.
    static let minimumCircleRadiusRatio = 0.86
    /// Rectangles and ellipses within this many degrees of the page axes are straightened.
    static let axisSnapDegrees = 10.0
    /// A rectangle's corners are within this many degrees of a right angle.
    static let rightAngleToleranceDegrees = 20.0
    static let maximumPolygonCornerCount = 6

    public static func recognize(_ strokePoints: [CGPoint]) -> RecognizedShape? {
        let points = removingRepeatedPoints(strokePoints)
        guard points.count >= 5, let first = points.first, let last = points.last else { return nil }
        let bounds = boundingBox(of: points)
        let size = hypot(bounds.width, bounds.height)
        guard size >= minimumShapeSize else { return nil }
        let length = pathLength(of: points)
        let closingGap = distance(first, last)
        if closingGap > max(maximumClosingGapFraction * length, 6) {
            return recognizeLine(points, length: length)
        }
        if let ellipse = recognizeEllipse(points, size: size) { return ellipse }
        return recognizePolygon(points, size: size)
    }

    // MARK: Open strokes

    private static func recognizeLine(_ points: [CGPoint], length: Double) -> RecognizedShape? {
        guard let start = points.first, let end = points.last else { return nil }
        let chord = distance(start, end)
        // A straight stroke's length is close to the distance between its ends.
        guard chord >= minimumShapeSize, chord >= minimumLineStraightness * length else { return nil }
        let deviation = points.map { point in distance(point, toSegmentFrom: start, to: end) }.max() ?? 0
        guard deviation <= max(maximumLineDeviationFraction * chord, 3) else { return nil }
        return .line(start: start, end: snapToAxis(end, around: start))
    }

    /// A line within the snap angle of horizontal or vertical is made exactly so, about its start.
    private static func snapToAxis(_ end: CGPoint, around start: CGPoint) -> CGPoint {
        let angle = atan2(end.y - start.y, end.x - start.x) * 180 / .pi
        let angleFromHorizontal = min(abs(angle), 180 - abs(angle))
        if angleFromHorizontal <= axisSnapDegrees / 2 { return CGPoint(x: end.x, y: start.y) }
        if abs(angleFromHorizontal - 90) <= axisSnapDegrees / 2 { return CGPoint(x: start.x, y: end.y) }
        return end
    }

    // MARK: Ellipses

    private static func recognizeEllipse(_ points: [CGPoint], size: Double) -> RecognizedShape? {
        let centroid = CGPoint(x: points.map(\.x).reduce(0, +) / Double(points.count), y: points.map(\.y).reduce(0, +) / Double(points.count))
        var covarianceXX = 0.0, covarianceYY = 0.0, covarianceXY = 0.0
        for point in points {
            let deltaX = point.x - centroid.x, deltaY = point.y - centroid.y
            covarianceXX += deltaX * deltaX; covarianceYY += deltaY * deltaY; covarianceXY += deltaX * deltaY
        }
        var rotation = 0.5 * atan2(2 * covarianceXY, covarianceXX - covarianceYY)
        // Extents along the principal axes give the radii.
        var minimumAlong = Double.infinity, maximumAlong = -Double.infinity
        var minimumAcross = Double.infinity, maximumAcross = -Double.infinity
        for point in points {
            let deltaX = point.x - centroid.x, deltaY = point.y - centroid.y
            let along = deltaX * cos(rotation) + deltaY * sin(rotation)
            let across = -deltaX * sin(rotation) + deltaY * cos(rotation)
            minimumAlong = min(minimumAlong, along); maximumAlong = max(maximumAlong, along)
            minimumAcross = min(minimumAcross, across); maximumAcross = max(maximumAcross, across)
        }
        var horizontalRadius = (maximumAlong - minimumAlong) / 2
        var verticalRadius = (maximumAcross - minimumAcross) / 2
        guard horizontalRadius > 1, verticalRadius > 1 else { return nil }
        let center = CGPoint(x: centroid.x + ((maximumAlong + minimumAlong) / 2) * cos(rotation) - ((maximumAcross + minimumAcross) / 2) * sin(rotation),
                             y: centroid.y + ((maximumAlong + minimumAlong) / 2) * sin(rotation) + ((maximumAcross + minimumAcross) / 2) * cos(rotation))
        let residual = points.map { point -> Double in
            let deltaX = point.x - center.x, deltaY = point.y - center.y
            let along = deltaX * cos(rotation) + deltaY * sin(rotation)
            let across = -deltaX * sin(rotation) + deltaY * cos(rotation)
            return abs(((along / horizontalRadius) * (along / horizontalRadius) + (across / verticalRadius) * (across / verticalRadius)).squareRoot() - 1)
        }.reduce(0, +) / Double(points.count)
        guard residual <= maximumEllipseResidual, coversFullTurn(points, around: center) else { return nil }
        if min(horizontalRadius, verticalRadius) / max(horizontalRadius, verticalRadius) >= minimumCircleRadiusRatio {
            let radius = (horizontalRadius + verticalRadius) / 2
            return .ellipse(center: center, horizontalRadius: radius, verticalRadius: radius, rotation: 0)
        }
        // Straighten an ellipse that is nearly upright or level.
        let rotationDegrees = rotation * 180 / .pi
        let nearestQuarterTurn = (rotationDegrees / 90).rounded() * 90
        if abs(rotationDegrees - nearestQuarterTurn) <= axisSnapDegrees {
            if Int(nearestQuarterTurn / 90) % 2 != 0 { swap(&horizontalRadius, &verticalRadius) }
            rotation = 0
        }
        return .ellipse(center: center, horizontalRadius: horizontalRadius, verticalRadius: verticalRadius, rotation: rotation)
    }

    /// Whether the stroke goes all the way around `center`, rather than doubling back.
    private static func coversFullTurn(_ points: [CGPoint], around center: CGPoint) -> Bool {
        var totalAngle = 0.0
        for (previous, current) in zip(points, points.dropFirst()) {
            var change = atan2(current.y - center.y, current.x - center.x) - atan2(previous.y - center.y, previous.x - center.x)
            if change > .pi { change -= 2 * .pi }
            if change < -.pi { change += 2 * .pi }
            totalAngle += change
        }
        return abs(totalAngle) >= 1.7 * .pi
    }

    // MARK: Polygons

    private static func recognizePolygon(_ points: [CGPoint], size: Double) -> RecognizedShape? {
        var corners = simplify(points + [points[0]], tolerance: max(0.045 * size, 2.5))
        // The closing point repeats the first.
        if corners.count > 1, let firstCorner = corners.first, let lastCorner = corners.last, distance(firstCorner, lastCorner) < 0.12 * size {
            corners.removeLast()
        }
        corners = mergingNearbyCorners(corners, minimumSpacing: 0.12 * size)
        corners = removingStraightCorners(corners, minimumTurnDegrees: 25)
        guard corners.count >= 3, corners.count <= maximumPolygonCornerCount, coversFullTurn(points, around: centroid(of: corners)) else { return nil }
        guard pointsStayNearOutline(points, corners: corners, tolerance: max(0.07 * size, 3)) else { return nil }
        if corners.count == 4, let rectangle = rectangle(fitting: corners) { return .polygon(corners: rectangle) }
        return .polygon(corners: corners)
    }

    /// A rectangle through four corners that are each near a right angle; nil otherwise.
    private static func rectangle(fitting corners: [CGPoint]) -> [CGPoint]? {
        for cornerIndex in corners.indices {
            let previous = corners[(cornerIndex + corners.count - 1) % corners.count]
            let next = corners[(cornerIndex + 1) % corners.count]
            let angle = interiorAngleDegrees(at: corners[cornerIndex], previous: previous, next: next)
            guard abs(angle - 90) <= rightAngleToleranceDegrees else { return nil }
        }
        // The direction of the edges, averaged over all four after folding them into one quarter turn.
        var sumOfSines = 0.0, sumOfCosines = 0.0
        for cornerIndex in corners.indices {
            let start = corners[cornerIndex], end = corners[(cornerIndex + 1) % corners.count]
            let edgeAngle = atan2(end.y - start.y, end.x - start.x)
            sumOfSines += sin(4 * edgeAngle); sumOfCosines += cos(4 * edgeAngle)
        }
        var rotation = atan2(sumOfSines, sumOfCosines) / 4
        if abs(rotation * 180 / .pi) <= axisSnapDegrees { rotation = 0 }
        let center = centroid(of: corners)
        var minimumAlong = Double.infinity, maximumAlong = -Double.infinity
        var minimumAcross = Double.infinity, maximumAcross = -Double.infinity
        var alongTotal = 0.0, acrossTotal = 0.0
        for corner in corners {
            let deltaX = corner.x - center.x, deltaY = corner.y - center.y
            let along = deltaX * cos(rotation) + deltaY * sin(rotation)
            let across = -deltaX * sin(rotation) + deltaY * cos(rotation)
            minimumAlong = min(minimumAlong, along); maximumAlong = max(maximumAlong, along)
            minimumAcross = min(minimumAcross, across); maximumAcross = max(maximumAcross, across)
            alongTotal += abs(along); acrossTotal += abs(across)
        }
        // Half the average extent on each axis, so one stray corner does not stretch the rectangle.
        let halfWidth = alongTotal / 4, halfHeight = acrossTotal / 4
        guard halfWidth > 1, halfHeight > 1 else { return nil }
        let localCorners = [(-halfWidth, -halfHeight), (halfWidth, -halfHeight), (halfWidth, halfHeight), (-halfWidth, halfHeight)]
        var fitted = localCorners.map { along, across in
            CGPoint(x: center.x + along * cos(rotation) - across * sin(rotation), y: center.y + along * sin(rotation) + across * cos(rotation))
        }
        // Start where the stroke started and keep its direction.
        let startIndex = fitted.indices.min { leftIndex, rightIndex in distance(fitted[leftIndex], corners[0]) < distance(fitted[rightIndex], corners[0]) } ?? 0
        fitted = Array(fitted[startIndex...] + fitted[..<startIndex])
        if signedArea(of: fitted) * signedArea(of: corners) < 0 { fitted = [fitted[0]] + fitted.dropFirst().reversed() }
        return fitted
    }

    private static func pointsStayNearOutline(_ points: [CGPoint], corners: [CGPoint], tolerance: Double) -> Bool {
        let meanDistance = points.map { point in
            corners.indices.map { cornerIndex in
                distance(point, toSegmentFrom: corners[cornerIndex], to: corners[(cornerIndex + 1) % corners.count])
            }.min() ?? .infinity
        }.reduce(0, +) / Double(points.count)
        return meanDistance <= tolerance
    }

    // MARK: Geometry

    static func removingRepeatedPoints(_ points: [CGPoint]) -> [CGPoint] {
        var kept: [CGPoint] = []
        for point in points where point.x.isFinite && point.y.isFinite {
            if let last = kept.last, distance(last, point) < 0.5 { continue }
            kept.append(point)
        }
        return kept
    }

    /// Ramer–Douglas–Peucker simplification, iterative so a long stroke cannot exhaust the stack.
    static func simplify(_ points: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var isKept = [Bool](repeating: false, count: points.count)
        isKept[0] = true; isKept[points.count - 1] = true
        var pendingRanges = [(0, points.count - 1)]
        while let (startIndex, endIndex) = pendingRanges.popLast() {
            guard endIndex > startIndex + 1 else { continue }
            var farthestIndex = startIndex, farthestDistance = 0.0
            for pointIndex in (startIndex + 1)..<endIndex {
                let pointDistance = distance(points[pointIndex], toSegmentFrom: points[startIndex], to: points[endIndex])
                if pointDistance > farthestDistance { farthestDistance = pointDistance; farthestIndex = pointIndex }
            }
            guard farthestDistance > tolerance else { continue }
            isKept[farthestIndex] = true
            pendingRanges.append((startIndex, farthestIndex))
            pendingRanges.append((farthestIndex, endIndex))
        }
        return points.indices.filter { pointIndex in isKept[pointIndex] }.map { pointIndex in points[pointIndex] }
    }

    private static func mergingNearbyCorners(_ corners: [CGPoint], minimumSpacing: Double) -> [CGPoint] {
        var merged: [CGPoint] = []
        for corner in corners {
            if let last = merged.last, distance(last, corner) < minimumSpacing {
                merged[merged.count - 1] = CGPoint(x: (last.x + corner.x) / 2, y: (last.y + corner.y) / 2)
            } else {
                merged.append(corner)
            }
        }
        if merged.count > 2, let first = merged.first, let last = merged.last, distance(first, last) < minimumSpacing {
            merged[0] = CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2)
            merged.removeLast()
        }
        return merged
    }

    /// Drops corners where the outline barely turns, which a wobbly straight edge leaves.
    private static func removingStraightCorners(_ corners: [CGPoint], minimumTurnDegrees: Double) -> [CGPoint] {
        var kept = corners
        var didRemove = true
        while didRemove, kept.count > 3 {
            didRemove = false
            for cornerIndex in kept.indices {
                let previous = kept[(cornerIndex + kept.count - 1) % kept.count]
                let next = kept[(cornerIndex + 1) % kept.count]
                if 180 - interiorAngleDegrees(at: kept[cornerIndex], previous: previous, next: next) < minimumTurnDegrees {
                    kept.remove(at: cornerIndex)
                    didRemove = true
                    break
                }
            }
        }
        return kept
    }

    private static func interiorAngleDegrees(at corner: CGPoint, previous: CGPoint, next: CGPoint) -> Double {
        let firstX = previous.x - corner.x, firstY = previous.y - corner.y
        let secondX = next.x - corner.x, secondY = next.y - corner.y
        let lengths = hypot(firstX, firstY) * hypot(secondX, secondY)
        guard lengths > 0 else { return 180 }
        let cosine = min(max((firstX * secondX + firstY * secondY) / lengths, -1), 1)
        return acos(cosine) * 180 / .pi
    }

    private static func signedArea(of corners: [CGPoint]) -> Double {
        corners.indices.reduce(0) { total, cornerIndex in
            let current = corners[cornerIndex], next = corners[(cornerIndex + 1) % corners.count]
            return total + (current.x * next.y - next.x * current.y)
        } / 2
    }

    private static func centroid(of points: [CGPoint]) -> CGPoint {
        CGPoint(x: points.map(\.x).reduce(0, +) / Double(max(points.count, 1)), y: points.map(\.y).reduce(0, +) / Double(max(points.count, 1)))
    }

    private static func boundingBox(of points: [CGPoint]) -> CGRect {
        let horizontal = points.map(\.x), vertical = points.map(\.y)
        guard let minimumX = horizontal.min(), let maximumX = horizontal.max(), let minimumY = vertical.min(), let maximumY = vertical.max() else { return .null }
        return CGRect(x: minimumX, y: minimumY, width: maximumX - minimumX, height: maximumY - minimumY)
    }

    private static func pathLength(of points: [CGPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { total, pair in total + distance(pair.0, pair.1) }
    }

    static func distance(_ first: CGPoint, _ second: CGPoint) -> Double {
        hypot(second.x - first.x, second.y - first.y)
    }

    static func distance(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> Double {
        let segmentX = end.x - start.x, segmentY = end.y - start.y
        let squaredLength = segmentX * segmentX + segmentY * segmentY
        guard squaredLength > 0 else { return distance(point, start) }
        let fraction = min(max(((point.x - start.x) * segmentX + (point.y - start.y) * segmentY) / squaredLength, 0), 1)
        return distance(point, CGPoint(x: start.x + fraction * segmentX, y: start.y + fraction * segmentY))
    }
}
