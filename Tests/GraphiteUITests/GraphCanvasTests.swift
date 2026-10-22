import XCTest
@testable import GraphiteUI

/// What the graph's canvas draws around the open note.
@MainActor
final class GraphCanvasTests: XCTestCase {
    func testTheOpenNotesHaloCanBeFoundWhenItsNodeIsADot() {
        let farOut = GraphCanvas.haloRadii(ofNodeRadius: 2)
        XCTAssertGreaterThanOrEqual(farOut.ring, 9, "The ring keeps a finger tip's size when the node is a dot.")
        XCTAssertGreaterThan(farOut.glow, farOut.ring)
    }

    func testTheOpenNotesHaloSitsJustOutsideALargeNode() {
        let close = GraphCanvas.haloRadii(ofNodeRadius: 20)
        XCTAssertEqual(close.ring, 23)
        XCTAssertEqual(close.glow, 30)
    }
}
