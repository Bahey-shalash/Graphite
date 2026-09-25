import XCTest
@testable import GraphiteCore

final class NotePreviewDocumentTests: XCTestCase {
    func testHeadingsCalloutsEmbedsAndBasesBecomeBlocks() {
        let body = """
        Intro paragraph
        ## Table of Contents
        - [[#General Concepts]]

        > [!note]- Slides No. 28
        > Hidden **body**
        > $$f = x$$

        ![[Lecture.pdf#page=3]]
        ![[demo.mp4]]
        ```base
        views:
          - type: table
        ```
        ```swift
        # not a heading
        ```
        ### General Concepts
        """
        let blocks = NotePreviewDocument.blocks(from: body)
        guard blocks.count == 9 else { return XCTFail("Expected 9 blocks, got \(blocks)") }
        XCTAssertEqual(blocks[0], .markdown("Intro paragraph"))
        XCTAssertEqual(blocks[1], .heading(level: 2, text: "Table of Contents", anchor: "table of contents"))
        guard case .callout(let type, let title, let folding, let calloutBody) = blocks[3] else { return XCTFail("Expected a callout, got \(blocks[3])") }
        XCTAssertEqual(type, "note")
        XCTAssertEqual(title, "Slides No. 28")
        XCTAssertEqual(folding, .collapsed)
        XCTAssertEqual(calloutBody, [.markdown("Hidden **body**"), .displayMath("$$f = x$$")])
        guard case .embed(let pdfEmbed) = blocks[4], case .embed(let videoEmbed) = blocks[5] else { return XCTFail("Expected embeds") }
        XCTAssertEqual(pdfEmbed.target, "Lecture.pdf#page=3")
        XCTAssertEqual(videoEmbed.target, "demo.mp4")
        XCTAssertEqual(blocks[6], .baseDefinition("views:\n  - type: table"))
        XCTAssertEqual(blocks[7], .markdown("```swift\n# not a heading\n```"))
        XCTAssertEqual(blocks[8], .heading(level: 3, text: "General Concepts", anchor: "general concepts"))
    }

    func testOutlineSkipsCode() {
        let outline = NotePreviewDocument.outline(of: "# One\n```\n# Code\n```\n## Two  \n")
        XCTAssertEqual(outline.map(\.text), ["One", "Two"])
        XCTAssertEqual(outline.map(\.level), [1, 2])
    }

    func testInlineMarkupForReading() {
        let prepared = ObsidianInlineMarkup.preparedForReading("A ~={#ff0000}red=~ and ==mark== %%hidden%% `==code==`", colorsEnabled: true, paletteHexByName: [:])
        XCTAssertEqual(prepared, "A \u{E000}#ff0000\u{E001}red\u{E002} and \u{E003}mark\u{E004}  `==code==`")
        XCTAssertEqual(ObsidianInlineMarkup.preparedForReading("~={#ff0000}x=~", colorsEnabled: false, paletteHexByName: [:]), "~={#ff0000}x=~")
    }

    func testDisplayMathInsideTableCellsBecomesInline() {
        let table = "| $$A \\uparrow$$ | text |\n$$\nx\n$$"
        XCTAssertEqual(ObsidianInlineMarkup.displayMathInTableCellsMadeInline(table), "| $A \\uparrow$ | text |\n$$\nx\n$$")
    }

    func testSectionRunsToTheNextHeadingOfTheSameLevel() {
        let body = "# Top\nintro\n## Saturation Region\ntext\n### Detail\nmore\n## Linear Region\nother"
        XCTAssertEqual(NotePreviewDocument.section(of: body, headingAnchor: "saturation region"), "## Saturation Region\ntext\n### Detail\nmore")
        XCTAssertEqual(NotePreviewDocument.section(of: body, headingAnchor: "missing"), body)
    }

    func testDisplayMathBlockBecomesOneLineWithItsLaTeXProtected() {
        let markdown = "Before\n\n$$\n\\frac{a}{b} % half\n\\{x \\mid x > 0\\}\n$$\n\nAfter"
        XCTAssertEqual(ObsidianInlineMarkup.protectingMath(in: markdown),
                       "Before\n\n$$ \\\\frac\\{a\\}\\{b\\}  \\\\\\{x \\\\mid x \\> 0\\\\\\} $$\n\nAfter")
    }

    func testQuotedDisplayMathKeepsItsQuotePrefix() {
        XCTAssertEqual(ObsidianInlineMarkup.protectingMath(in: "> $$\n> x^2\n> $$"), "> $$ x\\^2 $$")
    }

    func testInlineMathIsProtectedButDollarAmountsAndCodeAreNot() {
        XCTAssertEqual(ObsidianInlineMarkup.protectingMath(in: "Area $a*b*c$ costs $5 and $10."), "Area $a\\*b\\*c$ costs $5 and $10.")
        XCTAssertEqual(ObsidianInlineMarkup.protectingMath(in: "`$a*b$` and\n```\n$$\nx*y\n$$\n```"), "`$a*b$` and\n```\n$$\nx*y\n$$\n```")
        XCTAssertEqual(ObsidianInlineMarkup.protectingMath(in: "Inline $$x_1$$ display"), "Inline $$x\\_1$$ display")
    }

