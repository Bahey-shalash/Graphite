import CoreGraphics
import XCTest
@testable import GraphiteCore

final class ShapeOutlineSamplingTests: XCTestCase {
    func testALongStraightSideIsFilledInSoPencilKitCannotBowIt() {
        let points = ShapeOutlineSampling.polyline([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)], closed: false)
        XCTAssertEqual(points.first, CGPoint(x: 0, y: 0))
        XCTAssertEqual(points.last, CGPoint(x: 10, y: 0))
        XCTAssertEqual(points.count, 6)
        XCTAssertTrue(points.allSatisfy { point in point.y == 0 })
    }

    func testARectangleIsClosedAndTurnedAboutItsCenter() throws {
        let upright = ShapeOutlineSampling.rectangle(center: CGPoint(x: 10, y: 20), size: CGSize(width: 8, height: 4), angleRadians: 0)
        XCTAssertEqual(upright.first, CGPoint(x: 6, y: 18))
        XCTAssertEqual(upright.last, upright.first)
        let turned = ShapeOutlineSampling.rectangle(center: .zero, size: CGSize(width: 8, height: 4), angleRadians: .pi / 2)
        let firstCorner = try XCTUnwrap(turned.first)
        // The top-left corner (−4, −2) turned a quarter clockwise, y downwards, lies at (2, −4).
        XCTAssertEqual(firstCorner.x, 2, accuracy: 1e-9)
        XCTAssertEqual(firstCorner.y, -4, accuracy: 1e-9)
    }

    func testAnEllipseStaysOnItsCurveWithinTheTolerance() {
        let points = ShapeOutlineSampling.ellipse(center: CGPoint(x: 5, y: 5), radii: CGSize(width: 20, height: 10), angleRadians: 0, tolerance: 0.1)
        XCTAssertEqual(points.first, points.last)
        for point in points {
            let normalized = pow((point.x - 5) / 20, 2) + pow((point.y - 5) / 10, 2)
            XCTAssertEqual(normalized, 1, accuracy: 1e-9)
        }
        for (start, end) in zip(points, points.dropFirst()) {
            let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            XCTAssertLessThan(1 - (pow((middle.x - 5) / 20, 2) + pow((middle.y - 5) / 10, 2)), 0.02)
        }
        XCTAssertEqual(ShapeOutlineSampling.ellipse(center: .zero, radii: .zero, angleRadians: 0, tolerance: 0.1), [.zero])
    }

    func testAnArcPassesThroughItsThreePointsTheWayTheyGo() throws {
        let first = CGPoint(x: 10, y: 0), second = CGPoint(x: 0, y: 10), third = CGPoint(x: -10, y: 0)
        let points = ShapeOutlineSampling.arc(through: first, second, third, tolerance: 0.1)
        XCTAssertEqual(points.first, first)
        let last = try XCTUnwrap(points.last)
        XCTAssertEqual(last.x, -10, accuracy: 1e-9)
        XCTAssertEqual(last.y, 0, accuracy: 1e-9)
        XCTAssertTrue(points.allSatisfy { point in abs(hypot(point.x, point.y) - 10) < 1e-9 })
        XCTAssertTrue(points.allSatisfy { point in point.y >= -1e-9 }, "the arc goes through (0, 10), not the other way round")
        XCTAssertEqual(ShapeOutlineSampling.arc(through: .zero, CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2), tolerance: 0.1).last, CGPoint(x: 2, y: 2))
    }
}
