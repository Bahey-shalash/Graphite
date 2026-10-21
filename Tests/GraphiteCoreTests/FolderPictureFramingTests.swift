import XCTest
@testable import GraphiteCore

final class FolderPictureFramingTests: XCTestCase {
    func testFillingCropsTheLongerSideAndCentres() {
        let rect = FolderPictureFraming.filling.drawingRect(pictureSize: CGSize(width: 200, height: 100), frameSide: 50)
        XCTAssertEqual(rect, CGRect(x: -25, y: 0, width: 100, height: 50))
    }

    func testZoomAndOffsetAreInFrameWidths() {
        let framing = FolderPictureFraming(zoom: 2, horizontalOffset: 0.1, verticalOffset: -0.2)
        let rect = framing.drawingRect(pictureSize: CGSize(width: 100, height: 100), frameSide: 100)
        XCTAssertEqual(rect, CGRect(x: -40, y: -70, width: 200, height: 200))
    }

    func testZoomIsBounded() {
        XCTAssertEqual(FolderPictureFraming(zoom: 50, horizontalOffset: 0, verticalOffset: 0).zoom, FolderPictureFraming.maximumZoom)
        XCTAssertEqual(FolderPictureFraming(zoom: 0, horizontalOffset: 0, verticalOffset: 0).zoom, FolderPictureFraming.minimumZoom)
        XCTAssertEqual(FolderPictureFraming.filling.drawingRect(pictureSize: .zero, frameSide: 10), .zero)
    }
}
