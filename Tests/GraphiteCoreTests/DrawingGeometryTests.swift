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

    func testDrawingOnAnImageIsSavedAsThePictureUnlessInkLeavesIt() {
        let pictureFrame = CGRect(x: 0, y: 0, width: 760, height: 506.4)
        // Ink on the picture: the file has the picture's proportions, with no margin.
        XCTAssertEqual(DrawingCanvasGeometry.exportBounds(inkBounds: CGRect(x: 100, y: 100, width: 200, height: 50), backgroundImageFrame: pictureFrame),
                       pictureFrame.integral)
        XCTAssertEqual(DrawingCanvasGeometry.exportBounds(inkBounds: nil, backgroundImageFrame: pictureFrame), pictureFrame.integral)
        // Notes written below the picture are kept, with the usual margin.
        let bounds = DrawingCanvasGeometry.exportBounds(inkBounds: CGRect(x: 40, y: 540, width: 300, height: 60), backgroundImageFrame: pictureFrame)
        XCTAssertEqual(bounds.minY, 0)
        XCTAssertEqual(bounds.maxY, 600 + DrawingLimits.exportMargin)
        XCTAssertEqual(bounds.width, 760)
    }

    func testPayloadWithAPictureIsVersionTwoAndRoundTrips() throws {
        let picture = DrawingBackgroundImage(imageData: Data([0xFF, 0xD8, 0xFF, 0xE0]), frame: CGRect(x: 0, y: 0, width: 760, height: 400))
        let payload = DrawingPayload(width: 760, height: 400, background: .white, strokes: Data([1, 2, 3]), backgroundImage: picture)
        XCTAssertEqual(payload.version, 2)
        let decoded = try XCTUnwrap(DrawingPayload.decodeIfValid(try payload.encoded()))
        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.backgroundImage, picture)
        XCTAssertEqual(payload.replacingVisibleContentDigest(Data([9])).backgroundImage, picture, "Writing the digest keeps the picture.")
        // A drawing without a picture stays version 1, which every build reads.
        let plainPayload = DrawingPayload(width: 760, height: 400, background: .white, strokes: Data([1, 2, 3]))
        XCTAssertEqual(plainPayload.version, 1)
        XCTAssertNil(try XCTUnwrap(DrawingPayload.decodeIfValid(try plainPayload.encoded())).backgroundImage)
    }

    func testPayloadRejectsPicturesThatCannotBePlaced() {
        let strokes = Data([1])
        let emptyPicture = DrawingBackgroundImage(imageData: Data(), frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertThrowsError(try DrawingPayload(width: 100, height: 100, background: .white, strokes: strokes, backgroundImage: emptyPicture).encoded())
        let unplacedPicture = DrawingBackgroundImage(imageData: Data([1]), frame: CGRect(x: 0, y: 0, width: Double.infinity, height: 100))
        XCTAssertThrowsError(try DrawingPayload(width: 100, height: 100, background: .white, strokes: strokes, backgroundImage: unplacedPicture).encoded())
        let hugePicture = DrawingBackgroundImage(imageData: Data(count: DrawingLimits.maximumBackgroundImageBytes + 1), frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertFalse(hugePicture.hasValidGeometry)
    }

    func testPayloadRejectsCorruptAndOversizedMetadata() throws {
        let payload = DrawingPayload(width: 800, height: 600, background: .white, strokes: Data([1, 2, 3]))
        XCTAssertEqual(DrawingPayload.decodeIfValid(try payload.encoded()), payload)
        XCTAssertNil(DrawingPayload.decodeIfValid(Data("not a property list".utf8)))
        XCTAssertThrowsError(try DrawingPayload(width: 900_000, height: 10, background: .white, strokes: Data()).encoded())
    }

    // MARK: Paper and placed pictures

    func testPaperLinesAreWhereThePatternPutsThem() {
        let region = CGRect(x: 10, y: 20, width: 60, height: 50)
        let squared = DrawingPaperGeometry.linePositions(of: .squared, in: region)
        XCTAssertEqual(squared.horizontal, [24, 48], "Horizontal lines every 24 points from the drawing's origin.")
        XCTAssertEqual(squared.vertical, [24, 48])
        let ruled = DrawingPaperGeometry.linePositions(of: .ruled, in: region)
        XCTAssertEqual(ruled.horizontal, [32, 64])
        XCTAssertTrue(ruled.vertical.isEmpty, "Ruled paper has no vertical lines.")
        XCTAssertEqual(DrawingPaperGeometry.linePositions(of: .dotted, in: region).vertical, squared.vertical, "Dots are where squares cross.")
        let plain = DrawingPaperGeometry.linePositions(of: .plain, in: region)
        XCTAssertTrue(plain.horizontal.isEmpty && plain.vertical.isEmpty)
        let nowhere = DrawingPaperGeometry.linePositions(of: .squared, in: CGRect(x: 0, y: 0, width: Double.infinity, height: 10))
        XCTAssertTrue(nowhere.horizontal.isEmpty && nowhere.vertical.isEmpty)
        XCTAssertEqual(DrawingPaperGeometry.linePositions(of: .squared, in: CGRect(x: -30, y: -30, width: 31, height: 31)).horizontal, [-24, 0])
    }

    func testSavedDrawingStartsOnLinesOfItsPaper() {
        let bounds = CGRect(x: 0, y: 130, width: 760, height: 200)
        let squared = DrawingCanvasGeometry.startingOnPaperLines(bounds, of: .squared)
        XCTAssertEqual(squared.minY, 120, "Grown upward to the line at or above it.")
        XCTAssertEqual(squared.maxY, bounds.maxY)
        XCTAssertEqual(squared.minX, 0)
        let ruled = DrawingCanvasGeometry.startingOnPaperLines(CGRect(x: -10, y: 130, width: 770, height: 200), of: .ruled)
        XCTAssertEqual(ruled.minY, 128)
        XCTAssertEqual(ruled.minX, -10, "Ruled paper has no vertical lines to start on.")
        XCTAssertEqual(DrawingCanvasGeometry.startingOnPaperLines(bounds, of: .plain), bounds)
    }

    func testContentBoundsCoverInkAndPlacedPictures() {
        let ink = CGRect(x: 100, y: 100, width: 50, height: 50), picture = CGRect(x: 300, y: 400, width: 200, height: 100)
        XCTAssertEqual(DrawingCanvasGeometry.contentBounds(inkBounds: ink, pictureFrames: [picture]), ink.union(picture))
        XCTAssertEqual(DrawingCanvasGeometry.contentBounds(inkBounds: nil, pictureFrames: [picture]), picture)
        XCTAssertNil(DrawingCanvasGeometry.contentBounds(inkBounds: nil, pictureFrames: []))
        XCTAssertEqual(DrawingCanvasGeometry.contentBounds(inkBounds: .null, pictureFrames: [picture]), picture, "A drawing without strokes has null bounds.")
    }

    func testPayloadWithPicturesOrVisiblePaperIsVersionThreeAndAGuideStaysCompatible() throws {
        let strokes = Data([1, 2, 3])
        let first = DrawingBackgroundImage(imageData: Data([7, 7]), frame: CGRect(x: 10, y: 20, width: 100, height: 50))
        let second = DrawingBackgroundImage(imageData: Data([8]), frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        let visiblePaper = DrawingPaper(pattern: .squared, appearsInSavedDrawing: true)
        let withPictures = DrawingPayload(width: 760, height: 300, background: .white, strokes: strokes, pictures: [first, second], paper: visiblePaper)
        XCTAssertEqual(withPictures.version, 3)
        let decoded = try XCTUnwrap(DrawingPayload.decodeIfValid(try withPictures.encoded()))
        XCTAssertEqual(decoded, withPictures)
        XCTAssertEqual(decoded.pictures, [first, second], "Pictures keep their order, the lowest first.")
        XCTAssertEqual(decoded.paper, visiblePaper)
        XCTAssertEqual(withPictures.replacingVisibleContentDigest(Data([9])).pictures, [first, second], "Writing the digest keeps the pictures.")
        XCTAssertEqual(withPictures.replacingVisibleContentDigest(Data([9])).paper, visiblePaper)

        // Paper that the saved drawing shows is version 3 on its own: an older build would
        // save the ink again without it.
        XCTAssertEqual(DrawingPayload(width: 760, height: 300, background: .white, strokes: strokes, paper: visiblePaper).version, 3)

        // A guide changes nothing a reader sees, so an older build may open the drawing.
        let guide = DrawingPaper(pattern: .dotted, appearsInSavedDrawing: false)
        let withGuide = DrawingPayload(width: 760, height: 300, background: .white, strokes: strokes, paper: guide)
        XCTAssertEqual(withGuide.version, 1)
        XCTAssertEqual(try XCTUnwrap(DrawingPayload.decodeIfValid(try withGuide.encoded())).paper, guide)
        XCTAssertEqual(DrawingPayload(width: 760, height: 300, background: .white, strokes: strokes).paper, .plain)
        // Plain paper is never "shown".
        XCTAssertEqual(DrawingPayload(width: 760, height: 300, background: .white, strokes: strokes,
                                      paper: DrawingPaper(pattern: .plain, appearsInSavedDrawing: true)).version, 1)
    }

    func testPayloadRejectsTooManyOrTooLargePictures() {
        let strokes = Data([1])
        let small = DrawingBackgroundImage(imageData: Data([1]), frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let tooMany = Array(repeating: small, count: DrawingLimits.maximumPictureCount + 1)
        XCTAssertFalse(DrawingPayload(width: 100, height: 100, background: .white, strokes: strokes, pictures: tooMany).hasValidGeometry)
        XCTAssertTrue(DrawingPayload(width: 100, height: 100, background: .white, strokes: strokes,
                                     pictures: Array(repeating: small, count: DrawingLimits.maximumPictureCount)).hasValidGeometry)
        // The pictures of one drawing share one budget.
        let half = DrawingBackgroundImage(imageData: Data(count: DrawingLimits.maximumBackgroundImageBytes / 2 + 1), frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertTrue(DrawingPayload(width: 100, height: 100, background: .white, strokes: strokes, pictures: [half]).hasValidGeometry)
        XCTAssertFalse(DrawingPayload(width: 100, height: 100, background: .white, strokes: strokes, pictures: [half, half]).hasValidGeometry)
        XCTAssertFalse(DrawingPayload(width: 100, height: 100, background: .white, strokes: strokes, backgroundImage: half, pictures: [half]).hasValidGeometry)
        let unplaced = DrawingBackgroundImage(imageData: Data([1]), frame: CGRect(x: 0, y: 0, width: 0, height: 10))
        XCTAssertThrowsError(try DrawingPayload(width: 100, height: 100, background: .white, strokes: strokes, pictures: [unplaced]).encoded())
    }
}
