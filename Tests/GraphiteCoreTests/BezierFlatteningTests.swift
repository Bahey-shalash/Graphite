import CoreGraphics
import Foundation
import XCTest
@testable import GraphiteCore

/// Splitting Bézier segments and arcs into straight pieces within a tolerance.
final class BezierFlatteningTests: XCTestCase {
    private static let tolerance = 0.1
    private static let roundingAllowance = 1e-9
    private static let curvedQuadratic = (start: CGPoint(x: 0, y: 0), control: CGPoint(x: 50, y: 100), end: CGPoint(x: 100, y: 0))
    private static let curvedCubic = (start: CGPoint(x: 0, y: 0), control1: CGPoint(x: 0, y: 100), control2: CGPoint(x: 100, y: 100),
                                      end: CGPoint(x: 100, y: 0))

    // MARK: Quadratic segments

    func testAStraightQuadraticIsOnePiece() {
        let parameters = BezierFlattening.quadraticParameters(start: CGPoint(x: 0, y: 0), control: CGPoint(x: 5, y: 5),
                                                              end: CGPoint(x: 10, y: 10), tolerance: Self.tolerance)
        XCTAssertEqual(parameters, [1])
    }

    func testACurvedQuadraticIsSplitSoEveryChordStaysWithinTheTolerance() {
        let curve = Self.curvedQuadratic
        let parameters = BezierFlattening.quadraticParameters(start: curve.start, control: curve.control, end: curve.end,
                                                              tolerance: Self.tolerance)
        XCTAssertGreaterThan(parameters.count, 1)
        var previousParameter = 0.0
        for parameter in parameters {
            let chordStart = BezierFlattening.quadraticPoint(start: curve.start, control: curve.control, end: curve.end, at: previousParameter)
            let chordEnd = BezierFlattening.quadraticPoint(start: curve.start, control: curve.control, end: curve.end, at: parameter)
            let chordMidpoint = CGPoint(x: (chordStart.x + chordEnd.x) / 2, y: (chordStart.y + chordEnd.y) / 2)
            let curveMidpoint = BezierFlattening.quadraticPoint(start: curve.start, control: curve.control, end: curve.end,
                                                                at: (previousParameter + parameter) / 2)
            XCTAssertLessThanOrEqual(hypot(chordMidpoint.x - curveMidpoint.x, chordMidpoint.y - curveMidpoint.y),
                                     Self.tolerance + Self.roundingAllowance)
            previousParameter = parameter
        }
    }

    func testQuadraticParametersIncreaseExcludeZeroAndEndAtOne() {
        let curve = Self.curvedQuadratic
        let parameters = BezierFlattening.quadraticParameters(start: curve.start, control: curve.control, end: curve.end,
                                                              tolerance: Self.tolerance)
        assertIncreasingFromAboveZeroToOne(parameters)
    }

    func testAnEnormousQuadraticIsCappedAtTheMaximumPieceCount() {
        let parameters = BezierFlattening.quadraticParameters(start: CGPoint(x: 0, y: 0), control: CGPoint(x: 1e9, y: 1e9),
                                                              end: CGPoint(x: 2e9, y: 0), tolerance: Self.tolerance)
        XCTAssertEqual(parameters.count, BezierFlattening.maximumPiecesPerSegment)
        assertIncreasingFromAboveZeroToOne(parameters)
    }

    func testAQuadraticWithNonFiniteControlPointsStaysWithinTheMaximumPieceCount() {
        let parameters = BezierFlattening.quadraticParameters(start: CGPoint(x: 0, y: 0), control: CGPoint(x: Double.infinity, y: Double.nan),
                                                              end: CGPoint(x: 10, y: 0), tolerance: Self.tolerance)
        XCTAssertFalse(parameters.isEmpty)
        XCTAssertLessThanOrEqual(parameters.count, BezierFlattening.maximumPiecesPerSegment)
        XCTAssertEqual(parameters.last, 1)
    }

    // MARK: Cubic segments

    func testAStraightCubicIsOnePiece() {
        let parameters = BezierFlattening.cubicParameters(start: CGPoint(x: 0, y: 0), control1: CGPoint(x: 10, y: 0),
                                                          control2: CGPoint(x: 20, y: 0), end: CGPoint(x: 30, y: 0), tolerance: Self.tolerance)
        XCTAssertEqual(parameters, [1])
    }

    func testACurvedCubicIsSplitSoEveryChordStaysWithinTheTolerance() {
        let curve = Self.curvedCubic
        let parameters = BezierFlattening.cubicParameters(start: curve.start, control1: curve.control1, control2: curve.control2, end: curve.end,
                                                          tolerance: Self.tolerance)
        XCTAssertGreaterThan(parameters.count, 1)
        var previousParameter = 0.0
        for parameter in parameters {
            let chordStart = cubicPoint(curve, at: previousParameter)
            let chordEnd = cubicPoint(curve, at: parameter)
            let chordMidpoint = CGPoint(x: (chordStart.x + chordEnd.x) / 2, y: (chordStart.y + chordEnd.y) / 2)
            let curveMidpoint = cubicPoint(curve, at: (previousParameter + parameter) / 2)
            XCTAssertLessThanOrEqual(hypot(chordMidpoint.x - curveMidpoint.x, chordMidpoint.y - curveMidpoint.y),
                                     Self.tolerance + Self.roundingAllowance)
            previousParameter = parameter
        }
    }

    func testCubicParametersIncreaseExcludeZeroAndEndAtOne() {
        let curve = Self.curvedCubic
        let parameters = BezierFlattening.cubicParameters(start: curve.start, control1: curve.control1, control2: curve.control2, end: curve.end,
                                                          tolerance: Self.tolerance)
        assertIncreasingFromAboveZeroToOne(parameters)
    }

