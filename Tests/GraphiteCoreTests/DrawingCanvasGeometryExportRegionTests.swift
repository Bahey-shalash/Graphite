import XCTest
import CoreGraphics
@testable import GraphiteCore

/// The region a drawing is saved in, composed as `DrawingFileService.fileData` composes it:
/// the content around the ink and the placed pictures, the full canvas width, a margin, a
/// minimum height, then grown up and left onto the lines of the paper. Everything saved is
/// translated by the region's origin, so the file starts at 0,0.
final class DrawingCanvasGeometryExportRegionTests: XCTestCase {
    private let canvasWidth = 800.0

    private func exportRegion(ink: CGRect?, pictures: [CGRect] = [], backgroundImageFrame: CGRect? = nil, paper: DrawingPaper = .plain) -> CGRect {
        let contentBounds = DrawingCanvasGeometry.contentBounds(inkBounds: ink, pictureFrames: pictures)
        let unaligned = backgroundImageFrame.map { frame in DrawingCanvasGeometry.exportBounds(inkBounds: contentBounds, backgroundImageFrame: frame) }
            ?? DrawingCanvasGeometry.exportBounds(inkBounds: contentBounds, canvasWidth: canvasWidth)
        return DrawingCanvasGeometry.startingOnPaperLines(unaligned, of: paper.pattern, spacing: paper.spacing)
    }

    func testTheMarginIs24PointsAndTheMinimumHeightIs96() {
        XCTAssertEqual(DrawingLimits.exportMargin, 24)
        XCTAssertEqual(DrawingLimits.minimumExportHeight, 96)
    }

    func testAnEmptyDrawingIsTheFullWidthAndTheMinimumHeightAtTheOrigin() {
        XCTAssertEqual(exportRegion(ink: nil), CGRect(x: 0, y: 0, width: 800, height: 96))
        XCTAssertEqual(exportRegion(ink: .null), CGRect(x: 0, y: 0, width: 800, height: 96))
    }

    func testInkIsSavedFullWidthWithA24PointMarginAboveAndBelow() {
        XCTAssertEqual(exportRegion(ink: CGRect(x: 100, y: 200, width: 300, height: 50)), CGRect(x: 0, y: 176, width: 800, height: 98))
    }

    func testAShortStrokeIsSavedAtLeast96PointsTall() {
        XCTAssertEqual(exportRegion(ink: CGRect(x: 100, y: 200, width: 10, height: 10)), CGRect(x: 0, y: 176, width: 800, height: 96))
    }

    func testInkBeyondTheCanvasWidthWidensTheRegionWithAMarginAndIsNeverCropped() {
        XCTAssertEqual(exportRegion(ink: CGRect(x: 900, y: 100, width: 100, height: 50)), CGRect(x: 0, y: 76, width: 1024, height: 98))
        XCTAssertEqual(exportRegion(ink: CGRect(x: -100, y: 100, width: 50, height: 50)), CGRect(x: -124, y: 76, width: 924, height: 98))
    }

    func testTheRegionIsWholePoints() {
        XCTAssertEqual(exportRegion(ink: CGRect(x: 100.4, y: 200.6, width: 10, height: 10)), CGRect(x: 0, y: 176, width: 800, height: 97))
    }

    func testPlacedPicturesCountLikeInk() {
        let picture = CGRect(x: 50, y: 300, width: 200, height: 100)
        XCTAssertEqual(exportRegion(ink: nil, pictures: [picture]), CGRect(x: 0, y: 276, width: 800, height: 148))
        XCTAssertEqual(exportRegion(ink: CGRect(x: 100, y: 100, width: 50, height: 50), pictures: [picture]), CGRect(x: 0, y: 76, width: 800, height: 348))
    }

    func testADrawingOnAnImageIsExactlyTheImageUnlessInkLeavesIt() {
        let imageFrame = CGRect(x: 10, y: 20, width: 300, height: 200)
        XCTAssertEqual(exportRegion(ink: CGRect(x: 50, y: 60, width: 100, height: 40), backgroundImageFrame: imageFrame), imageFrame)
        XCTAssertEqual(exportRegion(ink: nil, backgroundImageFrame: imageFrame), imageFrame)
        XCTAssertEqual(exportRegion(ink: CGRect(x: 250, y: 100, width: 200, height: 50), backgroundImageFrame: imageFrame), CGRect(x: 10, y: 20, width: 464, height: 200),
                       "Ink that leaves the picture widens the region by the margin.")
    }

    func testTheRegionGrowsUpAndLeftOntoSquaredAndDottedPaperLines() {
        for pattern in [DrawingPaperPattern.squared, .dotted] {
            let paper = DrawingPaper(pattern: pattern, appearsInSavedDrawing: true)
            // Squares are 24 points: y 176 grows to 168, and the region keeps its far edges.
            XCTAssertEqual(exportRegion(ink: CGRect(x: 100, y: 200, width: 300, height: 50), paper: paper), CGRect(x: 0, y: 168, width: 800, height: 106), "\(pattern)")
            XCTAssertEqual(exportRegion(ink: CGRect(x: 900, y: 200, width: 100, height: 50), pictures: [], paper: paper).minX, 0)
            XCTAssertEqual(exportRegion(ink: CGRect(x: -100, y: 200, width: 50, height: 50), paper: paper).minX, -144, "-124 grows to the line at -144.")
        }
    }

    func testTheRegionGrowsOnlyUpOntoRuledLinesAndByTheChosenSpacing() {
        let ruled = DrawingPaper(pattern: .ruled, appearsInSavedDrawing: true)
        XCTAssertEqual(exportRegion(ink: CGRect(x: -100, y: 200, width: 50, height: 50), paper: ruled), CGRect(x: -124, y: 160, width: 924, height: 114),
                       "Ruled lines are 32 points apart: y 176 grows to 160; x is left as it is.")
        let narrow = DrawingPaper(pattern: .ruled, appearsInSavedDrawing: true, spacing: .narrow)
        let wide = DrawingPaper(pattern: .ruled, appearsInSavedDrawing: true, spacing: .wide)
        XCTAssertEqual(exportRegion(ink: CGRect(x: 100, y: 200, width: 300, height: 50), paper: narrow).minY, 168, "24 points apart.")
        XCTAssertEqual(exportRegion(ink: CGRect(x: 100, y: 200, width: 300, height: 50), paper: wide).minY, 144, "48 points apart.")
    }

    func testPicturesTranslateSoTheRegionStartsAtTheOrigin() {
        let region = exportRegion(ink: CGRect(x: 100, y: 200, width: 300, height: 50))
        let picture = DrawingBackgroundImage(imageData: Data([1, 2, 3]), frame: CGRect(x: 50, y: 300, width: 200, height: 100), rotationRadians: .pi / 4)
        let moved = picture.offsetBy(dx: -region.minX, dy: -region.minY)
        XCTAssertEqual(moved.frame, CGRect(x: 50, y: 124, width: 200, height: 100))
        XCTAssertEqual(moved.imageData, picture.imageData)
        XCTAssertEqual(moved.rotationRadians, picture.rotationRadians)
        XCTAssertEqual(region.offsetBy(dx: -region.minX, dy: -region.minY).origin, .zero)
    }
}
