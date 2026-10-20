#if canImport(UIKit)
import XCTest
import PencilKit
import UIKit
import GraphiteApple
@testable import GraphiteUI

/// What a canvas does when its document's history gives it a drawing back, and what it
/// remembers of each tool's strokes for shapes made from a hold.
@MainActor
final class HistoryCanvasViewHistoryTests: XCTestCase {
    /// A canvas that notes what it recorded and had selected at the moment its drawing was set.
    private final class WatchedCanvas: HistoryCanvasView {
        var events: [String] = []
        override var drawing: PKDrawing {
            willSet {
                events.append("drawing:recorded=\(recordedDrawing.strokes.count),shown=\(newValue.strokes.count),selected=\(inkSelection.selectedStrokeIndices.count)")
            }
        }
    }

    private func stroke(startX: CGFloat, size: CGFloat = 3, inkType: PKInk.InkType = .pen) -> PKStroke {
        let points = (0...4).map { step in
            PKStrokePoint(location: CGPoint(x: startX + CGFloat(step) * 10, y: 30), timeOffset: TimeInterval(step) / 10,
                          size: CGSize(width: size, height: size), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(inkType, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 500 + Double(startX))),
                        transform: .identity, mask: nil, randomSeed: 5)
    }

    func testADrawingFromTheHistoryIsRecordedBeforeItIsShownAndASelectionIsEndedFirst() throws {
        let canvas = WatchedCanvas(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let earlier = PKDrawing(strokes: [stroke(startX: 0)])
        canvas.drawing = PKDrawing(strokes: [stroke(startX: 0), stroke(startX: 100)])
        canvas.recordedDrawing = canvas.drawing
        canvas.inkSelection.isActive = true
        canvas.inkSelection.select([1])
        XCTAssertEqual(canvas.inkSelection.selectedStrokeIndices, [1])
        canvas.events = []

        canvas.showDrawingFromHistory(earlier)

        XCTAssertEqual(canvas.events, ["drawing:recorded=1,shown=1,selected=0"],
                       "The recorded drawing already is the shown one and the selection is gone when the canvas reports the change.")
        XCTAssertEqual(canvas.recordedDrawing.strokes.count, 1)
        XCTAssertEqual(canvas.inkSelection.selectedStrokeIndices, [])
    }

    func testTheLassoStaysTheToolWhenADrawingFromTheHistoryEndsItsSelection() {
        let canvas = WatchedCanvas(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        canvas.tool = PKLassoTool()
        canvas.events = []

        canvas.showDrawingFromHistory(PKDrawing(strokes: [stroke(startX: 0)]))

        XCTAssertEqual(canvas.events, ["drawing:recorded=1,shown=1,selected=0"])
        XCTAssertTrue(canvas.tool is PKLassoTool, "The lasso stays the tool.")
    }

    // MARK: Footprints

    func testAFootprintIsKeptPerInkAndPerWidthRoundedToHundredthsOfAPoint() throws {
        let canvas = HistoryCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let tool = PKInkingTool(.pen, color: .black, width: 5.37)
        canvas.tool = tool
        XCTAssertNil(HistoryCanvasView.footprint(of: tool), "Nothing is known until a stroke has been drawn with the tool at this width.")

        canvas.drawing = PKDrawing(strokes: [stroke(startX: 0, size: 4.5)])
        _ = canvas.drawingAfterShapeRecognition(shapeToolIsOn: false)

        let footprint = try XCTUnwrap(HistoryCanvasView.footprint(of: tool))
        XCTAssertEqual(footprint.size.width, 4.5, accuracy: 0.001)
        XCTAssertNotNil(HistoryCanvasView.footprint(of: PKInkingTool(.pen, color: .red, width: tool.width + 0.004)), "The colour does not matter and the width is rounded to hundredths.")
        XCTAssertNil(HistoryCanvasView.footprint(of: PKInkingTool(.pen, color: .black, width: tool.width + 0.01)), "Another hundredth is another key.")
        XCTAssertNil(HistoryCanvasView.footprint(of: PKInkingTool(.marker, color: .black, width: tool.width)), "Another ink is another key.")
    }
}
#endif
