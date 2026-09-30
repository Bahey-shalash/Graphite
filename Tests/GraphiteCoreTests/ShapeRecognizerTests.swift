import XCTest
import CoreGraphics
@testable import GraphiteCore

/// Hand-drawn strokes are simulated with a small, deterministic wobble and imperfect ends.
final class ShapeRecognizerTests: XCTestCase {
    private func wobble(_ pointIndex: Int, amplitude: Double) -> (Double, Double) {
        (amplitude * sin(Double(pointIndex) * 0.9), amplitude * cos(Double(pointIndex) * 1.3))
    }

    private func strokeAlong(_ corners: [CGPoint], pointsPerEdge: Int = 24, wobbleAmplitude: Double = 1.5, closes: Bool = true) -> [CGPoint] {
        var points: [CGPoint] = []
        let edgeCount = closes ? corners.count : corners.count - 1
        for edgeIndex in 0..<edgeCount {
            let start = corners[edgeIndex], end = corners[(edgeIndex + 1) % corners.count]
            for step in 0..<pointsPerEdge {
                let fraction = Double(step) / Double(pointsPerEdge)
                let (wobbleX, wobbleY) = wobble(points.count, amplitude: wobbleAmplitude)
                points.append(CGPoint(x: start.x + (end.x - start.x) * fraction + wobbleX, y: start.y + (end.y - start.y) * fraction + wobbleY))
            }
        }
        // A hand rarely ends exactly where it started.
        points.append(closes ? CGPoint(x: corners[0].x + 4, y: corners[0].y + 3) : corners[corners.count - 1])
        return points
    }

    private func ellipseStroke(center: CGPoint, horizontalRadius: Double, verticalRadius: Double, rotationDegrees: Double,
                               startDegrees: Double = 20, turnDegrees: Double = 350, wobbleAmplitude: Double = 1.5) -> [CGPoint] {
        let rotation = rotationDegrees * .pi / 180
        return (0...80).map { pointIndex in
            let angle = (startDegrees + turnDegrees * Double(pointIndex) / 80) * .pi / 180
            let (wobbleX, wobbleY) = wobble(pointIndex, amplitude: wobbleAmplitude)
            let localX = horizontalRadius * cos(angle) + wobbleX, localY = verticalRadius * sin(angle) + wobbleY
            return CGPoint(x: center.x + localX * cos(rotation) - localY * sin(rotation), y: center.y + localX * sin(rotation) + localY * cos(rotation))
        }
    }

    private func assertPoint(_ point: CGPoint, near expected: CGPoint, within tolerance: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(hypot(point.x - expected.x, point.y - expected.y), tolerance, "\(point) is not near \(expected)", file: file, line: line)
    }

    func testStraightStrokeBecomesALineSnappedToTheAxis() throws {
        let points = strokeAlong([CGPoint(x: 100, y: 200), CGPoint(x: 400, y: 212)], wobbleAmplitude: 1.2, closes: false)
        guard case .line(let start, let end) = try XCTUnwrap(ShapeRecognizer.recognize(points)) else { return XCTFail("Not a line") }
        assertPoint(start, near: CGPoint(x: 100, y: 200), within: 3)
        XCTAssertEqual(end.y, start.y, "A nearly level line is made level.")
        XCTAssertEqual(end.x, 400, accuracy: 3)
    }

