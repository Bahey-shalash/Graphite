import XCTest
@testable import MermaidDiagrams

final class DiagramRouteDrawingTests: XCTestCase {
    func testPointsInLineAreJoinedStraight() {
        let drawn = DiagramRouteDrawing.path(through: [CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 50)], flowIsVertical: true, startTrim: 0, endTrim: 0)
        XCTAssertEqual(drawn.path.segments, [.line(to: CGPoint(x: 10, y: 50))])
        XCTAssertEqual(drawn.endDirection, CGVector(dx: 0, dy: 1))
    }

    func testPointsOutOfLineAreJoinedByAnSAlongTheFlow() {
        let drawn = DiagramRouteDrawing.path(through: [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 100)], flowIsVertical: true, startTrim: 0, endTrim: 0)
        XCTAssertEqual(drawn.path.segments, [.curve(to: CGPoint(x: 40, y: 100), control1: CGPoint(x: 0, y: 50), control2: CGPoint(x: 40, y: 50))])
        XCTAssertEqual(drawn.startDirection, CGVector(dx: 0, dy: 1))
        let across = DiagramRouteDrawing.path(through: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 40)], flowIsVertical: false, startTrim: 0, endTrim: 0)
        XCTAssertEqual(across.path.segments, [.curve(to: CGPoint(x: 100, y: 40), control1: CGPoint(x: 50, y: 0), control2: CGPoint(x: 50, y: 40))])
    }

    func testTheEndsAreShortenedByTheirMarks() {
        let drawn = DiagramRouteDrawing.path(through: [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 100)], flowIsVertical: true, startTrim: 4, endTrim: 7)
        XCTAssertEqual(drawn.path.start, CGPoint(x: 0, y: 4))
        XCTAssertEqual(drawn.path.segments, [.line(to: CGPoint(x: 0, y: 93))])
    }

    func testEachSegmentTurnsAlongItsOwnFlow() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 100), CGPoint(x: 140, y: 140)]
        let drawn = DiagramRouteDrawing.path(through: points, segmentsRunVertically: [true, false], startTrim: 0, endTrim: 0)
        XCTAssertEqual(drawn.path.segments, [
            .curve(to: CGPoint(x: 40, y: 100), control1: CGPoint(x: 0, y: 50), control2: CGPoint(x: 40, y: 50)),
            .curve(to: CGPoint(x: 140, y: 140), control1: CGPoint(x: 90, y: 100), control2: CGPoint(x: 90, y: 140)),
        ])
        XCTAssertEqual(drawn.startDirection, CGVector(dx: 0, dy: 1))
        XCTAssertEqual(drawn.endDirection, CGVector(dx: 1, dy: 0))
    }
}
