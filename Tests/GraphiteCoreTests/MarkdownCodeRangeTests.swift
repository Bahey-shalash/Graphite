import XCTest
@testable import GraphiteCore

final class MarkdownCodeRangeTests: XCTestCase {
    func testCodeSpansAndFencesAreFound() {
        let text = "Use `![[a.png]]` here\n```\n[[b]]\n```\n[[c]] ``x ` y``" as NSString
        let ranges = MarkdownCodeRanges.ranges(in: text)
        XCTAssertTrue(MarkdownCodeRanges.range(text.range(of: "![[a.png]]"), isInside: ranges))
        XCTAssertTrue(MarkdownCodeRanges.range(text.range(of: "[[b]]"), isInside: ranges))
        XCTAssertFalse(MarkdownCodeRanges.range(text.range(of: "[[c]]"), isInside: ranges))
        XCTAssertTrue(MarkdownCodeRanges.range(text.range(of: "x ` y"), isInside: ranges))
    }
}
