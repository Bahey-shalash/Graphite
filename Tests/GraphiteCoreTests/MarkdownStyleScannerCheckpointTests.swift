import XCTest
@testable import GraphiteCore

/// A block-state checkpoint only spares the scanner the text before it: the spans of a
/// range are the same with any checkpoint at or before the line before the range as with none.
final class MarkdownStyleScannerCheckpointTests: XCTestCase {
    /// A note with every construct that carries block state from one line to the next:
    /// frontmatter, backtick and tilde fences, an unclosed-looking fence marker inside
    /// another fence, display math, quoted code, setext underlines and a rule.
    private static let corpus = """
    ---
    title: Checkpoints
    tags: [a, b]
    ---
    # Heading with **bold**
    Paragraph line one
    Setext heading
    ==============
    ```swift
    let x = "```"
    ~~~
    ```
    ~~~python
    # not a heading
    ```
    ~~~
    $$
    a = b
    c = d $$
    After math with [[Link|alias]]
    > quoted line
    > ```
    > # inside quoted code
    > ```
    > [!note]- Title
    > body
    Plain after quote
    ---
    - [ ] task with #tag
    1. numbered
    ```
    unclosed fence runs to the end
    """

    private func lineStarts(in text: NSString) -> [Int] {
        var starts: [Int] = []
        var location = 0
        while location < text.length {
            starts.append(location)
            location = NSMaxRange(text.lineRange(for: NSRange(location: location, length: 0)))
        }
        return starts
    }

    func testSpansOfEveryLineAreTheSameWithAnyEarlierCheckpoint() {
        let text = Self.corpus as NSString
        let starts = lineStarts(in: text)
        XCTAssertGreaterThan(starts.count, 30)
        // One checkpoint per line start, each made from the top of the text.
        let checkpoints = starts.map { start in MarkdownStyleScanner.blockCheckpoint(atLineStart: start, in: text, resumingFrom: nil) }
        var comparedCount = 0
        for (lineIndex, lineStart) in starts.enumerated() {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            let expected = MarkdownStyleScanner.spans(in: text, range: lineRange)
            // The checkpoint must lie at or before the line before the range.
            for checkpoint in checkpoints where lineIndex > 0 && checkpoint.lineStart <= starts[lineIndex - 1] {
                XCTAssertEqual(MarkdownStyleScanner.spans(in: text, range: lineRange, resumingFrom: checkpoint), expected,
                               "Line \(lineIndex) with the checkpoint at \(checkpoint.lineStart)")
                comparedCount += 1
            }
        }
        XCTAssertGreaterThan(comparedCount, 400)
    }

    func testSpansOfARangeAcrossSeveralLinesAreTheSameWithACheckpoint() {
        let text = Self.corpus as NSString
        let starts = lineStarts(in: text)
        for (lineIndex, lineStart) in starts.enumerated() where lineIndex >= 2 {
            let range = NSRange(location: lineStart, length: min(40, text.length - lineStart))
            let expected = MarkdownStyleScanner.spans(in: text, range: range)
            let checkpoint = MarkdownStyleScanner.blockCheckpoint(atLineStart: starts[lineIndex - 2], in: text, resumingFrom: nil)
            XCTAssertEqual(MarkdownStyleScanner.spans(in: text, range: range, resumingFrom: checkpoint), expected, "Range at line \(lineIndex)")
        }
    }

    func testACheckpointBuiltFromAnEarlierCheckpointEqualsOneBuiltFromTheTop() {
        let text = Self.corpus as NSString
        let starts = lineStarts(in: text)
        let early = MarkdownStyleScanner.blockCheckpoint(atLineStart: starts[8], in: text, resumingFrom: nil)
        for start in starts where start >= early.lineStart {
            XCTAssertEqual(MarkdownStyleScanner.blockCheckpoint(atLineStart: start, in: text, resumingFrom: early),
                           MarkdownStyleScanner.blockCheckpoint(atLineStart: start, in: text, resumingFrom: nil), "Line starting at \(start)")
        }
    }

    func testACheckpointFromBeforeAnEditOfTheFrontmatterIsIgnored() {
        let original = "---\na: 1\n---\n```\ncode\n```\nafter\n" as NSString
        let checkpoint = MarkdownStyleScanner.blockCheckpoint(atLineStart: 17, in: original, resumingFrom: nil)
        // The frontmatter grew by two characters, so the checkpoint no longer describes the text.
        let edited = "---\na: 123\n---\n```\ncode\n```\nafter\n" as NSString
        let afterLine = NSRange(location: edited.length - 6, length: 6)
        XCTAssertEqual(MarkdownStyleScanner.spans(in: edited, range: afterLine, resumingFrom: checkpoint), MarkdownStyleScanner.spans(in: edited, range: afterLine))
    }
}
