import XCTest
@testable import GraphiteCore

final class MarkdownCodeRangeTests: XCTestCase {
    func testCodeSpansAndFencesAreFound() {
        let text = "Use `![[a.png]]` here\n```\n[[b]]\n```\n[[c]] ``x ` y``" as NSString
        let codeRanges = MarkdownCodeRanges.rangeSet(in: text)
        XCTAssertTrue(codeRanges.intersects(text.range(of: "![[a.png]]")))
        XCTAssertTrue(codeRanges.intersects(text.range(of: "[[b]]")))
        XCTAssertFalse(codeRanges.intersects(text.range(of: "[[c]]")))
        XCTAssertTrue(codeRanges.intersects(text.range(of: "x ` y")))
    }
}
