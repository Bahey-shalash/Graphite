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

    func testPaperColorsAndAShownPatternsStyleAreVersionFourAndAGuidesStyleIsNot() throws {
        let strokes = Data([1, 2, 3])
        // A tinted paper is something a version 3 build would not show.
        let ivory = DrawingPayload(width: 760, height: 300, background: .ivory, strokes: strokes)
        XCTAssertEqual(ivory.version, 4)
        XCTAssertEqual(try XCTUnwrap(DrawingPayload.decodeIfValid(try ivory.encoded())).background, .ivory)
        XCTAssertEqual(DrawingPayload(width: 760, height: 300, background: .transparent, strokes: strokes).version, 1)

        // So is the style of a pattern the saved drawing shows.
        let styled = DrawingPaper(pattern: .ruled, appearsInSavedDrawing: true, spacing: .wide, lineColor: .blue, lineStrength: .strong)
        let withStyledPaper = DrawingPayload(width: 760, height: 300, background: .white, strokes: strokes, paper: styled)
        XCTAssertEqual(withStyledPaper.version, 4)
        let decoded = try XCTUnwrap(DrawingPayload.decodeIfValid(try withStyledPaper.encoded()))
        XCTAssertEqual(decoded.paper, styled)
        XCTAssertEqual(decoded.replacingVisibleContentDigest(Data([9])).paper, styled)

        // A guide's style is kept, but raises nothing: a reader sees none of it.
        let styledGuide = DrawingPaper(pattern: .dotted, appearsInSavedDrawing: false, spacing: .narrow, lineColor: .green, lineStrength: .light)
        let withGuide = DrawingPayload(width: 760, height: 300, background: .white, strokes: strokes, paper: styledGuide)
        XCTAssertEqual(withGuide.version, 1)
        XCTAssertEqual(try XCTUnwrap(DrawingPayload.decodeIfValid(try withGuide.encoded())).paper, styledGuide)
        // The standard style of a shown pattern stays version 3, as before there were styles.
        XCTAssertEqual(DrawingPayload(width: 760, height: 300, background: .white, strokes: strokes,
                                      paper: DrawingPaper(pattern: .squared, appearsInSavedDrawing: true)).version, 3)
        // Plain paper keeps no style.
        let plainWithStyle = DrawingPaper(pattern: .plain, appearsInSavedDrawing: false, spacing: .wide)
        XCTAssertEqual(try XCTUnwrap(DrawingPayload.decodeIfValid(try DrawingPayload(width: 760, height: 300, background: .white,
                                                                                         strokes: strokes, paper: plainWithStyle).encoded())).paper, .plain)
    }

    func testSpacingMovesThePatternsLinesAndWhereASavedDrawingStarts() {
        XCTAssertEqual(DrawingPaperGeometry.spacing(of: .squared, spacing: .narrow), 18)
        XCTAssertEqual(DrawingPaperGeometry.spacing(of: .ruled, spacing: .wide), 48)
        XCTAssertNil(DrawingPaperGeometry.spacing(of: .plain, spacing: .wide))
        let wideLines = DrawingPaperGeometry.linePositions(of: .squared, spacing: .wide, in: CGRect(x: 0, y: 0, width: 100, height: 80))
        XCTAssertEqual(wideLines.horizontal, [0, 36, 72])
        XCTAssertEqual(wideLines.vertical, [0, 36, 72])
        let start = DrawingCanvasGeometry.startingOnPaperLines(CGRect(x: 50, y: 50, width: 10, height: 10), of: .squared, spacing: .wide)
        XCTAssertEqual(start.minX, 36)
        XCTAssertEqual(start.minY, 36)
        XCTAssertEqual(start.maxX, 60)
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

    // MARK: Turned pictures

    func testAnglesAreKeptWithinOneTurnAndSnapToQuarterTurnsNearby() {
        XCTAssertEqual(PictureRotation.normalized(5 * .pi / 2), .pi / 2, accuracy: 1e-12)
        XCTAssertEqual(PictureRotation.normalized(-.pi), .pi, accuracy: 1e-12, "A half turn is π, never -π.")
        XCTAssertEqual(PictureRotation.normalized(-5 * .pi / 2), -.pi / 2, accuracy: 1e-12)
        XCTAssertEqual(PictureRotation.normalized(.nan), 0)
        let degree = Double.pi / 180
        XCTAssertEqual(PictureRotation.snapped(3 * degree), 0)
        XCTAssertEqual(PictureRotation.snapped(88 * degree), .pi / 2, accuracy: 1e-12)
        XCTAssertEqual(PictureRotation.snapped(-176 * degree), .pi, accuracy: 1e-12)
        XCTAssertEqual(PictureRotation.snapped(10 * degree), 10 * degree, accuracy: 1e-12, "Farther from a quarter turn, the angle stays.")
        XCTAssertTrue(PictureRotation.isNearQuarterTurn(-268 * degree))
        XCTAssertFalse(PictureRotation.isNearQuarterTurn(45 * degree))
    }

    func testATurnedPictureCoversItsFrameTurnedAboutItsMiddle() {
        // 100 by 40 around (150, 120), turned a quarter clockwise where y points down.
        let picture = DrawingBackgroundImage(imageData: Data([1]), frame: CGRect(x: 100, y: 100, width: 100, height: 40), rotationRadians: .pi / 2)
        XCTAssertTrue(picture.isTurned)
        let box = picture.boundingFrame
        XCTAssertEqual(box.minX, 130, accuracy: 1e-9)
        XCTAssertEqual(box.minY, 70, accuracy: 1e-9)
        XCTAssertEqual(box.width, 40, accuracy: 1e-9)
        XCTAssertEqual(box.height, 100, accuracy: 1e-9)
        XCTAssertTrue(picture.contains(CGPoint(x: 150, y: 80)), "The turned picture reaches up there.")
        XCTAssertFalse(picture.contains(CGPoint(x: 105, y: 120)), "Its end before it turned is empty.")
        // A clockwise quarter turn where y points down takes the right side to the bottom.
        let turnedRightEnd = PictureRotation.point(CGPoint(x: 200, y: 120), turnedBy: .pi / 2, about: CGPoint(x: 150, y: 120))
        XCTAssertEqual(turnedRightEnd.x, 150, accuracy: 1e-9)
        XCTAssertEqual(turnedRightEnd.y, 170, accuracy: 1e-9)
        // Upright pictures keep their frame exactly.
        let upright = DrawingBackgroundImage(imageData: Data([1]), frame: CGRect(x: 10.5, y: 20.25, width: 30, height: 40))
        XCTAssertFalse(upright.isTurned)
        XCTAssertEqual(upright.boundingFrame, upright.frame)
        XCTAssertEqual(upright.offsetBy(dx: 5, dy: 5).rotationRadians, 0)
        XCTAssertEqual(picture.offsetBy(dx: 5, dy: -5).rotationRadians, .pi / 2, accuracy: 1e-12, "Moving a picture keeps its angle.")
    }

    func testAPartOfATurnedPictureIsPlacedWhereItWasShown() {
        // The right half of a 100 by 40 picture around (150, 120) turned a quarter clockwise:
        // that half was shown below the middle, so on its own its middle is (150, 145).
        let rightHalf = PictureRotation.rectangle(CGRect(x: 150, y: 100, width: 50, height: 40), withMiddleTurnedBy: .pi / 2, about: CGPoint(x: 150, y: 120))
        XCTAssertEqual(rightHalf.midX, 150, accuracy: 1e-9)
        XCTAssertEqual(rightHalf.midY, 145, accuracy: 1e-9)
        XCTAssertEqual(rightHalf.size, CGSize(width: 50, height: 40))
    }

    func testPayloadWithATurnedPictureIsVersionFiveAndKeepsEveryAngle() throws {
        let strokes = Data([1, 2, 3])
        let turned = DrawingBackgroundImage(imageData: Data([7, 7]), frame: CGRect(x: 10, y: 20, width: 100, height: 50), rotationRadians: 0.3)
        let upright = DrawingBackgroundImage(imageData: Data([8]), frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        let payload = DrawingPayload(width: 760, height: 300, background: .ivory, strokes: strokes, pictures: [upright, turned])
        XCTAssertEqual(payload.version, 5, "Turned pictures need a build that turns them, whatever else the drawing has.")
        let decoded = try XCTUnwrap(DrawingPayload.decodeIfValid(try payload.encoded()))
        XCTAssertEqual(decoded.pictures, [upright, turned])
        XCTAssertEqual(decoded.background, .ivory)
        XCTAssertEqual(payload.replacingVisibleContentDigest(Data([9])).pictures, [upright, turned], "Writing the digest keeps the angles.")
        // Upright pictures alone stay version 3, which earlier builds read.
        XCTAssertEqual(DrawingPayload(width: 760, height: 300, background: .white, strokes: strokes, pictures: [upright]).version, 3)
        // The most pictures a drawing holds, every one turned, still fit the record's bound.
        let manyTurned = (0..<DrawingLimits.maximumPictureCount).map { pictureIndex in
            DrawingBackgroundImage(imageData: Data([UInt8(pictureIndex)]), frame: CGRect(x: Double(pictureIndex), y: 1.5 * Double(pictureIndex), width: 10 + Double(pictureIndex), height: 7),
                                   rotationRadians: 0.01 * Double(pictureIndex + 1))
        }
        let full = DrawingPayload(width: 760, height: 300, background: .white, strokes: strokes,
                                  backgroundImage: DrawingBackgroundImage(imageData: Data([99]), frame: CGRect(x: 0, y: 0, width: 760, height: 300)), pictures: manyTurned)
        XCTAssertEqual(try XCTUnwrap(DrawingPayload.decodeIfValid(try full.encoded())).pictures, manyTurned)
    }

    func testPayloadRefusesAnglesThatDoNotMatchItsPicturesOrItsVersion() throws {
        func payload(_ fields: [String: Any]) throws -> Data {
            var record: [String: Any] = ["version": 5, "width": 760.0, "height": 300.0, "background": "white", "strokes": Data([1]), "pixelDigest": Data(),
                                         "pictures": [Data([7])], "pictureFrames": [[[10.0, 20.0], [100.0, 50.0]]], "pictureRotations": [0.3]]
            for (key, value) in fields { record[key] = value }
            return try PropertyListSerialization.data(fromPropertyList: record, format: .binary, options: 0)
        }
        XCTAssertEqual(DrawingPayload.decodeIfValid(try payload([:]))?.pictures.first?.rotationRadians ?? 0, 0.3, accuracy: 1e-12)
        XCTAssertNil(DrawingPayload.decodeIfValid(try payload(["pictureRotations": [0.3, 0.4]])), "One angle for each picture.")
        XCTAssertNil(DrawingPayload.decodeIfValid(try payload(["pictureRotations": [0.0]])), "Angles are written only for a turned picture.")
        XCTAssertNil(DrawingPayload.decodeIfValid(try payload(["pictureRotations": [Double.infinity]])))
        XCTAssertNil(DrawingPayload.decodeIfValid(try payload(["version": 3])), "An earlier version has no angles.")
        XCTAssertNil(DrawingPayload.decodeIfValid(try payload(["version": 6])), "A later version is an ordinary image to this build.")
    }
}
