import XCTest
@testable import GraphiteUI

/// How many columns of cards a width holds, and the margins around them.
final class UiBasesCardGridTests: XCTestCase {
    func testAPhoneShowsTwoColumnsOfSmallerCards() {
        // An iPhone 17 Pro is 402 points wide; a base inside a note there is about 336.
        for width: CGFloat in [402, 336] {
            let metrics = BaseCardGridMetrics(availableWidth: width, preferredCardWidth: 220)
            XCTAssertEqual(metrics.columnCount, 2, "at \(width) points")
            XCTAssertTrue(metrics.isCompact)
            XCTAssertEqual(metrics.padding, 12)
        }
    }

    func testAWidthTooNarrowForTwoMinimumCardsShowsOne() {
        let metrics = BaseCardGridMetrics(availableWidth: 300, preferredCardWidth: 220)
        XCTAssertEqual(metrics.columnCount, 1)
    }

    func testAWideViewFitsAsManyCardsOfTheCardSizeAsItCan() {
        // 800 − 2 × 16 margin = 768; (768 + 16) / (220 + 16) = 3.3.
        let metrics = BaseCardGridMetrics(availableWidth: 800, preferredCardWidth: 220)
        XCTAssertEqual(metrics.columnCount, 3)
        XCTAssertFalse(metrics.isCompact)
        XCTAssertEqual(metrics.padding, 16)
    }

    func testUnusableWidthsAndCardSizesStillGiveOneColumnOrMore() {
        XCTAssertEqual(BaseCardGridMetrics(availableWidth: 0, preferredCardWidth: 220).columnCount, 1)
        XCTAssertEqual(BaseCardGridMetrics(availableWidth: .infinity, preferredCardWidth: 220).columnCount, 1)
        XCTAssertEqual(BaseCardGridMetrics(availableWidth: 800, preferredCardWidth: -12).columnCount, 14, "A card size under 40 counts as 40.")
        XCTAssertEqual(BaseCardGridMetrics(availableWidth: 800, preferredCardWidth: .nan).columnCount, 14)
    }
}
