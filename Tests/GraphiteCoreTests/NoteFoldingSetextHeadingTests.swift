import XCTest
@testable import GraphiteCore

/// A setext heading folds like an ATX heading: its section runs to the next heading of the
/// same or a higher level, and the underline folds away with the section.
final class NoteFoldingSetextHeadingTests: XCTestCase {
    private func hidden(_ region: FoldableRegion, in text: String) -> String {
        (text as NSString).substring(with: region.hiddenRange)
    }

    func testSetextHeadingsFoldToTheNextHeadingOfTheSameOrHigherLevel() {
        let text = "Title\n=====\nIntro\nSub\n---\nBody\n\nNext\n=====\nTail\n"
        let regions = NoteFolding.regions(in: text)
        XCTAssertEqual(regions.map(\.kind), [.heading(level: 1), .heading(level: 2), .heading(level: 1)])
        guard regions.count == 3 else { return }
        XCTAssertEqual((text as NSString).substring(with: regions[0].headerRange), "Title")
        XCTAssertEqual(hidden(regions[0], in: text), "\n=====\nIntro\nSub\n---\nBody")
        XCTAssertEqual(hidden(regions[1], in: text), "\n---\nBody", "Blank lines before the next heading stay visible.")
        XCTAssertEqual(regions.map(\.key), ["h1|Title|0", "h2|Sub|0", "h1|Next|0"])
    }

    func testASetextHeadingWithNothingUnderItsUnderlineDoesNotFold() {
        XCTAssertTrue(NoteFolding.regions(in: "Alone\n=====\n").isEmpty)
        XCTAssertTrue(NoteFolding.regions(in: "Alone\n=====\n\n\n").isEmpty)
        XCTAssertEqual(NoteFolding.regions(in: "Alone\n=====\nText").count, 1)
    }

    func testARuleAfterABlankLineStartsNoRegion() {
        XCTAssertTrue(NoteFolding.regions(in: "Text\n\n---\nMore").isEmpty)
    }

    func testSetextHeadingsInCodeStartNoRegion() {
        XCTAssertTrue(NoteFolding.regions(in: "```\nTitle\n=====\nBody\n```\n").isEmpty)
    }

    func testReadAloudLeavesOutAFoldedSetextSection() {
        let text = "Title\n=====\nHidden text\nNext\n=====\nShown text\n"
        let hiddenRanges = ReadAloudFolding.hiddenRanges(in: text, foldedKeys: ["h1|Title|0"], calloutExpansion: [:])
        XCTAssertEqual(hiddenRanges.map { range in (text as NSString).substring(with: range) }, ["\n=====\nHidden text"])
    }

    func testTypingInASetextHeadingLineFindsTheRegionsAgain() {
        let before = "Title\n=====\nBody\n" as NSString
        let after = "Titles\n=====\nBody\n" as NSString
        let regions = NoteFolding.regions(in: before as String)
        XCTAssertNil(NoteFolding.regions(regions, across: NSRange(location: 5, length: 0), replacementLength: 1, before: before, after: after),
                     "The line is the heading's text, so its key changes.")
    }

    func testTypingAnUnderlineUnderAParagraphLineFindsTheRegionsAgain() {
        let before = "Title\n==\nBody\n" as NSString
        let after = "Title\n===\nBody\n" as NSString
        let regions = NoteFolding.regions(in: before as String)
        XCTAssertNil(NoteFolding.regions(regions, across: NSRange(location: 8, length: 0), replacementLength: 1, before: before, after: after))
    }
}
