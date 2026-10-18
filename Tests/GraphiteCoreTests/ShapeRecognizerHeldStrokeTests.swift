import XCTest
import CoreGraphics
@testable import GraphiteCore

final class ShapeRecognizerHeldStrokeTests: XCTestCase {
    /// A closed, slightly wobbling circle drawn on the zoomed canvas.
    private func circleStroke(diameter: Double, around center: CGPoint) -> [CGPoint] {
        (0...80).map { pointIndex in
            let angle = (20 + 350 * Double(pointIndex) / 80) * .pi / 180
            let wobble = 0.01 * diameter * sin(Double(pointIndex) * 0.9)
            return CGPoint(x: center.x + (diameter / 2 + wobble) * cos(angle), y: center.y + (diameter / 2 + wobble) * sin(angle))
        }
    }

    func testAStrokeJudgedOnTheZoomedCanvasBecomesAShapeInDrawingCoordinates() throws {
        let zoomScale = 3.0
        let canvasStroke = circleStroke(diameter: 30, around: CGPoint(x: 300, y: 300))
        let drawingStroke = canvasStroke.map { point in CGPoint(x: point.x / zoomScale, y: point.y / zoomScale) }
        XCTAssertNil(ShapeRecognizer.recognize(drawingStroke), "At 10 drawing points across, a second recognition in drawing coordinates rejects the circle.")

        let heldShape = try XCTUnwrap(ShapeRecognizer.recognizeHeldStroke(canvasPoints: canvasStroke, zoomScale: zoomScale))

        guard case .ellipse(let center, let horizontalRadius, let verticalRadius, _) = heldShape else { return XCTFail("Expected a circle, got \(heldShape)") }
        XCTAssertEqual(center.x, 100, accuracy: 1)
        XCTAssertEqual(center.y, 100, accuracy: 1)
        XCTAssertEqual(horizontalRadius, 5, accuracy: 0.5)
        XCTAssertEqual(verticalRadius, 5, accuracy: 0.5)
    }

    func testAStrokeThatIsNotAShapeOnTheCanvasIsNotHeldAsOne() {
        let scribble = (0...40).map { pointIndex in CGPoint(x: Double(pointIndex) * 0.2, y: Double(pointIndex % 2)) }

        XCTAssertNil(ShapeRecognizer.recognizeHeldStroke(canvasPoints: scribble, zoomScale: 1))
    }

    func testAZoomOfZeroRecognizesNothing() {
        XCTAssertNil(ShapeRecognizer.recognizeHeldStroke(canvasPoints: circleStroke(diameter: 42, around: .zero), zoomScale: 0))
    }
}