    func testDiagonalLineKeepsItsAngle() throws {
        let points = strokeAlong([CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 150)], closes: false)
        guard case .line(let start, let end) = try XCTUnwrap(ShapeRecognizer.recognize(points)) else { return XCTFail("Not a line") }
        assertPoint(start, near: .zero, within: 3)
        assertPoint(end, near: CGPoint(x: 200, y: 150), within: 3)
    }

    func testRoundStrokeBecomesACircle() throws {
        let points = ellipseStroke(center: CGPoint(x: 300, y: 300), horizontalRadius: 80, verticalRadius: 76, rotationDegrees: 0)
        guard case .ellipse(let center, let horizontalRadius, let verticalRadius, let rotation) = try XCTUnwrap(ShapeRecognizer.recognize(points)) else {
            return XCTFail("Not an ellipse")
        }
        assertPoint(center, near: CGPoint(x: 300, y: 300), within: 4)
        XCTAssertEqual(horizontalRadius, verticalRadius, "Nearly equal radii make a circle.")
        XCTAssertEqual(horizontalRadius, 78, accuracy: 4)
        XCTAssertEqual(rotation, 0)
    }

    func testTiltedOvalKeepsItsRotation() throws {
        let points = ellipseStroke(center: CGPoint(x: 200, y: 200), horizontalRadius: 120, verticalRadius: 55, rotationDegrees: 30)
        guard case .ellipse(_, let horizontalRadius, let verticalRadius, let rotation) = try XCTUnwrap(ShapeRecognizer.recognize(points)) else {
            return XCTFail("Not an ellipse")
        }
        XCTAssertEqual(max(horizontalRadius, verticalRadius), 120, accuracy: 6)
        XCTAssertEqual(min(horizontalRadius, verticalRadius), 55, accuracy: 6)
        let rotationDegrees = (rotation * 180 / .pi).truncatingRemainder(dividingBy: 180)
        XCTAssertEqual((rotationDegrees + 180).truncatingRemainder(dividingBy: 180), 30, accuracy: 5)
    }

    func testNearlyLevelOvalIsStraightened() throws {
        let points = ellipseStroke(center: CGPoint(x: 200, y: 200), horizontalRadius: 110, verticalRadius: 50, rotationDegrees: 6)
        guard case .ellipse(_, let horizontalRadius, let verticalRadius, let rotation) = try XCTUnwrap(ShapeRecognizer.recognize(points)) else {
            return XCTFail("Not an ellipse")
        }
        XCTAssertEqual(rotation, 0)
        XCTAssertGreaterThan(horizontalRadius, verticalRadius, "The long axis stays horizontal.")
    }

    func testBoxBecomesARectangle() throws {
        let corners = [CGPoint(x: 100, y: 100), CGPoint(x: 340, y: 104), CGPoint(x: 336, y: 260), CGPoint(x: 98, y: 256)]
        guard case .polygon(let fitted) = try XCTUnwrap(ShapeRecognizer.recognize(strokeAlong(corners))) else { return XCTFail("Not a polygon") }
        XCTAssertEqual(fitted.count, 4)
        // Level and upright: the edges share coordinates.
        XCTAssertEqual(fitted[0].y, fitted[1].y, accuracy: 0.001)
        XCTAssertEqual(fitted[1].x, fitted[2].x, accuracy: 0.001)
        assertPoint(fitted[0], near: CGPoint(x: 99, y: 102), within: 6)
        assertPoint(fitted[2], near: CGPoint(x: 338, y: 258), within: 6)
    }

    func testTiltedBoxStaysTiltedAndSquare() throws {
        let rotation = 25.0 * .pi / 180
        let corners = [(-100.0, -50.0), (100, -50), (100, 50), (-100, 50)].map { along, across in
            CGPoint(x: 300 + along * cos(rotation) - across * sin(rotation), y: 300 + along * sin(rotation) + across * cos(rotation))
        }
        guard case .polygon(let fitted) = try XCTUnwrap(ShapeRecognizer.recognize(strokeAlong(corners))) else { return XCTFail("Not a polygon") }
        XCTAssertEqual(fitted.count, 4)
        for (fittedCorner, corner) in zip(fitted, corners) { assertPoint(fittedCorner, near: corner, within: 6) }
        let firstEdge = CGPoint(x: fitted[1].x - fitted[0].x, y: fitted[1].y - fitted[0].y)
        let secondEdge = CGPoint(x: fitted[2].x - fitted[1].x, y: fitted[2].y - fitted[1].y)
        XCTAssertEqual(firstEdge.x * secondEdge.x + firstEdge.y * secondEdge.y, 0, accuracy: 0.01, "Corners are right angles.")
    }

    func testThreeSidedStrokeBecomesATriangle() throws {
        let corners = [CGPoint(x: 200, y: 80), CGPoint(x: 320, y: 280), CGPoint(x: 80, y: 280)]
        guard case .polygon(let fitted) = try XCTUnwrap(ShapeRecognizer.recognize(strokeAlong(corners, pointsPerEdge: 30))) else { return XCTFail("Not a polygon") }
        XCTAssertEqual(fitted.count, 3)
        for corner in corners {
            XCTAssertTrue(fitted.contains { fittedCorner in hypot(fittedCorner.x - corner.x, fittedCorner.y - corner.y) < 10 }, "\(corner) missing")
        }
    }

    func testHandwritingAndOpenCurvesStayAsDrawn() {
        // A wave, like cursive.
        let wave = (0...80).map { pointIndex in CGPoint(x: Double(pointIndex) * 4, y: 100 + 25 * sin(Double(pointIndex) * 0.35)) }
        XCTAssertNil(ShapeRecognizer.recognize(wave))
        // A wavy underline is close to its straight line everywhere, but longer than one.
        let wavyUnderline = (0...100).map { pointIndex in CGPoint(x: Double(pointIndex) * 2, y: 100 + 5 * sin(Double(pointIndex) * 2 * 2 * .pi / 50)) }
        XCTAssertNil(ShapeRecognizer.recognize(wavyUnderline))
        // Half a circle does not close.
        let arc = ellipseStroke(center: CGPoint(x: 200, y: 200), horizontalRadius: 80, verticalRadius: 80, rotationDegrees: 0, startDegrees: 0, turnDegrees: 180)
        XCTAssertNil(ShapeRecognizer.recognize(arc))
        // A dot or a tiny tick.
        XCTAssertNil(ShapeRecognizer.recognize((0...10).map { pointIndex in CGPoint(x: 10 + Double(pointIndex) * 0.8, y: 10) }))
        // A closed scribble loops over itself.
        let scribble = (0...120).map { pointIndex -> CGPoint in
            let angle = Double(pointIndex) * 0.26
            return CGPoint(x: 200 + 60 * cos(angle) + 40 * cos(3.7 * angle), y: 200 + 60 * sin(angle) + 40 * sin(2.3 * angle))
        }
        XCTAssertNil(ShapeRecognizer.recognize(scribble))
    }

    func testOutlinePointsFollowTheShapeAndKeepCornersSharp() {
        let line = RecognizedShape.line(start: .zero, end: CGPoint(x: 100, y: 0)).outlinePoints(spacing: 10)
        XCTAssertEqual(line.first, .zero)
        XCTAssertEqual(line.last, CGPoint(x: 100, y: 0))
        XCTAssertEqual(line.count, 11)

        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 0, y: 50)]
        let outline = RecognizedShape.polygon(corners: square).outlinePoints(spacing: 10)
        XCTAssertEqual(outline.first, square[0])
        XCTAssertEqual(outline.last, square[0], "Closed outlines end where they start.")
        XCTAssertEqual(outline.filter { point in point == square[2] }.count, 3, "Each corner is repeated so it stays sharp.")

        let circle = RecognizedShape.ellipse(center: CGPoint(x: 50, y: 50), horizontalRadius: 20, verticalRadius: 20, rotation: 0).outlinePoints(spacing: 4)
        XCTAssertGreaterThanOrEqual(circle.count, 32)
        for point in circle { XCTAssertEqual(hypot(point.x - 50, point.y - 50), 20, accuracy: 0.001) }
        XCTAssertEqual(circle.first!.x, circle.last!.x, accuracy: 0.001)
    }

    func testSimplificationIsIterativeOnLongStrokes() {
        let longStroke = (0..<50_000).map { pointIndex in CGPoint(x: Double(pointIndex) * 0.7, y: 20 * sin(Double(pointIndex) * 0.01)) }
        XCTAssertGreaterThan(ShapeRecognizer.simplify(longStroke, tolerance: 1).count, 2)
    }
}
