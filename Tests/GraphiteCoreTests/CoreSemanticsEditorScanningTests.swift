import XCTest
@testable import GraphiteCore

/// Editor styling and Live Preview blocks follow CommonMark fences, display math rules,
/// setext headings and the note's line endings.
final class CoreSemanticsEditorScanningTests: XCTestCase {
    private func styles(of text: String) -> [(String, MarkdownStyle)] {
        let source = text as NSString
        return MarkdownStyleScanner.spans(in: source, range: NSRange(location: 0, length: source.length)).map { span in
            (source.substring(with: span.range), span.style)
        }
    }

    private func text(styled style: MarkdownStyle, in text: String) -> [String] {
        styles(of: text).filter { styledText in styledText.1 == style }.map(\.0)
    }

    private func context(atLineOf fragment: String, in text: String) -> MarkdownBlockContext {
        let source = text as NSString
        return MarkdownStyleScanner.blockContext(atLineContaining: source.range(of: fragment).location, in: source)
    }

    // MARK: Fences (CommonMark)

    func testOneLineTripleBacktickSpanDoesNotOpenAFence() {
        let source = "```js console.log(1)```\nAfter **bold** #tag"
        XCTAssertEqual(context(atLineOf: "After", in: source), .normal)
        XCTAssertEqual(text(styled: .strong, in: source), ["bold"])
        XCTAssertEqual(text(styled: .inlineCode, in: source), ["js console.log(1)"])
    }

    func testFencesCloseOnlyWithTheSameCharacterAndAtLeastTheSameLength() {
        let tildes = "~~~\n```\nstill code\n~~~\nafter **bold**"
        XCTAssertEqual(context(atLineOf: "still code", in: tildes), .fencedCode)
        XCTAssertEqual(context(atLineOf: "after", in: tildes), .normal)
        XCTAssertEqual(text(styled: .codeBlock, in: tildes), ["```", "still code"])
        let nested = "````\n```\ninner **x**\n````\nout **y**"
        XCTAssertEqual(text(styled: .strong, in: nested), ["y"])
        let withInfo = "```\ncode\n```swift\nstill code **z**\n```\n"
        XCTAssertEqual(context(atLineOf: "still code", in: withInfo), .fencedCode, "A closing fence has no info text.")
        XCTAssertTrue(text(styled: .strong, in: withInfo).isEmpty)
    }

    func testAFenceInsideAQuoteEndsWithTheQuote() {
        let source = "> ```\n> code\n\nNormal **bold** #tag"
        XCTAssertEqual(context(atLineOf: "> code", in: source), .fencedCode)
        XCTAssertEqual(context(atLineOf: "Normal", in: source), .normal)
        XCTAssertEqual(text(styled: .strong, in: source), ["bold"])
        XCTAssertEqual(context(atLineOf: "inside", in: "```\n> ```\ninside\n```\nafter"), .fencedCode, "A quote marker inside code is code.")
    }

    // MARK: Display and inline math

    func testDisplayMathClosedOnItsLineDoesNotStyleTheRestOfTheNote() {
        let source = "$$E=mc^2$$ where E is energy\nnext **bold**\nmore #tag"
        XCTAssertEqual(context(atLineOf: "next", in: source), .normal)
        XCTAssertEqual(text(styled: .math, in: source), ["$$E=mc^2$$"])
        XCTAssertEqual(text(styled: .strong, in: source), ["bold"])
        XCTAssertEqual(text(styled: .tag, in: source), ["#tag"])
        XCTAssertEqual(context(atLineOf: "after", in: "$$$$\nafter **bold**"), .normal)
        XCTAssertEqual(context(atLineOf: "x = 1", in: "$$ a $$ b $$\nx = 1\n$$\n"), .mathBlock, "An odd count leaves math open.")
    }

    func testInlineMathSkipsPricesAndEscapedDollars() {
        XCTAssertTrue(text(styled: .math, in: "Prices $5/$10 and $5,$6").isEmpty)
        XCTAssertEqual(text(styled: .math, in: "$a\\$b$ and $x^2$"), ["$a\\$b$", "$x^2$"])
    }

    // MARK: Setext headings and rules

