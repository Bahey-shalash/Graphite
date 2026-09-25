import XCTest
@testable import GraphiteCore

/// Code ranges and block insertion follow CommonMark and the note's own line endings.
final class CoreSemanticsTextRulesTests: XCTestCase {
    private func codeTexts(in text: String) -> [String] {
        let source = text as NSString
        return MarkdownCodeRanges.ranges(in: source).sorted { first, second in first.location < second.location }.map { range in source.substring(with: range) }
    }

    func testEscapedBackticksAreNotCode() {
        XCTAssertEqual(codeTexts(in: "\\`[[Real]]\\` and `code`"), ["`code`"])
        XCTAssertEqual(codeTexts(in: "\\``real code`"), ["`real code`"], "Only the escaped backtick is literal.")
        XCTAssertEqual(codeTexts(in: "`a\\` b"), ["`a\\`"], "A backslash inside code is literal and cannot escape the closing run.")
    }

    func testCodeSpansNeedAClosingRunOfTheSameLength() {
        XCTAssertEqual(codeTexts(in: "Use `` a`b `` here"), ["`` a`b ``"])
        XCTAssertEqual(codeTexts(in: "``unclosed `closed`"), ["`closed`"])
        XCTAssertEqual(codeTexts(in: "`first\nsecond`"), [], "Spans stay on one line.")
    }

    func testIndentedFenceContinuingAParagraphIsText() {
        let text = "\\`[[Real]]\\`\n    ```\n[[AfterIndented]]"
        XCTAssertEqual(codeTexts(in: text), [])
        XCTAssertFalse(MarkdownCodeRanges.range((text as NSString).range(of: "[[AfterIndented]]"), isInside: MarkdownCodeRanges.ranges(in: text as NSString)))
    }

    func testFencesInsideListItemsMayBeIndented() {
        XCTAssertEqual(codeTexts(in: "- item\n    ```\n    [[InCode]]\n    ```\nafter"), ["    ```\n    [[InCode]]\n    ```\n"])
        XCTAssertEqual(codeTexts(in: "1. item\n   ```\n   code\n   ```\n"), ["   ```\n   code\n   ```\n"])
        XCTAssertEqual(codeTexts(in: "- item\n\ntext\n    ```\n[[Link]]"), [], "The list ended at the unindented paragraph.")
        XCTAssertEqual(codeTexts(in: "```\ncode\n    ```\nstill code\n```\nafter"), ["```\ncode\n    ```\nstill code\n```\n"],
                       "A closing fence indented four columns is content.")
    }

    private func inserting(_ block: String, into source: String, at location: Int, separatedByBlankLines: Bool = false) -> String {
        let nsSource = source as NSString
        let range = NSRange(location: location, length: 0)
        return nsSource.replacingCharacters(in: range, with: MarkdownBlockInsertion.text(inserting: block, into: nsSource, replacing: range, separatedByBlankLines: separatedByBlankLines))
    }

    func testBlockInsertionKeepsWindowsLineEndings() {
        XCTAssertEqual(inserting("![[a.png]]", into: "Text\r\nNext\r\n", at: 4), "Text\r\n![[a.png]]\r\nNext\r\n")
        XCTAssertEqual(inserting("![[a.png]]", into: "Text\r\nNext\r\n", at: 6), "Text\r\n![[a.png]]\r\nNext\r\n")
        XCTAssertEqual(inserting("![[a.png]]", into: "---\r\ntitle: A\r\n---\r\n", at: 20), "---\r\ntitle: A\r\n---\r\n![[a.png]]\r\n")
        XCTAssertEqual(inserting("![[a.png]]", into: "Links\r\n\r\n---\r\n", at: 7), "Links\r\n![[a.png]]\r\n\r\n---\r\n", "No setext heading.")
        XCTAssertEqual(inserting("| a |\n| - |", into: "Text\r\nMore", at: 4), "Text\r\n| a |\r\n| - |\r\nMore")
        XCTAssertEqual(inserting("> Quoted\n\n[[Book]]", into: "Line one\r\nLine two", at: 8, separatedByBlankLines: true),
                       "Line one\r\n\r\n> Quoted\r\n\r\n[[Book]]\r\n\r\nLine two")
    }

    func testBlockInsertionKeepsLineFeedNotesUnchanged() {
        XCTAssertEqual(inserting("![[a.png]]", into: "Text\nNext\n", at: 4), "Text\n![[a.png]]\nNext\n")
        XCTAssertEqual(inserting("![[a.png]]", into: "Text", at: 4), "Text\n![[a.png]]\n")
    }
}
