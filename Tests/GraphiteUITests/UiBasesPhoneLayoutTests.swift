import XCTest
@testable import GraphiteUI

/// How the table, list, Kanban and map views fit a phone. An iPhone 17 Pro is 402 points
/// wide; a base inside a note there is about 336.
final class UiBasesPhoneLayoutTests: XCTestCase {
    // MARK: Table

    func testAPhoneGivesTheFileNameColumnALittleOverHalfTheTable() {
        XCTAssertEqual(BaseTableLayout.defaultFileNameColumnWidth(viewWidth: 402), 221)
        XCTAssertEqual(BaseTableLayout.defaultFileNameColumnWidth(viewWidth: 336), 184)
    }

    func testAWideOrUnmeasuredTableKeepsTheFileNameColumnAtItsDefault() {
        for viewWidth: CGFloat? in [nil, 600, 1_200, .infinity, 0, -10] {
            XCTAssertEqual(BaseTableLayout.defaultFileNameColumnWidth(viewWidth: viewWidth), 240, "at \(String(describing: viewWidth))")
        }
    }

    func testTheFileNameColumnIsNeverNarrowerThanObsidiansMinimum() {
        XCTAssertEqual(BaseTableLayout.defaultFileNameColumnWidth(viewWidth: 60), 40)
    }

    func testTheFirstColumnIsPinnedWhenItLeavesMostOfTheViewToScroll() {
        XCTAssertTrue(BaseTableLayout.pinsFirstColumn(firstColumnWidth: 221, viewWidth: 402))
        XCTAssertTrue(BaseTableLayout.pinsFirstColumn(firstColumnWidth: 240, viewWidth: 1_000))
        XCTAssertFalse(BaseTableLayout.pinsFirstColumn(firstColumnWidth: 240, viewWidth: 402), "A configured wide column would cover most of a phone.")
        XCTAssertFalse(BaseTableLayout.pinsFirstColumn(firstColumnWidth: 100, viewWidth: nil), "Nothing is pinned before the table is laid out.")
        XCTAssertFalse(BaseTableLayout.pinsFirstColumn(firstColumnWidth: 100, viewWidth: .infinity))
    }

    // MARK: List

    func testASeparatorEndingInASpaceStaysWithItsValueAndBreaksAtTheSpace() {
        assertSeparator(", ", attaches: ",", isFollowedBySpace: true)
        assertSeparator(" · ", attaches: " ·", isFollowedBySpace: true)
        assertSeparator("   ", attaches: "", isFollowedBySpace: true)
    }

    func testASeparatorWithoutATrailingSpaceJoinsValuesWithoutAGap() {
        assertSeparator("/", attaches: "/", isFollowedBySpace: false)
        assertSeparator("", attaches: "", isFollowedBySpace: false)
    }

    // MARK: Kanban

    func testAPhoneBoardShowsOneWholeColumnAndAStripOfTheNext() {
        // 402 − 12 margin − 10 gap − 28 of the next column.
        assertBoard(availableWidth: 402, columnWidth: 352, spacing: 10, margin: 12)
        XCTAssertEqual(BaseKanbanColumnMetrics(availableWidth: 336).columnWidth, 286)
    }

    func testNarrowBoardColumnsStayBetweenTheirLimits() {
        XCTAssertEqual(BaseKanbanColumnMetrics(availableWidth: 250).columnWidth, 200)
        XCTAssertEqual(BaseKanbanColumnMetrics(availableWidth: 599).columnWidth, 360)
    }

    func testAWideOrUnmeasuredBoardKeepsObsidiansColumns() {
        for availableWidth: CGFloat? in [nil, 600, 1_200, .infinity, 0] {
            assertBoard(availableWidth: availableWidth, columnWidth: 272, spacing: 12, margin: 16)
        }
    }

    // MARK: Map

    func testAMapInANoteOnAPhoneIsNoTallerThanItIsWide() {
        XCTAssertEqual(BaseEmbeddedHeight.mapHeight(configuredHeight: 520, availableWidth: 336), 336)
        XCTAssertEqual(BaseEmbeddedHeight.mapHeight(configuredHeight: 300, availableWidth: 336), 300, "A lower map keeps its height.")
        XCTAssertEqual(BaseEmbeddedHeight.mapHeight(configuredHeight: 520, availableWidth: 150), 200, "A very narrow note still shows a usable map.")
    }

    func testAMapInAWideOrUnmeasuredNoteKeepsItsConfiguredHeight() {
        for availableWidth: CGFloat? in [nil, 600, 700, .infinity, 0] {
            XCTAssertEqual(BaseEmbeddedHeight.mapHeight(configuredHeight: 520, availableWidth: availableWidth), 520, "at \(String(describing: availableWidth))")
        }
    }

    // MARK: Helpers

    private func assertSeparator(_ separator: String, attaches attachedText: String, isFollowedBySpace: Bool, line: UInt = #line) {
        let inlineSeparator = BaseListInlineSeparator(separator: separator)
        XCTAssertEqual(inlineSeparator.attachedText, attachedText, "“\(separator)”", line: line)
        XCTAssertEqual(inlineSeparator.isFollowedBySpace, isFollowedBySpace, "“\(separator)”", line: line)
    }

    private func assertBoard(availableWidth: CGFloat?, columnWidth: CGFloat, spacing: CGFloat, margin: CGFloat, line: UInt = #line) {
        let metrics = BaseKanbanColumnMetrics(availableWidth: availableWidth)
        let widthDescription = String(describing: availableWidth)
        XCTAssertEqual(metrics.columnWidth, columnWidth, "at \(widthDescription)", line: line)
        XCTAssertEqual(metrics.spacing, spacing, "at \(widthDescription)", line: line)
        XCTAssertEqual(metrics.margin, margin, "at \(widthDescription)", line: line)
    }
}
