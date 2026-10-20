#if canImport(UIKit)
import XCTest
import PencilKit
import UIKit
import GraphiteCore
@testable import GraphiteApple

/// Where a saved drawing starts: the region around its ink and pictures, grown onto the lines
/// of its paper, becomes the origin of everything stored in the file.
final class DrawingFileServiceExportRegionTests: XCTestCase {
    private func stroke(atHeight height: CGFloat) -> PKStroke {
        let controlPoints = (0...10).map { step in
            PKStrokePoint(location: CGPoint(x: 100 + CGFloat(step) * 30, y: height), timeOffset: TimeInterval(step) / 10,
                          size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: controlPoints, creationDate: Date(timeIntervalSince1970: 1)))
    }

    private func pictureData() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0, green: 0.5, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage()))
    }

    private func savedPayload(_ content: DrawingContent) async throws -> DrawingPayload {
        let fileData = try await DrawingFileService().fileData(for: content, format: .svg)
        return try XCTUnwrap(DrawingMetadataReader.readMetadata(fileData, format: .svg).payload)
    }

    func testStrokesAndPicturesAreStoredRelativeToTheRegionInPlainPaper() async throws {
        let drawing = PKDrawing(strokes: [stroke(atHeight: 500)])
        let picture = DrawingBackgroundImage(imageData: try pictureData(), frame: CGRect(x: 40, y: 300, width: 120, height: 80))
        let content = DrawingContent(strokeData: drawing.dataRepresentation(), canvasWidth: 800, background: .white, pictures: [picture])
        let contentBounds = try XCTUnwrap(DrawingCanvasGeometry.contentBounds(inkBounds: drawing.bounds, pictureFrames: [picture.boundingFrame]))
        let region = DrawingCanvasGeometry.exportBounds(inkBounds: contentBounds, canvasWidth: 800)

        let payload = try await savedPayload(content)
        XCTAssertEqual(payload.width, region.width)
        XCTAssertEqual(payload.height, region.height)
        XCTAssertEqual(try PKDrawing(data: payload.strokes).bounds.minY, drawing.bounds.minY - region.minY, accuracy: 0.01)
        XCTAssertEqual(try PKDrawing(data: payload.strokes).bounds.minX, drawing.bounds.minX - region.minX, accuracy: 0.01)
        XCTAssertEqual(payload.pictures.first?.frame, picture.frame.offsetBy(dx: -region.minX, dy: -region.minY))
        XCTAssertEqual(payload.pictures.first?.imageData, picture.imageData)
    }

    func testTheRegionStartsOnALineOfSquaredPaperAndEverythingIsStoredFromThere() async throws {
        let drawing = PKDrawing(strokes: [stroke(atHeight: 500)])
        let paper = DrawingPaper(pattern: .squared, appearsInSavedDrawing: true)
        let content = DrawingContent(strokeData: drawing.dataRepresentation(), canvasWidth: 800, background: .white, paper: paper)
        let unaligned = DrawingCanvasGeometry.exportBounds(inkBounds: drawing.bounds, canvasWidth: 800)
        let region = DrawingCanvasGeometry.startingOnPaperLines(unaligned, of: .squared)
        XCTAssertEqual(region.minY.truncatingRemainder(dividingBy: DrawingPaperGeometry.squareSize), 0)
        XCTAssertLessThanOrEqual(region.minY, unaligned.minY)

        let payload = try await savedPayload(content)
        XCTAssertEqual(payload.height, region.height)
        XCTAssertEqual(try PKDrawing(data: payload.strokes).bounds.minY, drawing.bounds.minY - region.minY, accuracy: 0.01)
        XCTAssertEqual(payload.paper, paper)
    }

    func testADrawingOnAnImageIsExactlyTheImageWhileTheInkStaysOnIt() async throws {
        let drawing = PKDrawing(strokes: [stroke(atHeight: 150)])
        let image = DrawingBackgroundImage(imageData: try pictureData(), frame: CGRect(x: 20, y: 40, width: 500, height: 300))
        let content = DrawingContent(strokeData: drawing.dataRepresentation(), canvasWidth: 800, background: .white, backgroundImage: image)

        let payload = try await savedPayload(content)
        XCTAssertEqual(payload.width, 500)
        XCTAssertEqual(payload.height, 300)
        XCTAssertEqual(payload.backgroundImage?.frame, CGRect(x: 0, y: 0, width: 500, height: 300))
        XCTAssertEqual(try PKDrawing(data: payload.strokes).bounds.minY, drawing.bounds.minY - 40, accuracy: 0.01)
    }
}
#endif
