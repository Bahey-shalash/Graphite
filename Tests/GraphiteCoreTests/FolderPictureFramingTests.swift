import XCTest
@testable import GraphiteCore

final class FolderPictureFramingTests: XCTestCase {
    func testFillingCropsTheLongerSideAndCentres() {
        let rect = FolderPictureFraming.filling.drawingRect(pictureSize: CGSize(width: 200, height: 100), frameSize: CGSize(width: 50, height: 50))
        XCTAssertEqual(rect, CGRect(x: -25, y: 0, width: 100, height: 50))
    }

    func testZoomAndOffsetAreInFrameWidths() {
        let framing = FolderPictureFraming(zoom: 2, horizontalOffset: 0.1, verticalOffset: -0.2)
        let rect = framing.drawingRect(pictureSize: CGSize(width: 100, height: 100), frameSize: CGSize(width: 100, height: 100))
        XCTAssertEqual(rect, CGRect(x: -40, y: -70, width: 200, height: 200))
    }

    func testZoomIsBounded() {
        XCTAssertEqual(FolderPictureFraming(zoom: 50, horizontalOffset: 0, verticalOffset: 0).zoom, FolderPictureFraming.maximumZoom)
        XCTAssertEqual(FolderPictureFraming(zoom: 0, horizontalOffset: 0, verticalOffset: 0).zoom, FolderPictureFraming.minimumZoom)
        XCTAssertEqual(FolderPictureFraming.filling.drawingRect(pictureSize: .zero, frameSize: CGSize(width: 10, height: 10)), .zero)
    }

    func testAWideFrameFillsByItsLongerScale() {
        let rect = FolderPictureFraming.filling.drawingRect(pictureSize: CGSize(width: 100, height: 100), frameSize: CGSize(width: 200, height: 50))
        XCTAssertEqual(rect, CGRect(x: 0, y: -75, width: 200, height: 200))
    }

    func testADragMovesByFrameSizesAndStopsAtTheLimit() {
        let moved = FolderPictureFraming.filling.moved(by: CGSize(width: 50, height: -25), frameSize: CGSize(width: 100, height: 50))
        XCTAssertEqual(moved.horizontalOffset, 0.5)
        XCTAssertEqual(moved.verticalOffset, -0.5)
        XCTAssertEqual(FolderPictureFraming.filling.moved(by: CGSize(width: 1_000, height: 0), frameSize: CGSize(width: 100, height: 100)).horizontalOffset,
                       FolderPictureFraming.maximumOffset)
    }
}
