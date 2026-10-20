#if canImport(UIKit)
import XCTest
import PencilKit
import UIKit
import GraphiteApple
@testable import GraphiteUI

/// Graphite's lasso on a canvas: what a loop or a tap selects, what a resize does to the
/// strokes it carries, and the time smoothing gives the strokes it changes. The canvas is not
/// in a window, so one canvas point is one screen point and the zoom is 1.
@MainActor
final class InkSelectionControllerTests: XCTestCase {
    private func stroke(through points: [CGPoint], size: CGFloat = 2, createdAt seconds: TimeInterval = 1_000, mask: UIBezierPath? = nil) -> PKStroke {
        let controlPoints = points.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: TimeInterval(index) / 100, size: CGSize(width: size, height: size), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: controlPoints, creationDate: Date(timeIntervalSince1970: seconds)),
                        transform: .identity, mask: mask, randomSeed: 3)
    }

    private func horizontalStroke(y: CGFloat, from startX: CGFloat = 0, to endX: CGFloat = 100) -> PKStroke {
        stroke(through: stride(from: startX, through: endX, by: 10).map { x in CGPoint(x: x, y: y) })
    }

    private func controller(showing strokes: [PKStroke]) throws -> (canvas: HistoryCanvasView, controller: InkSelectionController) {
        try XCTSkipIf(LassoShape.stored != .freehand, "A rectangular lasso is chosen on this device.")
        let canvas = HistoryCanvasView(frame: CGRect(x: 0, y: 0, width: 600, height: 600))
        canvas.drawing = PKDrawing(strokes: strokes)
        let controller = canvas.inkSelection
        controller.isActive = true
        return (canvas, controller)
    }

    /// A freehand loop through the points, begun at the first.
    private func drawLoop(_ points: [CGPoint], with controller: InkSelectionController) {
        controller.loopDidBegin(at: points[0], reaching: points[1])
        for point in points.dropFirst(2) { controller.loopDidMove(to: point) }
        controller.loopDidEnd(at: points[points.count - 1])
    }

    private func box(from left: CGFloat, to right: CGFloat) -> [CGPoint] {
        [CGPoint(x: left, y: 20), CGPoint(x: right, y: 20), CGPoint(x: right, y: 80), CGPoint(x: left, y: 80), CGPoint(x: left, y: 20)]
    }

    // MARK: Which strokes a loop takes

    func testALoopTakesAStrokeWhenSeventyPercentOfItIsInsideAndMarksAnAreaWhenFiftyPercentIs() throws {
        let (_, controller) = try controller(showing: [horizontalStroke(y: 50)])
        drawLoop(box(from: -10, to: 70), with: controller)
        XCTAssertEqual(controller.selectedStrokeIndices, [0], "70 % of the stroke is inside.")

        controller.clearSelection()
        drawLoop(box(from: -10, to: 50), with: controller)
        XCTAssertEqual(controller.selectedStrokeIndices, [], "50 % is not enough.")
        XCTAssertTrue(controller.isShowingLassoedArea, "A loop that takes nothing marks its area.")
    }

    func testALoopShorterThanTwentyFourPointsIsASlipAndOneOfTwentyFourPointsIsNot() throws {
        let (_, controller) = try controller(showing: [])
        drawLoop([CGPoint(x: 100, y: 100), CGPoint(x: 111, y: 100), CGPoint(x: 123, y: 100)], with: controller)
        XCTAssertFalse(controller.isShowingLassoedArea, "A 23-point loop is a slip: nothing is selected or marked.")
        controller.clearSelection()
        drawLoop([CGPoint(x: 100, y: 100), CGPoint(x: 112, y: 100), CGPoint(x: 124, y: 100)], with: controller)
        XCTAssertTrue(controller.isShowingLassoedArea, "A 24-point loop is a loop.")
    }

    func testATapReachesFourteenPointsBeyondTheInkOfAStrokeAndNoFurther() throws {
        let (_, controller) = try controller(showing: [horizontalStroke(y: 50)])
        XCTAssertTrue(controller.selectStroke(at: CGPoint(x: 50, y: 64)), "14 points below the stroke's centre line is within reach of its ink.")
        XCTAssertEqual(controller.selectedStrokeIndices, [0])
        XCTAssertFalse(controller.selectStroke(at: CGPoint(x: 50, y: 66)), "16 points away is beside the ink.")
        XCTAssertEqual(controller.selectedStrokeIndices, [], "A tap beside the ink ends the selection.")
    }

    // MARK: Smoothing

    func testASmoothedStrokeGetsTheSmoothingTimeAsItsCreationDateAndAnUnchangedOneKeepsItsOwn() throws {
        let tremor = (0..<40).map { index in CGPoint(x: CGFloat(index) * 5, y: index.isMultiple(of: 2) ? 40 : 60) }
        let tremblingStroke = stroke(through: tremor, createdAt: 1_000)
        let shortStroke = stroke(through: [CGPoint(x: 0, y: 100), CGPoint(x: 10, y: 100), CGPoint(x: 20, y: 100)], createdAt: 2_000)
        let (canvas, controller) = try controller(showing: [tremblingStroke, shortStroke])
        controller.select([0, 1])

        let smoothingStart = Date()
        controller.smoothSelection()
        let smoothingEnd = Date()

        let strokes = canvas.drawing.strokes
        XCTAssertEqual(strokes.count, 2)
        let smoothedDate = strokes[0].path.creationDate
        XCTAssertGreaterThanOrEqual(smoothedDate, smoothingStart.addingTimeInterval(-0.001))
        XCTAssertLessThanOrEqual(smoothedDate, smoothingEnd.addingTimeInterval(0.001))
        XCTAssertNotEqual(Array(strokes[0].path).map(\.location), tremor, "The tremor is smoothed out.")
        XCTAssertEqual(strokes[0].path.first?.location, tremor.first, "Its ends stay where they are.")
        XCTAssertEqual(strokes[0].path.last?.location, tremor.last)
        XCTAssertEqual(strokes[1].path.creationDate.timeIntervalSince1970, 2_000, accuracy: 0.001, "A stroke smoothing did not change keeps its own date.")
    }

    // MARK: Moving and resizing

    func testMovingASelectionBakesTheMoveIntoPointsAndMaskAndKeepsAnIdentityTransform() throws {
        let mask = UIBezierPath(rect: CGRect(x: 90, y: 90, width: 40, height: 40))
        let original = stroke(through: [CGPoint(x: 100, y: 100), CGPoint(x: 140, y: 120), CGPoint(x: 180, y: 100)], size: 4, mask: mask)
        let (canvas, controller) = try controller(showing: [original])
        controller.select([0])
        let frame = try XCTUnwrap(controller.selectionFrame)

        controller.moveSelection(in: canvas.drawing, from: frame, to: frame.offsetBy(dx: 60, dy: 30))

        let moved = try XCTUnwrap(canvas.drawing.strokes.first)
        XCTAssertEqual(moved.transform, .identity)
        XCTAssertEqual(Array(moved.path).map(\.location), Array(original.path).map { point in CGPoint(x: point.location.x + 60, y: point.location.y + 30) })
        XCTAssertEqual(Array(moved.path).map(\.size), Array(original.path).map(\.size), "A move keeps the breadth.")
        let movedMask = try XCTUnwrap(moved.mask)
        XCTAssertEqual(movedMask.bounds.origin.x, mask.bounds.origin.x + 60, accuracy: 0.001)
        XCTAssertEqual(movedMask.bounds.origin.y, mask.bounds.origin.y + 30, accuracy: 0.001)
        XCTAssertEqual(moved.path.creationDate, original.path.creationDate)
    }

    func testResizingASelectionScalesPointsAndBreadthAndSettlesOnTheRequestedRenderBounds() throws {
        let original = stroke(through: [CGPoint(x: 100, y: 100), CGPoint(x: 140, y: 120), CGPoint(x: 180, y: 100)], size: 4)
        let (canvas, controller) = try controller(showing: [original])
        controller.select([0])
        let frame = try XCTUnwrap(controller.selectionFrame)
        let margin: CGFloat = 8
        let originalBounds = frame.insetBy(dx: margin, dy: margin)
        let targetBounds = CGRect(x: originalBounds.minX, y: originalBounds.minY, width: originalBounds.width * 2, height: originalBounds.height * 2)

        controller.moveSelection(in: canvas.drawing, from: frame, to: targetBounds.insetBy(dx: -margin, dy: -margin))

        let resized = try XCTUnwrap(canvas.drawing.strokes.first)
        XCTAssertEqual(resized.transform, .identity)
        let tolerance: CGFloat = 0.25
        XCTAssertEqual(resized.renderBounds.minX, targetBounds.minX, accuracy: tolerance)
        XCTAssertEqual(resized.renderBounds.minY, targetBounds.minY, accuracy: tolerance)
        XCTAssertEqual(resized.renderBounds.width, targetBounds.width, accuracy: tolerance, "The rebuilt ink fills the frame it was dragged to.")
        let originalSize = try XCTUnwrap(original.path.first?.size.width), resizedSize = try XCTUnwrap(resized.path.first?.size.width)
        XCTAssertGreaterThan(resizedSize, originalSize * 1.5, "The breadth is baked in with the points.")
    }
}
#endif