    func testMathJaxEnvironmentsBecomeOnesTheTypesetterDraws() {
        XCTAssertEqual(LaTeXCompatibility.normalized("\\begin{align}a &= b \\tag{1}\\\\ c &= d \\nonumber\\end{align}"),
                       "\\begin{aligned}a &= b \\\\ c &= d \\end{aligned}")
        XCTAssertEqual(LaTeXCompatibility.normalized("\\begin{equation*}E \\label{eq:e}\\end{equation*}"), "E ")
        // `aligned` needs two columns, so a formula without `&` gains an empty second one.
        XCTAssertEqual(LaTeXCompatibility.normalized("\\begin{alignat}{2}x\\end{alignat}"), "\\begin{aligned}x&\\end{aligned}")
        XCTAssertEqual(LaTeXCompatibility.normalized("\\begin{gather*}x\\end{gather*}"), "\\begin{gather}x\\end{gather}")
        XCTAssertEqual(LaTeXCompatibility.normalized("\\begin{aligned}x\\end{aligned}"), "\\begin{aligned}x&\\end{aligned}")
        XCTAssertEqual(LaTeXCompatibility.normalized("\\begin{aligned}a &= b\\end{aligned}"), "\\begin{aligned}a &= b\\end{aligned}")
    }

    func testPipeEscapedForATableStaysAPipeInsideMath() {
        XCTAssertEqual(ObsidianInlineMarkup.protectingMath(in: "| $a \\| b$ | c |"), "| $a \\| b$ | c |")
    }

    func testLongerFencesAreClosedOnlyByLongerOrEqualFences() {
        let body = "````base\nviews:\n  - type: table\n```\nstill yaml\n````\n\n````\n```\n# not a heading\n```\n````\n# Heading"
        let blocks = NotePreviewDocument.blocks(from: body)
        XCTAssertEqual(blocks.first, .baseDefinition("views:\n  - type: table\n```\nstill yaml"))
        XCTAssertEqual(NotePreviewDocument.outline(of: body).map(\.text), ["Heading"])
        XCTAssertEqual(LivePreviewBlockScanner.blocks(in: body as NSString).first?.markdown, "views:\n  - type: table\n```\nstill yaml")
    }

    func testBlockIdentifiersAreHiddenWhenReading() {
        XCTAssertEqual(ObsidianInlineMarkup.removingBlockIdentifiers(from: "Growth was normal. ^7943cj\n| a |\n^table1\n```\ncode ^keep\n```\nx^2"),
                       "Growth was normal.\n| a |\n\n```\ncode ^keep\n```\nx^2")
        let text = "Growth was normal. ^7943cj" as NSString
        let spans = MarkdownStyleScanner.spans(in: text, range: NSRange(location: 0, length: text.length))
        XCTAssertTrue(spans.contains { span in span.style == .concealableMarker && text.substring(with: span.range) == "^7943cj" })
    }

    func testTaskCheckboxesAreMarkedOutsideCode() {
        let unchecked = String(ObsidianInlineMarkup.uncheckedTaskMarker)
        let checked = String(ObsidianInlineMarkup.checkedTaskMarker)
        let markdown = "- [ ] open\n  1. [x] done\n> - [X] quoted\n- [/] other\n[ ] not a list\n```\n- [ ] code\n```"
        XCTAssertEqual(ObsidianInlineMarkup.markingTasks(in: markdown),
                       "- \(unchecked) open\n  1. \(checked) done\n> - \(checked) quoted\n- \(checked) other\n[ ] not a list\n```\n- [ ] code\n```")
    }
}

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

final class HTMLToMarkdownTests: XCTestCase {
    func testCommonWebMarkupBecomesMarkdown() {
        let html = """
        <html><head><style>p { color: red }</style></head><body>
        <h2>Fourier <em>series</em></h2>
        <p>A <strong>periodic</strong> signal &amp; its <a href="https://example.org/wiki">harmonics</a>.<br>Next line</p>
        <ul><li>one</li><li>two<ol><li>nested</li></ol></li></ul>
        <blockquote><p>Quoted</p></blockquote>
        <pre><code>let x = 1
        let y = 2</code></pre>
        <p>Inline <code>code</code> and <img src="https://example.org/a.png" alt="Plot"></p>
        <table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>
        <!-- a comment --><script>alert(1)</script>
        </body></html>
        """
        let expected = """
        ## Fourier *series*

        A **periodic** signal & its [harmonics](https://example.org/wiki).  
        Next line

        - one
        - two
        \t1. nested

        > Quoted

        ```
        let x = 1
        let y = 2
        ```

        Inline `code` and ![Plot](https://example.org/a.png)

        | A | B |
        | --- | --- |
        | 1 | 2 |
        """
        XCTAssertEqual(HTMLToMarkdown.markdown(from: html), expected)
    }

    func testEntitiesAndBrokenMarkup() {
        XCTAssertEqual(HTMLToMarkdown.markdown(from: "&lt;tag&gt; &#8594; &#x2192; &nbsp;x"), "<tag> → → x")
        XCTAssertEqual(HTMLToMarkdown.markdown(from: "<b>unclosed <i>tags"), "**unclosed *tags")
        XCTAssertEqual(HTMLToMarkdown.markdown(from: "a < b and c > d"), "a < b and c > d")
    }
}
