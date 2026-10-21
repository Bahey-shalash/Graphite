import XCTest
import CoreGraphics
@testable import GraphiteCore

/// The order Read Aloud reads a page's text boxes in.
final class PDFTextBoxReadingOrderTests: XCTestCase {
    private func box(_ name: String, x: Double, top: Double) -> PDFTextBox {
        PDFTextBox(name: name, runs: [PDFTextRun(text: name, attributes: .plain)], origin: CGPoint(x: x, y: top), width: 50, height: 20)
    }

    func testBoxesAreReadFromTheTopDownAndLevelOnesFromLeftToRight() {
        let boxes = [box("low", x: 10, top: 300), box("right", x: 200, top: 700), box("left", x: 20, top: 703), box("top", x: 300, top: 760)]
        XCTAssertEqual(PDFTextBoxReadingOrder.sorted(boxes, pageQuarterTurns: 0).map(\.name), ["top", "left", "right", "low"])
    }

    func testOnAPageShownTurnedTheOrderIsAsThePageIsShown() {
        // Turned a quarter clockwise: the page's left edge is at the top of the screen.
        let boxes = [box("further right on the page", x: 400, top: 500), box("left on the page", x: 10, top: 500)]
        XCTAssertEqual(PDFTextBoxReadingOrder.sorted(boxes, pageQuarterTurns: 1).map(\.name), ["left on the page", "further right on the page"])
        XCTAssertEqual(PDFTextBoxReadingOrder.sorted(boxes, pageQuarterTurns: 3).map(\.name), ["further right on the page", "left on the page"])
    }
}
