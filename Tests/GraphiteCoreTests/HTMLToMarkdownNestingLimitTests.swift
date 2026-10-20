import XCTest
@testable import GraphiteCore

/// Pasted HTML nested deeper than 64 levels of quotes or of inline elements is converted as
/// if the deeper tags were absent, which bounds the work and the size of the output.
final class HTMLToMarkdownNestingLimitTests: XCTestCase {
    func testQuotesBeyondSixtyFourLevelsAddNoMoreQuoteMarkers() {
        func deepestQuotePrefix(depth: Int) -> Int {
            let html = String(repeating: "<blockquote>", count: depth) + "deep" + String(repeating: "</blockquote>", count: depth)
            let line = HTMLToMarkdown.markdown(from: html).split(separator: "\n").first { line in line.contains("deep") } ?? ""
            return line.prefix { character in character == ">" || character == " " }.filter { $0 == ">" }.count
        }
        XCTAssertEqual(deepestQuotePrefix(depth: 64), 64)
        XCTAssertEqual(deepestQuotePrefix(depth: 65), 64)
        XCTAssertEqual(deepestQuotePrefix(depth: 200), 64)
    }

    /// Repeated emphasis is written once, so the limit shows in the element opened after the
    /// limit's worth of emphasis: bold written inside 63 italics is bold, inside 64 it is ignored.
    func testInlineElementsBeyondSixtyFourLevelsAreIgnored() {
        func markdown(italicDepth: Int) -> String {
            HTMLToMarkdown.markdown(from: String(repeating: "<i>", count: italicDepth) + "<b>word</b>" + String(repeating: "</i>", count: italicDepth))
        }
        XCTAssertTrue(markdown(italicDepth: 63).contains("**word**"), "The 64th element is tracked.")
        XCTAssertFalse(markdown(italicDepth: 64).contains("**"), "The 65th element is ignored.")
        XCTAssertFalse(markdown(italicDepth: 100).contains("**"))
        XCTAssertTrue(markdown(italicDepth: 64).contains("word"), "Its text is kept.")
    }
}
