import XCTest
@testable import GraphiteCore

/// Where stacked tabs' panes go as the row scrolls: Obsidian's sliding panes.
final class StackedPaneGeometryTests: XCTestCase {
    /// Four panes of 40-point spines and 700-point content in a 1,000-point container.
    private let geometry = StackedPaneGeometry(paneCount: 4, containerWidth: 1_000, spineWidth: 40, preferredContentWidth: 700, minimumContentWidth: 300)

    func testAPaneIsAsWideAsItsPreferredContentWhileEverySpineFits() {
        XCTAssertEqual(geometry.paneWidth, 740)
        XCTAssertEqual(geometry.rowWidth, 2_960)
        let narrow = StackedPaneGeometry(paneCount: 4, containerWidth: 600, spineWidth: 40, preferredContentWidth: 700, minimumContentWidth: 300)
        XCTAssertEqual(narrow.contentWidth, 440, "The content leaves room for every pane's spine.")
        let crowded = StackedPaneGeometry(paneCount: 20, containerWidth: 600, spineWidth: 40, preferredContentWidth: 700, minimumContentWidth: 300)
        XCTAssertEqual(crowded.contentWidth, 300, "It never gets narrower than the minimum; panes overlap instead.")
    }

    func testPanesWaitAtTheTrailingEdgeAndStopAtTheLeadingEdgeWithTheirSpineShowing() {
        // Unscrolled: the first pane whole, the second partly, the last two waiting as spines.
        XCTAssertEqual(geometry.displayedLeadingEdge(ofPane: 0, scrollOffset: 0), 0)
        XCTAssertEqual(geometry.displayedLeadingEdge(ofPane: 1, scrollOffset: 0), 740)
        XCTAssertEqual(geometry.displayedLeadingEdge(ofPane: 2, scrollOffset: 0), 920, "Two spines before the trailing edge.")
        XCTAssertEqual(geometry.displayedLeadingEdge(ofPane: 3, scrollOffset: 0), 960)
        XCTAssertEqual(geometry.visibleContentWidth(ofPane: 1, scrollOffset: 0), 140, "Covered from the third pane's spine on.")
        XCTAssertEqual(geometry.visibleContentWidth(ofPane: 2, scrollOffset: 0), 0, "Only its spine shows.")
        // Scrolled to the end: the first two stopped at the leading edge, the last whole.
        let end = geometry.maximumScrollOffset
        XCTAssertEqual(end, 1_960)
        XCTAssertEqual(geometry.displayedLeadingEdge(ofPane: 0, scrollOffset: end), 0)
        XCTAssertEqual(geometry.displayedLeadingEdge(ofPane: 1, scrollOffset: end), 40)
        XCTAssertEqual(geometry.displayedLeadingEdge(ofPane: 3, scrollOffset: end), 260)
        XCTAssertEqual(geometry.visibleContentWidth(ofPane: 0, scrollOffset: end), 0, "The panes after it cover all but its spine.")
        XCTAssertEqual(geometry.visibleContentWidth(ofPane: 3, scrollOffset: end), 700)
    }

    func testShowingAPaneScrollsAsLittleAsItNeeds() {
        XCTAssertEqual(geometry.scrollOffset(showingPane: 0, from: 0), 0, "Already whole.")
        // The third pane whole needs its leading edge past two spines and its trailing edge
        // before the last pane's spine.
        let offset = geometry.scrollOffset(showingPane: 2, from: 0)
        XCTAssertEqual(offset, 1_260)
        XCTAssertEqual(geometry.visibleContentWidth(ofPane: 2, scrollOffset: offset), 700)
        XCTAssertEqual(geometry.displayedLeadingEdge(ofPane: 2, scrollOffset: offset), 220)
        XCTAssertEqual(geometry.scrollOffset(showingPane: 2, from: 1_400), 1_400, "Any offset that already shows it whole stays.")
        XCTAssertEqual(geometry.scrollOffset(showingPane: 0, from: 1_960), 0)
    }

    func testThePanePointedAtIsTheOneDrawnOnTop() {
        XCTAssertEqual(geometry.pane(at: 10, scrollOffset: 0), 0)
        XCTAssertEqual(geometry.pane(at: 930, scrollOffset: 0), 2, "The third pane's spine is drawn over the second pane.")
        XCTAssertEqual(geometry.pane(at: 970, scrollOffset: 0), 3)
        XCTAssertEqual(geometry.pane(at: 20, scrollOffset: 1_960), 0)
        XCTAssertEqual(geometry.pane(at: 50, scrollOffset: 1_960), 1)
        XCTAssertNil(geometry.pane(at: 1_000, scrollOffset: 0))
    }

    func testPanesThatAllFitNeverStick() {
        let roomy = StackedPaneGeometry(paneCount: 2, containerWidth: 2_000, spineWidth: 40, preferredContentWidth: 700, minimumContentWidth: 300)
        XCTAssertEqual(roomy.maximumScrollOffset, 0)
        XCTAssertEqual(roomy.displayedLeadingEdge(ofPane: 1, scrollOffset: 0), 740)
        XCTAssertEqual(roomy.visibleContentWidth(ofPane: 0, scrollOffset: 0), 700)
    }
}