    func testSetextHeadingsAreStyledAsHeadings() {
        XCTAssertEqual(text(styled: .heading(level: 2), in: "Title\n---\nText"), ["Title"])
        XCTAssertEqual(text(styled: .syntaxMarker, in: "Title\n---\nText"), ["---"])
        XCTAssertTrue(text(styled: .horizontalRule, in: "Title\n---\nText").isEmpty)
        XCTAssertEqual(text(styled: .heading(level: 1), in: "Title\n===\n"), ["Title"])
        XCTAssertEqual(text(styled: .horizontalRule, in: "# Title\n---\ntext"), ["---"], "After an ATX heading, --- is a rule.")
        XCTAssertEqual(text(styled: .horizontalRule, in: "Text\n\n---"), ["---"])
        XCTAssertEqual(text(styled: .horizontalRule, in: "- item\n---"), ["---"])
    }

    func testRestylingOneLineAlsoRestylesItsSetextNeighbor() {
        let source = "Title\n---\nText" as NSString
        let titleLine = MarkdownStyleScanner.spans(in: source, range: NSRange(location: 0, length: 0))
        XCTAssertTrue(titleLine.contains { span in span.style == .syntaxMarker && source.substring(with: span.range) == "---" },
                      "Typing on the title line restyles the underline below it.")
        let underline = MarkdownStyleScanner.spans(in: source, range: NSRange(location: 6, length: 0))
        XCTAssertTrue(underline.contains { span in span.style == .heading(level: 2) && source.substring(with: span.range) == "Title" },
                      "Typing on the underline restyles the title above it.")
    }

    // MARK: Inline syntax

    func testCalloutTitleOnlyRightAfterTheQuoteMarker() {
        XCTAssertTrue(text(styled: .calloutTitle, in: "> text [!note] more").isEmpty)
        XCTAssertEqual(text(styled: .calloutTitle, in: "> [!note] Title"), ["[!note]"])
    }

    func testMarkdownLinkDestinationsMayHoldParentheses() {
        let source = "[w](https://e.org/F_(b)) end"
        XCTAssertEqual(text(styled: .link, in: source), ["w"])
        XCTAssertEqual(text(styled: .concealableMarker, in: source), ["[", "](https://e.org/F_(b))"])
    }

    func testMultiBacktickCodeSpans() {
        XCTAssertEqual(text(styled: .inlineCode, in: "Use `` a`b `` here"), [" a`b "])
        XCTAssertEqual(text(styled: .concealableMarker, in: "Use `` a`b `` here"), ["``", "``"])
        XCTAssertTrue(text(styled: .inlineCode, in: "\\`not code\\`").isEmpty)
    }

    func testUnclosedFrontmatterIsNotStyledAsFrontmatter() {
        let source = "---\n# Heading\nText **bold** #tag"
        XCTAssertTrue(text(styled: .frontmatter, in: source).isEmpty)
        XCTAssertEqual(text(styled: .heading(level: 1), in: source), ["# Heading"])
        XCTAssertEqual(text(styled: .frontmatter, in: "---\ntitle: A\n---\nBody"), ["---", "title: A", "---"])
        XCTAssertEqual(MarkdownStyleScanner.blockContext(atLineContaining: 5, in: "---\ntitle: A\n---\nBody" as NSString), .frontmatter)
    }

    // MARK: Block context without reading every line

    /// The fast block-context search must agree with applying the block rules to every
    /// line in order.
    func testBlockContextMatchesALineByLineWalk() {
        var generator = SeededGenerator(seed: 42)
        let pieces = ["text", "```", "```swift", "~~~", "````", "$$", "$$x$$", "a $$", "x$$", "> quote", "> ```", ">> ```", "> code", "  ```",
                      "`code`", "$x$", "", "\t```", "\u{00A0}```", "$$ y", "é", "---", "> $$", "$$ a $$ b $$", "```js a```"]
        for _ in 0..<1_500 {
            let lineBreak = ["\n", "\r\n", "\r", "\u{2028}"][Int(generator.next() % 4)]
            let lines = (0..<(1 + Int(generator.next() % 12))).map { _ in pieces[Int(generator.next() % UInt64(pieces.count))] }
            let source = ("Intro" + lineBreak + lines.joined(separator: lineBreak) + lineBreak + "end") as NSString
            var expected = MarkdownStyleScanner.BlockState()
            var lineStart = 0
            while lineStart < source.length {
                let lineRange = source.lineRange(for: NSRange(location: lineStart, length: 0))
                XCTAssertEqual(MarkdownStyleScanner.blockContext(atLineContaining: lineStart, in: source), expected.context, "\(source) at \(lineStart)")
                expected = MarkdownStyleScanner.nextState(after: source.substring(with: lineRange), expected)
                lineStart = NSMaxRange(lineRange)
            }
        }
    }

