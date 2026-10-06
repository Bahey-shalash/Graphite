import Foundation
import CoreGraphics

/// The shape a hand-drawn stroke was meant to be.
public enum RecognizedShape: Equatable, Sendable {
    case line(start: CGPoint, end: CGPoint)
    /// A straight line with an arrowhead at `end`.
    case arrow(start: CGPoint, end: CGPoint)
    /// Part of a circle, from `startAngle` through `sweepAngle`, in radians. A positive
    /// sweep turns toward larger angles.
    case arc(center: CGPoint, radius: Double, startAngle: Double, sweepAngle: Double)
    /// An arc with an arrowhead at its end.
    case curvedArrow(center: CGPoint, radius: Double, startAngle: Double, sweepAngle: Double)
    /// `rotation` is in radians; a circle has equal radii and no rotation.
    case ellipse(center: CGPoint, horizontalRadius: Double, verticalRadius: Double, rotation: Double)
    /// A closed outline through its corners, in drawing order: a triangle, a rectangle, or
    /// another polygon of up to six sides.
    case polygon(corners: [CGPoint])

    /// Points along the outline about `spacing` apart. Corners are repeated, so a stroke
    /// that smooths between its points keeps them sharp. Closed outlines end where they
    /// start; an arrow's outline is its shaft, then one barb, back to the tip, and the other.
    public func outlinePoints(spacing: Double) -> [CGPoint] {
        let step = max(spacing, 0.5)
        switch self {
        case .line(let start, let end):
            return Self.segmentPoints(from: start, to: end, step: step, includesEnd: true)
        case .arrow(let start, let end):
            let shaft = Self.segmentPoints(from: start, to: end, step: step, includesEnd: true)
            return shaft + Self.arrowheadPoints(tip: end, direction: atan2(end.y - start.y, end.x - start.x), shaftLength: hypot(end.x - start.x, end.y - start.y), step: step)
        case .arc(let center, let radius, let startAngle, let sweepAngle):
            return Self.arcPoints(center: center, radius: radius, startAngle: startAngle, sweepAngle: sweepAngle, step: step)
        case .curvedArrow(let center, let radius, let startAngle, let sweepAngle):
            let shaft = Self.arcPoints(center: center, radius: radius, startAngle: startAngle, sweepAngle: sweepAngle, step: step)
            guard let tip = shaft.last else { return [] }
            // The arc's direction of travel at its end is a quarter turn from the radius there.
            let endAngle = startAngle + sweepAngle
            let direction = endAngle + (sweepAngle >= 0 ? Double.pi / 2 : -Double.pi / 2)
            return shaft + Self.arrowheadPoints(tip: tip, direction: direction, shaftLength: abs(sweepAngle) * radius, step: step)
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
    private static let minimumArcPointCount = 8
    private static let cornerRepetitionCount = 3
    /// An arrowhead's barbs are this fraction of the shaft long, within the limits below,
    /// and this far from the shaft, in radians.
    private static let arrowheadLengthFraction = 0.22
    private static let arrowheadLengthLimits = 9.0...24.0
    private static let arrowheadSpread = 28.0 * Double.pi / 180

    private static func segmentPoints(from start: CGPoint, to end: CGPoint, step: Double, includesEnd: Bool) -> [CGPoint] {
        let length = hypot(end.x - start.x, end.y - start.y)
        let segmentCount = max(1, Int((length / step).rounded(.up)))
        let lastIndex = includesEnd ? segmentCount : segmentCount - 1
        return (0...max(lastIndex, 0)).map { pointIndex in
            let fraction = Double(pointIndex) / Double(segmentCount)
            return CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
        }
    }

    private static func arcPoints(center: CGPoint, radius: Double, startAngle: Double, sweepAngle: Double, step: Double) -> [CGPoint] {
        let pointCount = max(minimumArcPointCount, Int((abs(sweepAngle) * radius / step).rounded(.up)))
        return (0...pointCount).map { pointIndex in
            let angle = startAngle + sweepAngle * Double(pointIndex) / Double(pointCount)
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
    }

    /// From the tip along one barb, back to the tip, and along the other, as a hand draws it.
    private static func arrowheadPoints(tip: CGPoint, direction: Double, shaftLength: Double, step: Double) -> [CGPoint] {
        let barbLength = min(max(shaftLength * arrowheadLengthFraction, arrowheadLengthLimits.lowerBound), arrowheadLengthLimits.upperBound)
        let barbEnds = [direction + Double.pi - arrowheadSpread, direction + Double.pi + arrowheadSpread].map { barbAngle in
            CGPoint(x: tip.x + barbLength * cos(barbAngle), y: tip.y + barbLength * sin(barbAngle))
        }
        let sharpTip = Array(repeating: tip, count: cornerRepetitionCount)
        return sharpTip + segmentPoints(from: tip, to: barbEnds[0], step: step, includesEnd: true).dropFirst()
            + Array(repeating: barbEnds[0], count: cornerRepetitionCount - 1)
            + segmentPoints(from: barbEnds[0], to: tip, step: step, includesEnd: true).dropFirst()
            + sharpTip.dropFirst()
            + segmentPoints(from: tip, to: barbEnds[1], step: step, includesEnd: true).dropFirst()
    }

    // MARK: Moving and resizing

    /// Whether the outline ends where it starts.
    public var isClosed: Bool {
        switch self {
        case .ellipse, .polygon: true
        case .line, .arrow, .arc, .curvedArrow: false
        }
    }

    /// Where an open shape starts and ends; nil for a closed one.
    public var endpoints: (start: CGPoint, end: CGPoint)? {
        switch self {
        case .line(let start, let end), .arrow(let start, let end):
            return (start, end)
        case .arc(let center, let radius, let startAngle, let sweepAngle), .curvedArrow(let center, let radius, let startAngle, let sweepAngle):
            let endAngle = startAngle + sweepAngle
            return (CGPoint(x: center.x + radius * cos(startAngle), y: center.y + radius * sin(startAngle)),
                    CGPoint(x: center.x + radius * cos(endAngle), y: center.y + radius * sin(endAngle)))
        case .ellipse, .polygon:
            return nil
        }
    }

    /// The middle of a closed shape; nil for an open one.
    public var center: CGPoint? {
        switch self {
        case .ellipse(let center, _, _, _):
            return center
        case .polygon(let corners):
            guard !corners.isEmpty else { return nil }
            return CGPoint(x: corners.map(\.x).reduce(0, +) / Double(corners.count), y: corners.map(\.y).reduce(0, +) / Double(corners.count))
        case .line, .arrow, .arc, .curvedArrow:
            return nil
        }
    }

    /// The shape made `scale` times as large and turned by `rotation` radians about `anchor`,
    /// which stays where it is.
    public func transformed(scale: Double, rotation: Double, about anchor: CGPoint) -> RecognizedShape {
        func transformedPoint(_ point: CGPoint) -> CGPoint {
            let offsetX = (point.x - anchor.x) * scale, offsetY = (point.y - anchor.y) * scale
            return CGPoint(x: anchor.x + offsetX * cos(rotation) - offsetY * sin(rotation), y: anchor.y + offsetX * sin(rotation) + offsetY * cos(rotation))
        }
        switch self {
        case .line(let start, let end):
            return .line(start: transformedPoint(start), end: transformedPoint(end))
        case .arrow(let start, let end):
            return .arrow(start: transformedPoint(start), end: transformedPoint(end))
        case .arc(let center, let radius, let startAngle, let sweepAngle):
            return .arc(center: transformedPoint(center), radius: radius * scale, startAngle: startAngle + rotation, sweepAngle: sweepAngle)
        case .curvedArrow(let center, let radius, let startAngle, let sweepAngle):
            return .curvedArrow(center: transformedPoint(center), radius: radius * scale, startAngle: startAngle + rotation, sweepAngle: sweepAngle)
        case .ellipse(let center, let horizontalRadius, let verticalRadius, let ellipseRotation):
            return .ellipse(center: transformedPoint(center), horizontalRadius: horizontalRadius * scale, verticalRadius: verticalRadius * scale, rotation: ellipseRotation + rotation)
        case .polygon(let corners):
            return .polygon(corners: corners.map(transformedPoint))
        }
    }

    /// Below this distance, in points, a drag has no direction to follow and changes nothing.
    private static let minimumDragReach = 4.0
    /// A drag makes a closed shape at least this fraction of its size, so it cannot vanish.
    private static let minimumDragScale = 0.1

    /// The shape after the hand that drew it, still down where the stroke ended, moves on to
    /// `point`, as in Apple Notes. An open shape keeps its start and turns and stretches so
    /// that its end follows the hand. A closed shape keeps its middle and grows or shrinks by
    /// how far the hand moves from it.
    public func dragging(from heldPoint: CGPoint, to point: CGPoint) -> RecognizedShape {
        if let endpoints {
            let currentReach = hypot(endpoints.end.x - endpoints.start.x, endpoints.end.y - endpoints.start.y)
            let newReach = hypot(point.x - endpoints.start.x, point.y - endpoints.start.y)
            guard currentReach >= Self.minimumDragReach, newReach >= Self.minimumDragReach else { return self }
            let rotation = atan2(point.y - endpoints.start.y, point.x - endpoints.start.x)
                - atan2(endpoints.end.y - endpoints.start.y, endpoints.end.x - endpoints.start.x)
            return transformed(scale: newReach / currentReach, rotation: rotation, about: endpoints.start)
        }
        guard let center else { return self }
        let heldReach = hypot(heldPoint.x - center.x, heldPoint.y - center.y)
        guard heldReach >= Self.minimumDragReach else { return self }
        let scale = max(hypot(point.x - center.x, point.y - center.y) / heldReach, Self.minimumDragScale)
        return transformed(scale: scale, rotation: 0, about: center)
    }
}

/// Recognizes lines, arcs, arrows, circles and ellipses, triangles, rectangles, and simple
/// polygons in a hand-drawn stroke, for Graphite's shape tool. A stroke that is none of
/// them, such as handwriting, a wave or a scribble, is not recognized and stays as drawn.
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
    /// An arc spans at least this many points between its ends; shorter curves are letters
    /// and brackets.
    static let minimumArcChord = 32.0
    /// An arc's points stay within this fraction of its chord from the fitted circle.
    static let maximumArcDeviationFraction = 0.05
    /// An arc turns through at least and at most this many degrees. A flatter curve is a
    /// line drawn unsteadily; a longer one is a circle left open.
    static let arcSweepDegrees = 24.0...300.0
    /// An arrowhead's barbs are this fraction of the shaft long.
    static let arrowheadBarbFraction = 0.05...0.6

    public static func recognize(_ strokePoints: [CGPoint]) -> RecognizedShape? {
        let points = removingRepeatedPoints(strokePoints)
        guard points.count >= 5, let first = points.first, let last = points.last else { return nil }
        let bounds = boundingBox(of: points)
        let size = hypot(bounds.width, bounds.height)
        guard size >= minimumShapeSize else { return nil }
        let length = pathLength(of: points)
        let closingGap = distance(first, last)
        if closingGap > max(maximumClosingGapFraction * length, 6) {
            return recognizeArrow(points, size: size) ?? recognizeLine(points, length: length) ?? recognizeArc(points)
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

    /// Part of a circle: the points lie on one circle and go around it in one direction.
    private static func recognizeArc(_ points: [CGPoint]) -> RecognizedShape? {
        guard let start = points.first, let end = points.last else { return nil }
        let chord = distance(start, end)
        guard chord >= minimumArcChord, let circle = circle(fitting: points) else { return nil }
        let deviation = points.map { point in abs(distance(point, circle.center) - circle.radius) }.max() ?? 0
        guard deviation <= max(maximumArcDeviationFraction * chord, 3) else { return nil }
        // The signed turn around the center, and how much of the movement went against it.
        var sweepAngle = 0.0, totalTurning = 0.0
        for (previous, current) in zip(points, points.dropFirst()) {
            var change = atan2(current.y - circle.center.y, current.x - circle.center.x) - atan2(previous.y - circle.center.y, previous.x - circle.center.x)
            if change > .pi { change -= 2 * .pi }
            if change < -.pi { change += 2 * .pi }
            sweepAngle += change
            totalTurning += abs(change)
        }
        let sweepDegrees = abs(sweepAngle) * 180 / .pi
        guard arcSweepDegrees.contains(sweepDegrees), totalTurning <= 1.15 * abs(sweepAngle) else { return nil }
        return .arc(center: circle.center, radius: circle.radius, startAngle: atan2(start.y - circle.center.y, start.x - circle.center.x), sweepAngle: sweepAngle)
    }

    /// The circle closest to the points in the least-squares sense (Kåsa's fit); nil when
    /// the points lie on a line.
    private static func circle(fitting points: [CGPoint]) -> (center: CGPoint, radius: Double)? {
        let pointCount = Double(points.count)
        let meanX = points.map(\.x).reduce(0, +) / pointCount, meanY = points.map(\.y).reduce(0, +) / pointCount
        var sumXX = 0.0, sumYY = 0.0, sumXY = 0.0, sumXZ = 0.0, sumYZ = 0.0, sumZ = 0.0
        for point in points {
            let offsetX = point.x - meanX, offsetY = point.y - meanY
            let squaredDistance = offsetX * offsetX + offsetY * offsetY
            sumXX += offsetX * offsetX; sumYY += offsetY * offsetY; sumXY += offsetX * offsetY
            sumXZ += offsetX * squaredDistance; sumYZ += offsetY * squaredDistance; sumZ += squaredDistance
        }
        let determinant = sumXX * sumYY - sumXY * sumXY
        guard abs(determinant) > 1e-9 * max(sumXX * sumYY, 1) else { return nil }
        let centerOffsetX = (sumXZ * sumYY - sumYZ * sumXY) / (2 * determinant)
        let centerOffsetY = (sumYZ * sumXX - sumXZ * sumXY) / (2 * determinant)
        let radius = (centerOffsetX * centerOffsetX + centerOffsetY * centerOffsetY + sumZ / pointCount).squareRoot()
        guard radius.isFinite, radius > 1 else { return nil }
        return (CGPoint(x: meanX + centerOffsetX, y: meanY + centerOffsetY), radius)
    }

    /// A line or an arc that ends in an arrowhead drawn without lifting: from the tip back
    /// along one barb, to the tip again, and along the other.
    private static func recognizeArrow(_ points: [CGPoint], size: Double) -> RecognizedShape? {
        let cornerIndices = simplifiedIndices(points, tolerance: max(0.03 * size, 2.5))
        // The start of the shaft, the tip, a barb's end, the tip again, the other barb's end.
        guard cornerIndices.count >= 5 else { return nil }
        let tipIndex = cornerIndices[cornerIndices.count - 4]
        let tip = points[tipIndex], firstBarbEnd = points[cornerIndices[cornerIndices.count - 3]]
        let returnedTip = points[cornerIndices[cornerIndices.count - 2]], secondBarbEnd = points[cornerIndices[cornerIndices.count - 1]]
        let shaftPoints = Array(points[...tipIndex])
        let shaftLength = pathLength(of: shaftPoints)
        let firstBarbLength = distance(tip, firstBarbEnd), secondBarbLength = distance(returnedTip, secondBarbEnd)
        let barbLengths = (arrowheadBarbFraction.lowerBound * shaftLength)...(arrowheadBarbFraction.upperBound * shaftLength)
        guard shaftPoints.count >= 5, barbLengths.contains(firstBarbLength), barbLengths.contains(secondBarbLength),
              distance(tip, returnedTip) <= 0.5 * max(firstBarbLength, secondBarbLength) else { return nil }
        // The direction the shaft arrives in, taken a barb's length back so a hook at the
        // very end does not decide it.
        let approachPoint = shaftPoints.last { point in distance(point, tip) >= min(firstBarbLength, secondBarbLength) } ?? shaftPoints[0]
        let approachX = tip.x - approachPoint.x, approachY = tip.y - approachPoint.y
        func side(of barbEnd: CGPoint) -> Double { approachX * (barbEnd.y - tip.y) - approachY * (barbEnd.x - tip.x) }
        func pointsBackward(_ barbEnd: CGPoint) -> Bool { approachX * (barbEnd.x - tip.x) + approachY * (barbEnd.y - tip.y) < 0 }
        guard side(of: firstBarbEnd) * side(of: secondBarbEnd) < 0, pointsBackward(firstBarbEnd), pointsBackward(secondBarbEnd) else { return nil }
        switch recognizeLine(shaftPoints, length: shaftLength) ?? recognizeArc(shaftPoints) {
        case .line(let start, let end): return .arrow(start: start, end: end)
        case .arc(let center, let radius, let startAngle, let sweepAngle):
            return .curvedArrow(center: center, radius: radius, startAngle: startAngle, sweepAngle: sweepAngle)
        default: return nil
        }
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

    static func simplify(_ points: [CGPoint], tolerance: Double) -> [CGPoint] {
        simplifiedIndices(points, tolerance: tolerance).map { pointIndex in points[pointIndex] }
    }

    /// Ramer–Douglas–Peucker simplification, iterative so a long stroke cannot exhaust the
    /// stack: the indices of the points that are kept.
    static func simplifiedIndices(_ points: [CGPoint], tolerance: Double) -> [Int] {
        guard points.count > 2 else { return Array(points.indices) }
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
        return points.indices.filter { pointIndex in isKept[pointIndex] }
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
