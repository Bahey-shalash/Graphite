import XCTest
@testable import GraphiteCore

final class MarkdownStyleScannerTests: XCTestCase {
    private func styles(of text: String) -> [(String, MarkdownStyle)] {
        let source = text as NSString
        return MarkdownStyleScanner.spans(in: source, range: NSRange(location: 0, length: source.length)).map { span in
            (source.substring(with: span.range), span.style)
        }
    }

    private func text(styled style: MarkdownStyle, in text: String) -> [String] {
        styles(of: text).filter { styledText in styledText.1 == style }.map(\.0)
    }

    func testHeadingsSeparateMarkerFromTitle() {
        let spans = styles(of: "## Dynamic logic\n")
        XCTAssertTrue(spans.contains { styledText in styledText.0 == "## " && styledText.1 == .concealableMarker })
        XCTAssertTrue(spans.contains { styledText in styledText.0 == "## Dynamic logic" && styledText.1 == .heading(level: 2) }, "The marker shares the heading size.")
    }

    func testInlineConstructs() {
        let line = "Use **bold**, *italic*, `code`, $x^2$, [[Note|alias]], ![[Figure.png|300]], [site](https://a.b) and #tag/sub ==mark== ~~old~~"
        XCTAssertEqual(text(styled: .strong, in: line), ["bold"])
        XCTAssertEqual(text(styled: .emphasis, in: line), ["italic"])
        XCTAssertEqual(text(styled: .inlineCode, in: line), ["code"])
        XCTAssertEqual(text(styled: .math, in: line), ["$x^2$"])
        XCTAssertEqual(text(styled: .link, in: line), ["alias", "site"])
        XCTAssertTrue(text(styled: .concealableMarker, in: line).contains("[[Note|"), "The target of an aliased link is concealed in Live Preview.")
        XCTAssertEqual(text(styled: .embed, in: line), ["Figure.png|300"])
        XCTAssertEqual(text(styled: .tag, in: line), ["#tag/sub"])
        XCTAssertEqual(text(styled: .highlight, in: line), ["mark"])
        XCTAssertEqual(text(styled: .strikethrough, in: line), ["old"])
    }

    func testSameNoteHeadingLinkReadsAsHeading() {
        XCTAssertEqual(text(styled: .link, in: "- [[#General Concepts]]"), ["General Concepts"])
        XCTAssertTrue(text(styled: .concealableMarker, in: "- [[#General Concepts]]").contains("[[#"))
        XCTAssertEqual(text(styled: .link, in: "See [[4_Logic design#Saturation Region]]"), ["4_Logic design", "Saturation Region"])
        XCTAssertEqual(text(styled: .subpathSeparator, in: "See [[4_Logic design#Saturation Region]]"), ["#"])
    }

    func testCodeHidesMarkdownInsideIt() {
        let line = "`**not bold** [[not a link]]` #real"
        XCTAssertTrue(text(styled: .strong, in: line).isEmpty)
        XCTAssertTrue(text(styled: .link, in: line).isEmpty)
        XCTAssertEqual(text(styled: .tag, in: line), ["#real"])
    }

    func testFencedCodeMathAndFrontmatterContexts() {
        let source = "---\ntags: [a]\n---\n# Title\n```swift\nlet x = \"#notATag\"\n```\n$$\nf = x\n$$\nAfter #tag\n"
        XCTAssertEqual(text(styled: .frontmatter, in: source), ["---", "tags: [a]", "---"])
        XCTAssertEqual(text(styled: .codeBlock, in: source), ["let x = \"#notATag\""])
        XCTAssertEqual(text(styled: .math, in: source), ["$$", "f = x", "$$"])
        XCTAssertEqual(text(styled: .tag, in: source), ["#tag"])
        let nsSource = source as NSString
        XCTAssertEqual(MarkdownStyleScanner.blockContext(atLineContaining: nsSource.range(of: "let x").location, in: nsSource), .fencedCode)
        XCTAssertEqual(MarkdownStyleScanner.blockContext(atLineContaining: nsSource.range(of: "After").location, in: nsSource), .normal)
    }

    func testCalloutsQuotesListsAndTasks() {
        let source = "> [!note]- Slides No. 28\n> Quoted $$f = x$$ text\n- [ ] Task\n1. Item\n"
        XCTAssertEqual(text(styled: .calloutTitle, in: source), ["[!note]-"])
        XCTAssertEqual(text(styled: .taskMarker, in: source), ["[ ]"])
        XCTAssertEqual(text(styled: .listMarker, in: source), ["-", "1."])
        XCTAssertTrue(styles(of: source).contains { styledText in styledText.0 == "> " && styledText.1 == .syntaxMarker })
    }

    func testHeadingAndTagDisambiguation() {
        XCTAssertTrue(text(styled: .tag, in: "# Heading\n").isEmpty)
        XCTAssertTrue(text(styled: .tag, in: "Slide #29 and https://a.b/#frag\n").isEmpty, "Numbers alone and URL fragments are not tags.")
        XCTAssertEqual(text(styled: .tag, in: "#2024review\n"), ["#2024review"])
    }

    func testWindowsLineEndingsAreNotStyled() {
        let spans = styles(of: "# Title\r\nText **bold**\r\n")
        XCTAssertFalse(spans.contains { styledText in styledText.0.contains("\r") || styledText.0.contains("\n") })
        XCTAssertTrue(spans.contains { styledText in styledText.0 == "# Title" })
    }

    func testRestyleScopeDetectsBlockDelimiters() {
        XCTAssertTrue(MarkdownStyleScanner.lineAffectsFollowingLines("```swift"))
        XCTAssertTrue(MarkdownStyleScanner.lineAffectsFollowingLines("> $$"))
        XCTAssertTrue(MarkdownStyleScanner.lineAffectsFollowingLines("---"))
        XCTAssertFalse(MarkdownStyleScanner.lineAffectsFollowingLines("Plain text with $x$"))
    }

    func testCodeLinesKnowTheirFencedBlock() throws {
        let source = "Intro\n```C++ title=x\nint a;\n\nint b;\n```\n> ```py\n> x = 1\n" as NSString
        let spans = MarkdownStyleScanner.spans(in: source, range: NSRange(location: 0, length: source.length)).filter { span in span.style == .codeBlock }
        let codeStart = NSMaxRange(source.lineRange(for: NSRange(location: source.range(of: "```C++").location, length: 0)))
        XCTAssertEqual(spans.map { span in source.substring(with: span.range) }, ["int a;", "", "int b;", "> x = 1"], "A blank code line has an empty span.")
        XCTAssertEqual(spans[0].fencedCodeBlock, FencedCodeBlock(language: "C++", codeStart: codeStart, quoteDepth: 0, fence: "```"))
        XCTAssertEqual(spans[1].fencedCodeBlock, spans[0].fencedCodeBlock)
        XCTAssertEqual(spans[2].fencedCodeBlock, spans[0].fencedCodeBlock)
        XCTAssertEqual(spans[3].fencedCodeBlock?.language, "py")
        XCTAssertEqual(spans[3].fencedCodeBlock?.quoteDepth, 1)
        // Styling only the last line of the first block still finds where the block starts.
        let lastLine = source.range(of: "int b;")
        let partialSpans = MarkdownStyleScanner.spans(in: source, range: lastLine).filter { span in span.style == .codeBlock }
        XCTAssertEqual(partialSpans.first?.fencedCodeBlock, spans[0].fencedCodeBlock)
    }
}
