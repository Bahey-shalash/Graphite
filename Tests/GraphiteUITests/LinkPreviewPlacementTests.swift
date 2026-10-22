import CoreGraphics
import XCTest
@testable import GraphiteUI

/// Where a link's card goes: below the link when it fits, otherwise on the side with more
/// room, within the window's margins, and cut to the room there is.
final class LinkPreviewPlacementTests: XCTestCase {
    private let window = CGSize(width: 1000, height: 800)

    func testACardThatFitsBelowItsLinkGoesBelowItAtTheLinksLeftEdge() {
        let frame = LinkPreviewPlacement.frame(beside: CGRect(x: 200, y: 100, width: 60, height: 20), naturalHeight: 250, in: window)
        XCTAssertEqual(frame, CGRect(x: 200, y: 126, width: 420, height: 250))
    }

    func testACardGoesAboveALinkNearTheBottomWhenThereIsMoreRoomThere() {
        let frame = LinkPreviewPlacement.frame(beside: CGRect(x: 200, y: 700, width: 60, height: 20), naturalHeight: 300, in: window)
        XCTAssertEqual(frame.maxY, 694, "The card ends just above the link.")
        XCTAssertEqual(frame.height, 300)
    }

    func testACardStaysInsideTheWindowsMarginsAndIsCutToTheRoomThereIs() {
        let nearTheRightEdge = LinkPreviewPlacement.frame(beside: CGRect(x: 900, y: 100, width: 60, height: 20), naturalHeight: 100, in: window)
        XCTAssertEqual(nearTheRightEdge.maxX, 988, "12 points from the right edge.")
        let tall = LinkPreviewPlacement.frame(beside: CGRect(x: 10, y: 100, width: 60, height: 20), naturalHeight: 2000, in: window)
        XCTAssertEqual(tall.minX, 12)
        XCTAssertEqual(tall.height, LinkPreviewPlacement.maximumHeightPoints, "No taller than a card may be.")
        let narrowAndShort = LinkPreviewPlacement.frame(beside: CGRect(x: 10, y: 100, width: 60, height: 20), naturalHeight: 400, in: CGSize(width: 300, height: 300))
        XCTAssertEqual(narrowAndShort.width, 276)
        XCTAssertEqual(narrowAndShort.height, 162, "Cut to the room below the link, the side with more room.")
    }
}
