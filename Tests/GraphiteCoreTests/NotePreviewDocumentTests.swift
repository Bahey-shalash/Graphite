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

    func testCodeBlocksInLanguagesPluginsDrawBecomeBlocksOfTheirOwn() {
        let body = "Intro\n\n```dataview table\nTABLE rating\n```\n> [!note] Tasks\n> ```tasks\n> not done\n> ```\n```swift\nlet x = 1\n```\n```Dataview\nkept as code\n```\n"
        let located = NotePreviewDocument.locatedBlocks(from: body, pluginCodeBlockLanguages: ["dataview", "tasks"])
        guard located.count == 4 else { return XCTFail("Expected 4 blocks, got \(located.map(\.block))") }
        XCTAssertEqual(located[0].block, .markdown("Intro\n"))
        // The language is the first word of the fence's info, as Obsidian gives it to processors.
        XCTAssertEqual(located[1].block, .pluginCodeBlock(language: "dataview", source: "TABLE rating"))
        XCTAssertEqual(located[1].startOffset, ("Intro\n\n" as NSString).length)
        XCTAssertEqual(located[1].lineCount, 3)
        guard case .callout(_, _, _, let calloutBody) = located[2].block else { return XCTFail("Expected a callout, got \(located[2].block)") }
        XCTAssertEqual(calloutBody, [.pluginCodeBlock(language: "tasks", source: "not done")])
        // Other languages, and a language written in other capitals, stay code.
        XCTAssertEqual(located[3].block, .markdown("```swift\nlet x = 1\n```\n```Dataview\nkept as code\n```\n"))
        XCTAssertEqual(NotePreviewDocument.blocks(from: body).filter { block in if case .pluginCodeBlock = block { true } else { false } }, [],
                       "Without plugin languages nothing changes.")
    }

    func testRunsOfMarkdownDivideIntoObsidiansSections() {
        let body = "First paragraph\ncontinues.\n\n- [ ] one\n- [x] two\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n> [!note] Title\n> Inside.\n>\n> Second.\n"
        let divided = NotePreviewDocument.dividedIntoSections(NotePreviewDocument.locatedBlocks(from: body))
        guard divided.count == 4 else { return XCTFail("Expected 4 sections, got \(divided.map(\.block))") }
        XCTAssertEqual(divided[0].block, .markdown("First paragraph\ncontinues."))
        XCTAssertEqual(divided[0].lineStartOffsets, [0, 16])
        XCTAssertEqual(divided[1].block, .markdown("- [ ] one\n- [x] two"))
        XCTAssertEqual(divided[1].startOffset, ("First paragraph\ncontinues.\n\n" as NSString).length)
        XCTAssertEqual(divided[2].block, .markdown("| a | b |\n|---|---|\n| 1 | 2 |"))
        guard case .callout(_, _, _, let calloutBody) = divided[3].block else { return XCTFail("Expected a callout") }
        XCTAssertEqual(calloutBody, [.markdown("Inside."), .markdown("Second.")])
        // Links in one section can need a definition in another, so such a run stays whole.
        let withDefinition = NotePreviewDocument.dividedIntoSections(NotePreviewDocument.locatedBlocks(from: "See [the site][1].\n\n[1]: https://example.com\n"))
        XCTAssertEqual(withDefinition.map(\.block), [.markdown("See [the site][1].\n\n[1]: https://example.com\n")])
    }

    func testRunsNestedPastTheSafeDepthStayWholeInsteadOfBeingParsedIntoSections() {
        let nestedQuotes = String(repeating: "> ", count: 64) + "deep"
        let nestedLists = String(repeating: "- ", count: 55) + "deep"
        for nestedLine in [nestedQuotes, nestedLists] {
            let body = "Before the nested line\n\(nestedLine)\n\nAfter it\n"
            // swift-markdown overflows the 512 KB stack of a Swift concurrency thread at this depth.
            let divided: [NotePreviewBlock] = onConcurrencySizedStack {
                NotePreviewDocument.dividedIntoSections(NotePreviewDocument.locatedBlocks(from: body)).map(\.block)
            }
            XCTAssertEqual(divided, [.markdown(body)])
        }
    }

    func testRunsWithinTheSafeDepthStillDivideWhenOtherRunsAreNestedTooDeeply() {
        let shallowBody = "First paragraph\n\n> quoted\n> > nested\n\n- one\n  - two\n"
        let divided: [NotePreviewBlock] = onConcurrencySizedStack {
            NotePreviewDocument.dividedIntoSections(NotePreviewDocument.locatedBlocks(from: shallowBody)).map(\.block)
        }
        XCTAssertEqual(divided, [.markdown("First paragraph"), .markdown("> quoted\n> > nested"), .markdown("- one\n  - two")])
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

    func testTableOfContentsLinksFindHeadingsByTheirGitHubSlugs() {
        XCTAssertEqual(HeadingSlug.slug(forHeading: "2. LRT7 Version — How It Works"), "2-lrt7-version--how-it-works")
        XCTAssertEqual(HeadingSlug.slug(forHeading: "2.1 Objectives"), "21-objectives")
        XCTAssertEqual(HeadingSlug.slug(forHeading: "Step 1: Open the Website!"), "step-1-open-the-website")
        XCTAssertEqual(HeadingSlug.slug(forHeading: "Équations différentielles & my_notes"), "équations-différentielles--my_notes")

        let body = "## Table of Contents\n1. [Overview](#1-overview)\n\n## 1. Overview\ntext\n### 2.1 Objectives\nmore\n## Notes\na\n## Notes\nb"
        let overviewLocation = (body as NSString).range(of: "## 1. Overview").location
        let objectivesLocation = (body as NSString).range(of: "### 2.1 Objectives").location
        let secondNotesLocation = (body as NSString).range(of: "## Notes", options: .backwards).location
        XCTAssertEqual(NotePreviewDocument.headingLineLocation(ofHeadingWithAnchor: "1-overview", in: body), overviewLocation)
        XCTAssertEqual(NotePreviewDocument.headingLineLocation(ofHeadingWithAnchor: "21-objectives", in: body), objectivesLocation)
        // GitHub numbers a repeated heading's slug.
        XCTAssertEqual(NotePreviewDocument.headingLineLocation(ofHeadingWithAnchor: "notes-1", in: body), secondNotesLocation)
        // The heading's own text still wins, and a slug no heading has finds nothing.
        XCTAssertEqual(NotePreviewDocument.headingLineLocation(ofHeadingWithAnchor: "1. overview", in: body), overviewLocation)
        XCTAssertNil(NotePreviewDocument.headingLineLocation(ofHeadingWithAnchor: "missing-heading", in: body))
        XCTAssertEqual(NotePreviewDocument.section(of: body, headingAnchor: "21-objectives"), "### 2.1 Objectives\nmore")
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
        // A marked task is its marker and its status character's code point.
        let unchecked = String(ObsidianInlineMarkup.uncheckedTaskMarker)
        let checked = String(ObsidianInlineMarkup.checkedTaskMarker)
        let markdown = "- [ ] open\n  1. [x] done\n> - [X] quoted\n- [/] other\n[ ] not a list\n```\n- [ ] code\n```"
        XCTAssertEqual(ObsidianInlineMarkup.markingTasks(in: markdown),
                       "- \(unchecked)32 open\n  1. \(checked)120 done\n> - \(checked)88 quoted\n- \(checked)47 other\n[ ] not a list\n```\n- [ ] code\n```")
    }

    /// Each block knows where its first line starts in the body, so a note keeps its place
    /// when it switches between reading and writing.
    func testEveryBlockKnowsWhereItStartsInTheBody() {
        let body = "Intro\n## Heading\nText one\nText two\n$$\nx = 1\n$$\n![[Slides.pdf]]\n> [!note] Title\n> Body\n```base\nviews: []\n```\n"
        let blocks = NotePreviewDocument.locatedBlocks(from: body)
        let text = body as NSString
        func offset(of line: String) -> Int { text.range(of: line).location }
        XCTAssertEqual(blocks.map(\.startOffset), [0, offset(of: "## Heading"), offset(of: "Text one"), offset(of: "$$\nx"),
                                                    offset(of: "![[Slides.pdf]]"), offset(of: "> [!note]"), offset(of: "```base")])
        XCTAssertEqual(blocks[2].lineStartOffsets, [offset(of: "Text one"), offset(of: "Text two")])
        // A callout's body is located in the same body.
        XCTAssertEqual(blocks[5].body.first?.startOffset, offset(of: "Body"))
    }

    /// Runs `work` on a thread with the 512 KB stack that Swift concurrency threads have,
    /// which is where reading view builds its sections.
    private func onConcurrencySizedStack<Value: Sendable>(_ work: @escaping @Sendable () -> Value) -> Value {
        let resultBox = StackThreadResultBox<Value>()
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread {
            resultBox.value = work()
            finished.signal()
        }
        thread.stackSize = 512 * 1_024
        thread.start()
        finished.wait()
        return resultBox.value!
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

/// Written once by the worker thread before it signals the semaphore, and read only after
/// the wait, so the semaphore orders the two accesses.
private final class StackThreadResultBox<Value>: @unchecked Sendable {
    var value: Value?
}
