import XCTest
import CoreGraphics
@testable import GraphiteCore

final class DrawingGeometryTests: XCTestCase {
    func testExportKeepsCanvasWidthAndCropsHeightToInk() {
        let bounds = DrawingCanvasGeometry.exportBounds(inkBounds: CGRect(x: 100, y: 400, width: 300, height: 200), canvasWidth: 1024)
        XCTAssertEqual(bounds, CGRect(x: 0, y: 376, width: 1024, height: 248))
    }

    func testInkOutsideTheCanvasIsNeverCropped() {
        let bounds = DrawingCanvasGeometry.exportBounds(inkBounds: CGRect(x: -50, y: -10, width: 1200, height: 20), canvasWidth: 1024)
        XCTAssertLessThanOrEqual(bounds.minX, -50)
        XCTAssertGreaterThanOrEqual(bounds.maxX, 1150)
        XCTAssertLessThanOrEqual(bounds.minY, -10)
        XCTAssertGreaterThanOrEqual(bounds.height, DrawingLimits.minimumExportHeight)
    }

    func testEmptyDrawingHasAMinimumSize() {
        XCTAssertEqual(DrawingCanvasGeometry.exportBounds(inkBounds: nil, canvasWidth: 800), CGRect(x: 0, y: 0, width: 800, height: DrawingLimits.minimumExportHeight))
    }

    func testPNGScaleDropsForTallDrawingsAndRefusesUnreadableOnes() {
        XCTAssertEqual(DrawingCanvasGeometry.pngScale(for: CGSize(width: 1024, height: 2000)), 2)
        let tallScale = try? XCTUnwrap(DrawingCanvasGeometry.pngScale(for: CGSize(width: 1366, height: 20_000)))
        XCTAssertNotNil(tallScale)
        XCTAssertLessThan(tallScale ?? 2, 2)
        XCTAssertNil(DrawingCanvasGeometry.pngScale(for: CGSize(width: 1366, height: 60_000)))
    }

    func testPayloadRejectsCorruptAndOversizedMetadata() throws {
        let payload = DrawingPayload(width: 800, height: 600, background: .white, strokes: Data([1, 2, 3]))
        XCTAssertEqual(DrawingPayload.decodeIfValid(try payload.encoded()), payload)
        XCTAssertNil(DrawingPayload.decodeIfValid(Data("not a property list".utf8)))
        XCTAssertThrowsError(try DrawingPayload(width: 900_000, height: 10, background: .white, strokes: Data()).encoded())
    }
}
