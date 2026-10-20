import XCTest
@testable import GraphiteCore

/// An embed's `|400` or `|400x300` is a size in points, from above 0 to 10,000.
final class EmbedDisplaySizeLimitTests: XCTestCase {
    func testSizeOfTenThousandPointsIsKept() {
        XCTAssertEqual(EmbedDisplaySize.parse(label: "10000"), EmbedDisplaySize(width: 10_000, height: nil))
        XCTAssertEqual(EmbedDisplaySize.parse(label: "Caption|10000x10000"), EmbedDisplaySize(width: 10_000, height: 10_000))
    }

    func testSizeAboveTenThousandPointsIsNotASize() {
        XCTAssertNil(EmbedDisplaySize.parse(label: "10000.5"))
        XCTAssertNil(EmbedDisplaySize.parse(label: "10001"))
        XCTAssertNil(EmbedDisplaySize.parse(label: "400x10001"), "Either dimension beyond the limit voids the size.")
    }

    func testZeroAndNonNumbersAreNotSizes() {
        XCTAssertNil(EmbedDisplaySize.parse(label: "0"))
        XCTAssertNil(EmbedDisplaySize.parse(label: "1e3"))
        XCTAssertNil(EmbedDisplaySize.parse(label: "Infinity"))
        XCTAssertEqual(EmbedDisplaySize.parse(label: "0.5"), EmbedDisplaySize(width: 0.5, height: nil))
    }
}