    func testAnEnormousCubicIsCappedAtTheMaximumPieceCount() {
        let parameters = BezierFlattening.cubicParameters(start: CGPoint(x: 0, y: 0), control1: CGPoint(x: 0, y: 1e9),
                                                          control2: CGPoint(x: 1e9, y: 1e9), end: CGPoint(x: 1e9, y: 0), tolerance: Self.tolerance)
        XCTAssertEqual(parameters.count, BezierFlattening.maximumPiecesPerSegment)
        assertIncreasingFromAboveZeroToOne(parameters)
    }

    func testACubicWithNonFiniteControlPointsStaysWithinTheMaximumPieceCount() {
        let parameters = BezierFlattening.cubicParameters(start: CGPoint(x: 0, y: 0), control1: CGPoint(x: Double.nan, y: 0),
                                                          control2: CGPoint(x: Double.infinity, y: 0), end: CGPoint(x: 10, y: 0),
                                                          tolerance: Self.tolerance)
        XCTAssertFalse(parameters.isEmpty)
        XCTAssertLessThanOrEqual(parameters.count, BezierFlattening.maximumPiecesPerSegment)
        XCTAssertEqual(parameters.last, 1)
    }

    // MARK: Arcs

    func testAHalfTurnArcStaysOnTheCircleAndEndsAtTheEndAngle() throws {
        let center = CGPoint(x: 5, y: 7)
        let points = BezierFlattening.arcPoints(center: center, radius: 10, startAngle: 0, endAngle: Double.pi, tolerance: Self.tolerance)
        XCTAssertGreaterThan(points.count, 2)
        for point in points {
            XCTAssertEqual(hypot(point.x - center.x, point.y - center.y), 10, accuracy: Self.roundingAllowance)
            XCTAssertGreaterThanOrEqual(point.y, center.y - Self.roundingAllowance)
        }
        let lastPoint = try XCTUnwrap(points.last)
        XCTAssertEqual(lastPoint.x, -5, accuracy: Self.roundingAllowance)
        XCTAssertEqual(lastPoint.y, 7, accuracy: Self.roundingAllowance)
    }

    func testAnArcExcludesItsStartPoint() throws {
        let points = BezierFlattening.arcPoints(center: .zero, radius: 10, startAngle: 0, endAngle: Double.pi, tolerance: Self.tolerance)
        let firstPoint = try XCTUnwrap(points.first)
        XCTAssertNotEqual(firstPoint, CGPoint(x: 10, y: 0))
    }

    func testAnArcKeepsEveryChordWithinTheTolerance() {
        let points = BezierFlattening.arcPoints(center: .zero, radius: 10, startAngle: 0, endAngle: Double.pi, tolerance: Self.tolerance)
        var previousPoint = CGPoint(x: 10, y: 0)
        for point in points {
            let chordMidpointDistance = hypot((previousPoint.x + point.x) / 2, (previousPoint.y + point.y) / 2)
            XCTAssertLessThanOrEqual(10 - chordMidpointDistance, Self.tolerance + Self.roundingAllowance)
            previousPoint = point
        }
    }

    func testANegativeSweepTurnsTheOtherWay() throws {
        let points = BezierFlattening.arcPoints(center: .zero, radius: 10, startAngle: 0, endAngle: -Double.pi / 2, tolerance: Self.tolerance)
        for point in points {
            XCTAssertLessThanOrEqual(point.y, Self.roundingAllowance)
        }
        let lastPoint = try XCTUnwrap(points.last)
        XCTAssertEqual(lastPoint.x, 0, accuracy: Self.roundingAllowance)
        XCTAssertEqual(lastPoint.y, -10, accuracy: Self.roundingAllowance)
    }

    func testAnArcOfZeroRadiusHasNoPoints() {
        XCTAssertEqual(BezierFlattening.arcPoints(center: .zero, radius: 0, startAngle: 0, endAngle: Double.pi, tolerance: Self.tolerance), [])
    }

    func testAnArcOfNonFiniteRadiusHasNoPoints() {
        XCTAssertEqual(BezierFlattening.arcPoints(center: .zero, radius: .infinity, startAngle: 0, endAngle: Double.pi,
                                                  tolerance: Self.tolerance), [])
        XCTAssertEqual(BezierFlattening.arcPoints(center: .zero, radius: .nan, startAngle: 0, endAngle: Double.pi, tolerance: Self.tolerance), [])
    }

    func testAnArcWithANonFiniteSweepHasNoPoints() {
        XCTAssertEqual(BezierFlattening.arcPoints(center: .zero, radius: 10, startAngle: 0, endAngle: .infinity, tolerance: Self.tolerance), [])
    }

    func testAnArcOfEnormousSweepIsCappedAtTheMaximumPieceCount() {
        let points = BezierFlattening.arcPoints(center: .zero, radius: 10, startAngle: 0, endAngle: 1e9, tolerance: Self.tolerance)
        XCTAssertEqual(points.count, BezierFlattening.maximumPiecesPerSegment)
    }

    // MARK: Helpers

    private func cubicPoint(_ curve: (start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint), at parameter: Double) -> CGPoint {
        BezierFlattening.cubicPoint(start: curve.start, control1: curve.control1, control2: curve.control2, end: curve.end, at: parameter)
    }

    private func assertIncreasingFromAboveZeroToOne(_ parameters: [Double]) {
        XCTAssertEqual(parameters.last, 1)
        XCTAssertGreaterThan(parameters.first ?? 0, 0)
        for pair in zip(parameters, parameters.dropFirst()) {
            XCTAssertLessThan(pair.0, pair.1)
        }
    }
}
