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
        // A curve that bends one way and then the other is on no circle.
        let bend = (0...80).map { pointIndex in CGPoint(x: Double(pointIndex) * 3, y: 100 + 30 * sin(Double(pointIndex) * 2 * .pi / 80)) }
        XCTAssertNil(ShapeRecognizer.recognize(bend))
        // A bracket or the bowl of a letter is a curve too small to be meant as an arc.
        let bracket = ellipseStroke(center: CGPoint(x: 200, y: 200), horizontalRadius: 12, verticalRadius: 12, rotationDegrees: 0, startDegrees: 100, turnDegrees: 160, wobbleAmplitude: 0.3)
        XCTAssertNil(ShapeRecognizer.recognize(bracket))
        // A spiral goes around its middle without staying on one circle.
        let spiral = (0...120).map { pointIndex -> CGPoint in
            let angle = Double(pointIndex) * 0.1
            return CGPoint(x: 200 + (20 + 6 * angle) * cos(angle), y: 200 + (20 + 6 * angle) * sin(angle))
        }
        XCTAssertNil(ShapeRecognizer.recognize(spiral))
        // A dot or a tiny tick.
        XCTAssertNil(ShapeRecognizer.recognize((0...10).map { pointIndex in CGPoint(x: 10 + Double(pointIndex) * 0.8, y: 10) }))
        // A closed scribble loops over itself.
        let scribble = (0...120).map { pointIndex -> CGPoint in
            let angle = Double(pointIndex) * 0.26
            return CGPoint(x: 200 + 60 * cos(angle) + 40 * cos(3.7 * angle), y: 200 + 60 * sin(angle) + 40 * sin(2.3 * angle))
        }
        XCTAssertNil(ShapeRecognizer.recognize(scribble))
    }

    // MARK: Arcs and arrows

    func testHalfACircleBecomesAnArcThatKeepsItsEndsAndDirection() throws {
        for turnDegrees in [180.0, -120.0, 60.0] {
            let points = ellipseStroke(center: CGPoint(x: 200, y: 200), horizontalRadius: 80, verticalRadius: 80, rotationDegrees: 0,
                                       startDegrees: 10, turnDegrees: turnDegrees, wobbleAmplitude: 1)
            let shape = try XCTUnwrap(ShapeRecognizer.recognize(points), "\(turnDegrees)")
            guard case .arc(let center, let radius, _, let sweepAngle) = shape else { return XCTFail("Not an arc: \(shape)") }
            assertPoint(center, near: CGPoint(x: 200, y: 200), within: 6)
            XCTAssertEqual(radius, 80, accuracy: 5)
            XCTAssertEqual(sweepAngle * 180 / .pi, turnDegrees, accuracy: 6, "The arc turns the way it was drawn.")
            let endpoints = try XCTUnwrap(shape.endpoints)
            assertPoint(endpoints.start, near: points[0], within: 5)
            assertPoint(endpoints.end, near: points[points.count - 1], within: 5)
            for point in shape.outlinePoints(spacing: 5) { XCTAssertEqual(hypot(point.x - center.x, point.y - center.y), radius, accuracy: 0.001) }
        }
        // A barely bent stroke is still a line.
        let shallow = ellipseStroke(center: CGPoint(x: 200, y: 2_000), horizontalRadius: 1_900, verticalRadius: 1_900, rotationDegrees: 0,
                                    startDegrees: 268, turnDegrees: 4, wobbleAmplitude: 0.5)
        guard case .line = try XCTUnwrap(ShapeRecognizer.recognize(shallow)) else { return XCTFail("Not a line") }
    }

    /// A shaft, then the head without lifting: back along one barb, to the tip, along the other.
    private func arrowStroke(shaft: [CGPoint], barbLength: Double = 22, spreadDegrees: Double = 30) -> [CGPoint] {
        let tip = shaft[shaft.count - 1], beforeTip = shaft[shaft.count - 4]
        let direction = atan2(tip.y - beforeTip.y, tip.x - beforeTip.x)
        let barbEnds = [Double.pi - spreadDegrees * .pi / 180, Double.pi + spreadDegrees * .pi / 180].map { offset in
            CGPoint(x: tip.x + barbLength * cos(direction + offset), y: tip.y + barbLength * sin(direction + offset))
        }
        func steps(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
            (1...8).map { step in CGPoint(x: start.x + (end.x - start.x) * Double(step) / 8, y: start.y + (end.y - start.y) * Double(step) / 8) }
        }
        return shaft + steps(from: tip, to: barbEnds[0]) + steps(from: barbEnds[0], to: CGPoint(x: tip.x + 1.5, y: tip.y - 1)) + steps(from: tip, to: barbEnds[1])
    }

    func testLineEndingInAHeadBecomesAnArrow() throws {
        let shaft = strokeAlong([CGPoint(x: 100, y: 200), CGPoint(x: 320, y: 207)], wobbleAmplitude: 1, closes: false)
        let shape = try XCTUnwrap(ShapeRecognizer.recognize(arrowStroke(shaft: shaft)))
        guard case .arrow(let start, let end) = shape else { return XCTFail("Not an arrow: \(shape)") }
        assertPoint(start, near: CGPoint(x: 100, y: 200), within: 3)
        XCTAssertEqual(end.y, start.y, "A nearly level arrow is made level.")
        XCTAssertEqual(end.x, 320, accuracy: 3)

        // The outline is the shaft and a head whose barbs point back on either side of it.
        let outline = shape.outlinePoints(spacing: 4)
        XCTAssertEqual(outline.first, start)
        XCTAssertGreaterThanOrEqual(outline.filter { point in point == end }.count, 4, "The tip is sharp, and the head returns to it.")
        let barbEnds = outline.filter { point in abs(point.y - start.y) > 5 }
        XCTAssertTrue(barbEnds.contains { point in point.y < start.y } && barbEnds.contains { point in point.y > start.y })
        XCTAssertTrue(barbEnds.allSatisfy { point in point.x < end.x && point.x > end.x - 30 })

        // A diagonal arrow keeps its angle, whichever barb is drawn first.
        let diagonal = strokeAlong([CGPoint(x: 50, y: 300), CGPoint(x: 200, y: 120)], wobbleAmplitude: 1, closes: false)
        guard case .arrow(_, let diagonalEnd) = try XCTUnwrap(ShapeRecognizer.recognize(arrowStroke(shaft: diagonal, spreadDegrees: -35))) else { return XCTFail("Not an arrow") }
        assertPoint(diagonalEnd, near: CGPoint(x: 200, y: 120), within: 4)
    }

    func testArcEndingInAHeadBecomesACurvedArrow() throws {
        let shaft = ellipseStroke(center: CGPoint(x: 300, y: 300), horizontalRadius: 100, verticalRadius: 100, rotationDegrees: 0,
                                  startDegrees: 180, turnDegrees: 140, wobbleAmplitude: 0.8)
        let shape = try XCTUnwrap(ShapeRecognizer.recognize(arrowStroke(shaft: shaft)))
        guard case .curvedArrow(let center, let radius, _, let sweepAngle) = shape else { return XCTFail("Not a curved arrow: \(shape)") }
        assertPoint(center, near: CGPoint(x: 300, y: 300), within: 8)
        XCTAssertEqual(radius, 100, accuracy: 8)
        XCTAssertEqual(sweepAngle * 180 / .pi, 140, accuracy: 8)
        let tip = try XCTUnwrap(shape.endpoints).end
        assertPoint(tip, near: shaft[shaft.count - 1], within: 6)
        // The head's barbs are beside the tip, behind it along the arc.
        let outline = shape.outlinePoints(spacing: 4)
        XCTAssertTrue(outline.suffix(12).allSatisfy { point in hypot(point.x - tip.x, point.y - tip.y) <= 25 })
    }

    func testStrokesThatOnlyLookLikeArrowsAreNot() throws {
        // A check mark has one short leg and one long one, and no shaft before them.
        let checkMark = strokeAlong([CGPoint(x: 100, y: 200), CGPoint(x: 130, y: 240), CGPoint(x: 220, y: 120)], wobbleAmplitude: 0.5, closes: false)
        if let shape = ShapeRecognizer.recognize(checkMark) {
            if case .arrow = shape { XCTFail("A check mark is no arrow") }
            if case .curvedArrow = shape { XCTFail("A check mark is no arrow") }
        }
        // A zigzag with both legs on one side of the line.
        let zigzag = strokeAlong([CGPoint(x: 100, y: 200), CGPoint(x: 300, y: 200), CGPoint(x: 270, y: 170), CGPoint(x: 300, y: 200), CGPoint(x: 330, y: 170)],
                                 wobbleAmplitude: 0.5, closes: false)
        XCTAssertNil(ShapeRecognizer.recognize(zigzag))
        // A head as long as the shaft is a letter, not an arrow.
        let shaft = strokeAlong([CGPoint(x: 100, y: 200), CGPoint(x: 150, y: 200)], wobbleAmplitude: 0.5, closes: false)
        XCTAssertNil(ShapeRecognizer.recognize(arrowStroke(shaft: shaft, barbLength: 45)))
    }

    // MARK: Dragging a held shape

    func testDraggingAnOpenShapeKeepsItsStartAndMovesItsEnd() throws {
        let line = RecognizedShape.line(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 200, y: 100))
        guard case .line(let lineStart, let lineEnd) = line.dragging(from: CGPoint(x: 200, y: 100), to: CGPoint(x: 100, y: 300)) else { return XCTFail("A line stays a line") }
        XCTAssertEqual(lineStart, CGPoint(x: 100, y: 100))
        assertPoint(lineEnd, near: CGPoint(x: 100, y: 300), within: 0.001)
        guard case .arrow(let start, let end) = RecognizedShape.arrow(start: .zero, end: CGPoint(x: 50, y: 0)).dragging(from: CGPoint(x: 50, y: 0), to: CGPoint(x: 60, y: 80)) else {
            return XCTFail("An arrow stays an arrow")
        }
        XCTAssertEqual(start, .zero)
        assertPoint(end, near: CGPoint(x: 60, y: 80), within: 0.001)

        // An arc turns and stretches as a whole: same sweep, its end under the hand.
        let arc = RecognizedShape.arc(center: CGPoint(x: 100, y: 100), radius: 50, startAngle: .pi, sweepAngle: .pi / 2)
        let draggedArc = arc.dragging(from: try XCTUnwrap(arc.endpoints).end, to: CGPoint(x: 250, y: 100))
        guard case .arc(_, let radius, _, let sweepAngle) = draggedArc else { return XCTFail("An arc stays an arc") }
        XCTAssertEqual(sweepAngle, .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(radius, 50 * 200 / (50 * 2.0.squareRoot()), accuracy: 0.001)
        let draggedEndpoints = try XCTUnwrap(draggedArc.endpoints)
        assertPoint(draggedEndpoints.start, near: CGPoint(x: 50, y: 100), within: 0.001)
        assertPoint(draggedEndpoints.end, near: CGPoint(x: 250, y: 100), within: 0.001)

        // A drag back onto the start has no direction to follow.
        XCTAssertEqual(line.dragging(from: CGPoint(x: 200, y: 100), to: CGPoint(x: 101, y: 100)), line)
    }

    func testDraggingAClosedShapeKeepsItsMiddleAndScalesIt() throws {
        let square = RecognizedShape.polygon(corners: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)])
        XCTAssertFalse(RecognizedShape.line(start: .zero, end: CGPoint(x: 1, y: 1)).isClosed)
        XCTAssertTrue(square.isClosed)
        XCTAssertEqual(square.center, CGPoint(x: 50, y: 50))
        XCTAssertNil(square.endpoints)
        // The hand, resting on a corner, moves twice as far from the middle.
        guard case .polygon(let corners) = square.dragging(from: .zero, to: CGPoint(x: -50, y: -50)) else { return XCTFail("A polygon stays a polygon") }
        XCTAssertEqual(corners, [CGPoint(x: -50, y: -50), CGPoint(x: 150, y: -50), CGPoint(x: 150, y: 150), CGPoint(x: -50, y: 150)])

        let ellipse = RecognizedShape.ellipse(center: CGPoint(x: 10, y: 10), horizontalRadius: 40, verticalRadius: 20, rotation: 0.3)
        XCTAssertEqual(ellipse.dragging(from: CGPoint(x: 50, y: 10), to: CGPoint(x: 30, y: 10)),
                       .ellipse(center: CGPoint(x: 10, y: 10), horizontalRadius: 20, verticalRadius: 10, rotation: 0.3))
        // Dragging into the middle leaves a small shape, not none.
        guard case .ellipse(_, let smallestRadius, _, _) = ellipse.dragging(from: CGPoint(x: 50, y: 10), to: CGPoint(x: 10, y: 10)) else { return XCTFail("An ellipse stays one") }
        XCTAssertEqual(smallestRadius, 4, accuracy: 0.001)
        // A hand resting on the middle gives no measure to scale by.
        XCTAssertEqual(ellipse.dragging(from: CGPoint(x: 11, y: 10), to: CGPoint(x: 90, y: 10)), ellipse)

        // The same transform serves to bring a shape from the screen's scale to the page's.
        XCTAssertEqual(square.transformed(scale: 0.5, rotation: 0, about: .zero),
                       .polygon(corners: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 0, y: 50)]))
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
