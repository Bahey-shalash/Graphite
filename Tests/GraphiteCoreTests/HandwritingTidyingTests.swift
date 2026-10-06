import XCTest
import CoreGraphics
@testable import GraphiteCore

/// Straightening a line of handwriting and smoothing its strokes.
final class HandwritingTidyingTests: XCTestCase {
    /// Points of a line of "letters" that runs at `degrees` from the horizontal, each letter
    /// a zigzag across the line.
    private func lineOfWriting(degrees: CGFloat, letterHeight: CGFloat = 20) -> [CGPoint] {
        let angle = degrees * .pi / 180
        return (0..<120).map { pointIndex in
            let along = CGFloat(pointIndex) * 3
            let across = pointIndex.isMultiple(of: 2) ? -letterHeight / 2 : letterHeight / 2
            return CGPoint(x: 100 + along * cos(angle) - across * sin(angle), y: 200 + along * sin(angle) + across * cos(angle))
        }
    }

    func testTheSlantOfALineOfWritingIsItsDirection() throws {
        XCTAssertEqual(try XCTUnwrap(HandwritingTidying.slantOfLine(through: lineOfWriting(degrees: 10))), 10 * .pi / 180, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(HandwritingTidying.slantOfLine(through: lineOfWriting(degrees: -18))), -18 * .pi / 180, accuracy: 0.01)
        XCTAssertNil(HandwritingTidying.slantOfLine(through: lineOfWriting(degrees: 0)), "A level line is left alone.")
        XCTAssertNil(HandwritingTidying.slantOfLine(through: lineOfWriting(degrees: 45)), "Steeper ink is not a line of writing to level.")
        XCTAssertNil(HandwritingTidying.slantOfLine(through: lineOfWriting(degrees: 90)))
    }

    func testInkThatIsNotOneLineHasNoSlant() {
        let square = (0..<40).map { pointIndex in CGPoint(x: CGFloat(pointIndex % 10) * 10, y: CGFloat(pointIndex / 10) * 25) }
        XCTAssertNil(HandwritingTidying.slantOfLine(through: square), "A block of ink as tall as it is wide.")
        XCTAssertNil(HandwritingTidying.slantOfLine(through: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 2)]))
        XCTAssertNil(HandwritingTidying.slantOfLine(through: Array(repeating: CGPoint(x: 5, y: 5), count: 10)))
        XCTAssertNil(HandwritingTidying.slantOfLine(through: [CGPoint(x: 0, y: 0), CGPoint(x: CGFloat.nan, y: 1), CGPoint(x: 3, y: 1)]))
    }

    func testSmoothingFlattensTremorAndKeepsTheEnds() {
        let trembling = (0...30).map { pointIndex in CGPoint(x: CGFloat(pointIndex) * 4, y: 100 + (pointIndex.isMultiple(of: 2) ? 2 : -2)) }
        let smoothed = HandwritingTidying.smoothed(trembling)
        XCTAssertEqual(smoothed.count, trembling.count)
        XCTAssertEqual(smoothed.first, trembling.first)
        XCTAssertEqual(smoothed.last, trembling.last)
        let inner = smoothed.dropFirst(3).dropLast(3)
        XCTAssertLessThan(inner.map { point in abs(point.y - 100) }.max() ?? 0, 0.5)
        // A straight stroke stays straight, point for point.
        let straight = (0...10).map { pointIndex in CGPoint(x: CGFloat(pointIndex) * 5, y: CGFloat(pointIndex) * 2) }
        for (smoothedPoint, point) in zip(HandwritingTidying.smoothed(straight), straight) {
            XCTAssertEqual(smoothedPoint.x, point.x, accuracy: 0.0001)
            XCTAssertEqual(smoothedPoint.y, point.y, accuracy: 0.0001)
        }
        // A stroke too short to smooth, such as a dot, is kept as it is.
        let dot = [CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 3), CGPoint(x: 1, y: 2)]
        XCTAssertEqual(HandwritingTidying.smoothed(dot), dot)
    }
}
