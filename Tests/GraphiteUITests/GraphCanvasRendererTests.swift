import XCTest
@testable import GraphiteUI

/// What the graph's renderer draws around the open note.
@MainActor
final class GraphCanvasRendererTests: XCTestCase {
    func testTheOpenNotesHaloCanBeFoundWhenItsNodeIsADot() {
        let farOut = GraphCanvasRenderer.haloRadii(ofNodeRadius: 2)
        XCTAssertGreaterThanOrEqual(farOut.ring, 9, "The ring keeps a finger tip's size when the node is a dot.")
        XCTAssertGreaterThan(farOut.glow, farOut.ring)
    }

    func testTheOpenNotesHaloSitsJustOutsideALargeNode() {
        let close = GraphCanvasRenderer.haloRadii(ofNodeRadius: 20)
        XCTAssertEqual(close.ring, 23)
        XCTAssertEqual(close.glow, 30)
    }
}
