#if canImport(UIKit)
import XCTest
import GraphiteCore
@testable import GraphiteUI

/// A picture placed on a drawing is no wider than 60 % of the canvas and no wider than the
/// width it asked for.
@MainActor
final class DrawingCanvasControllerNewPictureWidthTests: XCTestCase {
    private func placedWidth(preferredWidth: Double?, pictureWidth: Double = 900, canvasWidth: Double = 1_000) throws -> Double {
        let controller = DrawingCanvasController()
        controller.canvasWidth = canvasWidth
        let picture = DrawingBackgroundImage(imageData: Data([0]), frame: CGRect(x: 0, y: 0, width: pictureWidth, height: pictureWidth / 2))
        try controller.addPicture(picture, preferredWidth: preferredWidth)
        return try XCTUnwrap(controller.pictures.last).picture.frame.width
    }

    func testAPictureIsNeverWiderThanSixtyPercentOfTheCanvas() throws {
        XCTAssertEqual(try placedWidth(preferredWidth: nil), 600)
        XCTAssertEqual(try placedWidth(preferredWidth: 700), 600, "A larger preferred width is still kept to 60 %.")
        XCTAssertEqual(try placedWidth(preferredWidth: nil, canvasWidth: 500), 300)
    }

    func testAPictureAsksForNoMoreThanItsPreferredWidthOrItsOwnWidth() throws {
        XCTAssertEqual(try placedWidth(preferredWidth: 250), 250)
        XCTAssertEqual(try placedWidth(preferredWidth: nil, pictureWidth: 200), 200, "A picture narrower than the limit keeps its width.")
    }
}
#endif