    /// The search reads the text in chunks of 4,096 units; fences, math delimiters and
    /// line breaks that straddle a chunk boundary must be found as in a line-by-line walk.
    func testBlockContextMatchesALineByLineWalkAcrossChunkBoundaries() {
        let fillerLine = String(repeating: "a", count: 99) + "\n"
        let blockLines = ["```swift", "let value = 1", "> ```", "```", "$$", "x^2", "y$$", "~~~", "`code`", "~~~", "$$ a $$ b", "c $$"]
        for padding in 4_080...4_100 {
            let filler = String(repeating: fillerLine, count: padding / 100) + String(repeating: "b", count: padding % 100)
            let source = (filler + "\n" + blockLines.joined(separator: "\n") + "\n" + filler + "\nend") as NSString
            var expected = MarkdownStyleScanner.BlockState()
            var lineStart = 0
            while lineStart < source.length {
                let lineRange = source.lineRange(for: NSRange(location: lineStart, length: 0))
                XCTAssertEqual(MarkdownStyleScanner.blockContext(atLineContaining: lineStart, in: source), expected.context, "padding \(padding) at \(lineStart)")
                expected = MarkdownStyleScanner.nextState(after: source.substring(with: lineRange), expected)
                lineStart = NSMaxRange(lineRange)
            }
        }
    }

    // MARK: Live Preview blocks

    func testLivePreviewBlocksInWindowsNotesMatchLineFeedNotes() {
        let lineFeedNote = "Text\n| a | b |\n| - | - |\n| 1 | 2 |\n```base\nviews: []\n```\n> [!note] T\n> body line\n\n---\n$$\nx^2\n$$\nafter text\n![[e.png]]\n"
        let windowsNote = lineFeedNote.replacingOccurrences(of: "\n", with: "\r\n")
        let lineFeedBlocks = LivePreviewBlockScanner.blocks(in: lineFeedNote as NSString)
        let windowsBlocks = LivePreviewBlockScanner.blocks(in: windowsNote as NSString)
        XCTAssertEqual(windowsBlocks.map(\.kind), lineFeedBlocks.map(\.kind))
        XCTAssertEqual(windowsBlocks.map(\.markdown), lineFeedBlocks.map(\.markdown), "Rendered Markdown always uses line feeds.")
        XCTAssertEqual(lineFeedBlocks.count, 6)
        XCTAssertEqual(windowsBlocks.first { block in block.kind == .callout }?.markdown, "> [!note] T\n> body line")
        let windowsMath = windowsBlocks.first { block in block.kind == .mathBlock }
        XCTAssertEqual(windowsMath.map { block in (windowsNote as NSString).substring(with: block.range) }, "$$\r\nx^2\r\n$$\r\n")
    }

    func testLivePreviewKeepsUnicodeLineSeparatorsInsideALine() {
        XCTAssertTrue(LivePreviewBlockScanner.blocks(in: "text\u{2028}$$x$$ more\nnext" as NSString).isEmpty)
    }

    func testLivePreviewDisplayMathClosedOnItsLineIsText() {
        XCTAssertTrue(LivePreviewBlockScanner.blocks(in: "$$E=mc^2$$ where E is energy\nnext\n| a |\n| - |" as NSString).map(\.kind).allSatisfy { kind in kind == .table })
        XCTAssertEqual(LivePreviewBlockScanner.blocks(in: "$$f$$\ntext" as NSString).map(\.kind), [.mathBlock])
    }

    func testLivePreviewRuleAfterAHeadingOrBlock() {
        XCTAssertEqual(LivePreviewBlockScanner.blocks(in: "# Title\n---\ntext" as NSString).map(\.kind), [.horizontalRule])
        XCTAssertEqual(LivePreviewBlockScanner.blocks(in: "- item\n---\n" as NSString).map(\.kind), [.horizontalRule])
        XCTAssertEqual(LivePreviewBlockScanner.blocks(in: "| a |\n| - |\n---\n" as NSString).map(\.kind), [.table, .horizontalRule])
        XCTAssertTrue(LivePreviewBlockScanner.blocks(in: "Title\n---\ntext" as NSString).isEmpty, "A setext underline is not a rule.")
    }
}

/// A small deterministic generator, so the randomized comparison is reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 11
    }
}
