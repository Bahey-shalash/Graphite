import XCTest
@testable import GraphiteCore

/// Reading-view preparation: display math delimiters, comments,
/// headings, sections, embeds, tasks, markers and LaTeX rewriting.
final class NotePreviewDocumentDisplayMathTests: XCTestCase {
    func testDisplayMathOpenedInAListItemKeepsTheFollowingBlocks() {
        let blocks = NotePreviewDocument.blocks(from: "- $$\n  x^2\n  $$\n\nText after the list\n\n## Next heading\n\nMore text")
        XCTAssertEqual(blocks, [
            .markdown("- $$\n  x^2\n  $$\n\nText after the list\n"),
            .heading(level: 2, text: "Next heading", anchor: "next heading"),
            .markdown("\nMore text"),
        ])
        XCTAssertEqual(NotePreviewDocument.blocks(from: "1. $$\n   a+b\n   $$\n2. Next\n# Heading"), [
            .markdown("1. $$\n   a+b\n   $$\n2. Next"),
            .heading(level: 1, text: "Heading", anchor: "heading"),
        ])
    }

    func testDisplayMathOpenedAfterTextClosesAtItsClosingLine() {
        XCTAssertEqual(NotePreviewDocument.blocks(from: "Text $$\nE=mc^2\n$$\n## H"), [
            .markdown("Text $$\nE=mc^2\n$$"),
            .heading(level: 2, text: "H", anchor: "h"),
        ])
        XCTAssertEqual(ObsidianInlineMarkup.protectingMath(in: "Text $$\nE=mc^2\n$$ and more"), "Text $$ E\\=mc\\^2 $$ and more")
        XCTAssertEqual(ObsidianInlineMarkup.protectingMath(in: "- $$\n  x^2\n  $$\n\nText after the list"), "- $$ x\\^2 $$\n\nText after the list")
    }

    func testOneLineFormulaFollowedByTextIsInlineMath() {
        let body = "$$E=mc^2$$ is famous\nSecond paragraph line\n\nThird paragraph\n# Heading"
        XCTAssertEqual(NotePreviewDocument.blocks(from: body), [
            .markdown("$$E=mc^2$$ is famous\nSecond paragraph line\n\nThird paragraph"),
            .heading(level: 1, text: "Heading", anchor: "heading"),
        ])
        XCTAssertEqual(ObsidianPreviewText.applyingSoftLineBreaks(to: "$$E=mc^2$$ is famous\nnext line"), "$$E=mc^2$$ is famous  \nnext line  ")
    }

    func testDisplayMathBlocksOnTheirOwnLinesAreUnchanged() {
        XCTAssertEqual(NotePreviewDocument.blocks(from: "Before\n$$\nx\n$$\nAfter"), [.markdown("Before"), .displayMath("$$\nx\n$$"), .markdown("After")])
        XCTAssertEqual(NotePreviewDocument.blocks(from: "$$x$$"), [.displayMath("$$x$$")])
        // An unclosed block that starts its line runs to the end, as in Obsidian.
        XCTAssertEqual(NotePreviewDocument.blocks(from: "$$\nx\n# Not a heading"), [.displayMath("$$\nx\n# Not a heading")])
    }

    func testUnpairedDollarsAfterTextAreNotMath() {
        let body = "Costs $$5 each\n\nLater $$ text\n# Heading"
        XCTAssertEqual(NotePreviewDocument.blocks(from: body), [
            .markdown("Costs $$5 each\n\nLater $$ text"),
            .heading(level: 1, text: "Heading", anchor: "heading"),
        ])
        XCTAssertEqual(ObsidianInlineMarkup.protectingMath(in: "Costs $$5 each\n\nLater $$ text"), "Costs $$5 each\n\nLater $$ text")
    }

    func testDelimitersSkipEscapesAndCodeSpans() {
        XCTAssertEqual(DisplayMathLines.delimiterOffsets(in: "\\$$ and $$", skippingCodeSpans: false), [8])
        XCTAssertEqual(DisplayMathLines.delimiterOffsets(in: "$$$", skippingCodeSpans: false), [0])
        XCTAssertEqual(DisplayMathLines.delimiterOffsets(in: "Use `$$` to open", skippingCodeSpans: true), [])
        // Counted, the `$$` in code would open a formula closed on the next line.
        XCTAssertEqual(ObsidianInlineMarkup.protectingMath(in: "Use `$$` here\nmore $$ text"), "Use `$$` here\nmore $$ text")
    }

    func testBlockIdentifierRemovalLeavesDisplayMathAlone() {
        XCTAssertEqual(ObsidianInlineMarkup.preparedForReading("$$\nE = mc ^2\n$$", colorsEnabled: false, paletteHexByName: [:]), "$$ E \\= mc \\^2 $$")
        XCTAssertEqual(ObsidianInlineMarkup.removingBlockIdentifiers(from: "Paragraph ^id\n$$\nE = mc ^2\n$$ ^eq1\nAfter ^b"),
                       "Paragraph\n$$\nE = mc ^2\n$$\nAfter")
    }

    func testTableDisplayMathInCodeIsLeftAsWritten() {
        XCTAssertEqual(ObsidianInlineMarkup.displayMathInTableCellsMadeInline("```\n| $$x$$ |\n```\n| $$y$$ |"), "```\n| $$x$$ |\n```\n| $y$ |")
    }

    func testMathAfterALineThatIsNotAFenceIsProtected() {
        XCTAssertEqual(ObsidianInlineMarkup.protectingMath(in: "``` not`a fence\n$a*b*c$ math"), "``` not`a fence\n$a\\*b\\*c$ math")
    }
}

final class NotePreviewDocumentCommentTests: XCTestCase {
    func testCommentSpanningBlocksHidesEverythingInside() {
        let body = "Visible\n%%\nSecret draft\n# Draft heading\n![[secret.png]]\nmore secret\n%%\nVisible again"
        XCTAssertEqual(NotePreviewDocument.blocks(from: body), [.markdown("Visible\n\nVisible again")])
        XCTAssertEqual(NotePreviewDocument.outline(of: body).map(\.text), [])
        XCTAssertEqual(NotePreviewDocument.outline(of: "# Kept\n%% # Hidden %%\n# Also kept").map(\.text), ["Kept", "Also kept"])
        // A heading's anchor is the same in the outline, its section and reading view.
        let commentedHeading = "## Title %%draft%%\ntext\n## Next"
        XCTAssertEqual(NotePreviewDocument.outline(of: commentedHeading).map(\.anchor), ["title", "next"])
        XCTAssertEqual(NotePreviewDocument.section(of: commentedHeading, headingAnchor: "title"), "## Title %%draft%%\ntext")
        XCTAssertEqual(NotePreviewDocument.blocks(from: commentedHeading).first, .heading(level: 2, text: "Title", anchor: "title"))
    }

    func testCommentMarkersInCodeAreText() {
        let fencedCode = "```c\nprintf(\"%d%%\\n\", done);\nprintf(\"%%s\", name);\n```\nInline `x %% y` and `a %% b` here."
        XCTAssertEqual(ObsidianInlineMarkup.removingComments(from: fencedCode), fencedCode)
        let cells = "```python\n# %% cell one\nx = 1\n# %% cell two\ny = 2\n```"
        XCTAssertEqual(ObsidianInlineMarkup.preparedForReading(cells, colorsEnabled: false, paletteHexByName: [:]), cells)
        XCTAssertEqual(ObsidianInlineMarkup.removingComments(from: "a %%hidden%% b `%%code%%` %%\nlines\n%%c"), "a  b `%%code%%` c")
    }

    func testCommentMarkersInCodeInsideACalloutAreText() {
        let body = "> [!example]\n> ```python\n> # %% cell one\n> x = 1\n> # %% cell two\n> ```\n%%hidden%%After"
        XCTAssertEqual(NotePreviewDocument.blocks(from: body), [
            .callout(type: "example", title: "Example", folding: .notFoldable, body: [.markdown("```python\n# %% cell one\nx = 1\n# %% cell two\n```")]),
            .markdown("After"),
        ])
    }

    func testUnclosedCommentStaysVisible() {
        XCTAssertEqual(ObsidianInlineMarkup.removingComments(from: "a %% b\nc"), "a %% b\nc")
    }
}

final class NotePreviewDocumentHeadingAndSectionTests: XCTestCase {
    func testClosingHashesNeedASpaceBeforeThem() {
        let blocks = NotePreviewDocument.blocks(from: "## Learning C#\n## F#\n# Intro to C# ##\n## Learn F# and C#\n## Two ##  ")
        XCTAssertEqual(blocks, [
            .heading(level: 2, text: "Learning C#", anchor: "learning c#"),
            .heading(level: 2, text: "F#", anchor: "f#"),
            .heading(level: 1, text: "Intro to C#", anchor: "intro to c#"),
            .heading(level: 2, text: "Learn F# and C#", anchor: "learn f# and c#"),
            .heading(level: 2, text: "Two", anchor: "two"),
        ])
    }

    func testSectionIgnoresHeadingLikeLinesInCode() {
        let body = "# Setup\nIntro\n```bash\n# install dependencies\nbrew install x\n```\nAfter code\n# Next"
        XCTAssertEqual(NotePreviewDocument.section(of: body, headingAnchor: "setup"), "# Setup\nIntro\n```bash\n# install dependencies\nbrew install x\n```\nAfter code")
        XCTAssertEqual(NotePreviewDocument.section(of: "```\n# Setup\n```\nfake\n# Setup\nreal content", headingAnchor: "setup"), "# Setup\nreal content")
    }

    func testOutlineAndSectionsFollowFencesInCRLFNotes() {
        let body = "# One\r\n```\r\ncode\r\n```\r\n# Two\r\ntext\r\n"
        XCTAssertEqual(NotePreviewDocument.outline(of: body).map(\.text), ["One", "Two"])
        XCTAssertEqual(NotePreviewDocument.section(of: body, headingAnchor: "one"), "# One\r\n```\r\ncode\r\n```\r")
        // A marked task is its marker and its status character's code point.
        let unchecked = String(ObsidianInlineMarkup.uncheckedTaskMarker) + "32"
        XCTAssertEqual(ObsidianInlineMarkup.markingTasks(in: "```\r\n- [ ] code\r\n```\r\n- [ ] real"), "```\r\n- [ ] code\r\n```\r\n- \(unchecked) real")
    }

    func testSectionsAcceptObsidianHeadingPaths() {
        let body = "# Parent\n## Child\nwanted\n# Other\n## Child\nother\n## C#\nsharp"
        XCTAssertEqual(NotePreviewDocument.section(of: body, headingAnchor: "other#child"), "## Child\nother")
        XCTAssertEqual(NotePreviewDocument.section(of: body, headingAnchor: "c#"), "## C#\nsharp")
        XCTAssertNil(NotePreviewDocument.sectionIfPresent(of: body, headingAnchor: "parent#missing"))
        XCTAssertNil(NotePreviewDocument.sectionIfPresent(of: body, headingAnchor: "missing"))
        XCTAssertEqual(NotePreviewDocument.section(of: body, headingAnchor: "missing"), body)
    }
}

final class NotePreviewDocumentBlockTests: XCTestCase {
    func testRemoteImageOnItsOwnLineStaysMarkdown() {
        XCTAssertEqual(NotePreviewDocument.blocks(from: "![diagram](https://example.com/a.png)"), [.markdown("![diagram](https://example.com/a.png)")])
        guard case .embed(let embed)? = NotePreviewDocument.blocks(from: "![plot](Attachments/plot.png)").first else { return XCTFail("Expected an embed") }
        XCTAssertEqual(embed.target, "Attachments/plot.png")
    }

    func testDeeplyNestedCalloutsStopRecursingAtTheLimit() throws {
        // Before the limit, a debug build overflowed a 512 KB stack at about 200 levels.
        let depth = 400
        let body = (1...depth).map { level in String(repeating: ">", count: level) + "[!note]" }.joined(separator: "\n")
        let builtBlocks = BuiltBlocks()
        let finished = expectation(description: "blocks built")
        // The reading view builds blocks on a Swift concurrency thread, whose stack is this small.
        let thread = Thread {
            builtBlocks.blocks = NotePreviewDocument.blocks(from: body)
            finished.fulfill()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        wait(for: [finished], timeout: 60)
        var nestingDepth = 0
        var current = builtBlocks.blocks
        while case .callout(_, _, _, let calloutBody)? = current.first {
            nestingDepth += 1
            current = calloutBody
        }
        XCTAssertEqual(nestingDepth, NotePreviewDocument.maximumCalloutNestingDepth)
        guard case .markdown(let remainder)? = current.first else { return XCTFail("Expected the deeper levels as Markdown") }
        XCTAssertTrue(remainder.hasPrefix(">[!note]"))
    }
}

/// The thread writes the blocks before fulfilling its expectation, and the test reads
/// them only after waiting for it, so the two never access them at the same time.
private final class BuiltBlocks: @unchecked Sendable {
    var blocks: [NotePreviewBlock] = []
}

final class NotePreviewDocumentInlineMarkupTests: XCTestCase {
    func testMarkerCharactersInTheNoteAreNotReadAsFormatting() {
        let prepared = ObsidianInlineMarkup.preparedForReading("Nerd font glyph \u{E005} here and \u{E000}secret\u{E001} tail", colorsEnabled: true, paletteHexByName: [:])
        XCTAssertEqual(prepared, "Nerd font glyph \u{FFFD} here and \u{FFFD}secret\u{FFFD} tail")
        let markers: Set<Character> = [ObsidianInlineMarkup.colorStartMarker, ObsidianInlineMarkup.colorHexEndMarker, ObsidianInlineMarkup.colorEndMarker,
                                       ObsidianInlineMarkup.highlightStartMarker, ObsidianInlineMarkup.highlightEndMarker,
                                       ObsidianInlineMarkup.uncheckedTaskMarker, ObsidianInlineMarkup.checkedTaskMarker]
        XCTAssertFalse(prepared.contains { character in markers.contains(character) })
        // Other private-use characters are ordinary text.
        XCTAssertEqual(ObsidianInlineMarkup.preparedForReading("icon \u{E0A0}", colorsEnabled: true, paletteHexByName: [:]), "icon \u{E0A0}")
    }

    func testCustomTaskStatusesAreCheckboxes() {
        // A marked task is its marker and its status character's code point.
        let unchecked = String(ObsidianInlineMarkup.uncheckedTaskMarker)
        let checked = String(ObsidianInlineMarkup.checkedTaskMarker)
        XCTAssertEqual(ObsidianInlineMarkup.markingTasks(in: "- [/] in progress\n- [-] cancelled\n- [x] done\n- [ ] open\n- [] empty"),
                       "- \(checked)47 in progress\n- \(checked)45 cancelled\n- \(checked)120 done\n- \(unchecked)32 open\n- [] empty")
    }

    func testHighlightsSkipCodeSpans() {
        let start = String(ObsidianInlineMarkup.highlightStartMarker)
        let end = String(ObsidianInlineMarkup.highlightEndMarker)
        XCTAssertEqual(ObsidianInlineMarkup.markingHighlights(in: "==a== `==b==`\n==c=="), "\(start)a\(end) `==b==`\n\(start)c\(end)")
    }

    func testSoftLineBreaksKeepCRLFLineEndings() {
        XCTAssertEqual(ObsidianPreviewText.applyingSoftLineBreaks(to: "Line one\r\nLine two\r\n"), "Line one  \r\nLine two  \r\n")
        XCTAssertEqual(ObsidianPreviewText.applyingSoftLineBreaks(to: "one\r\ntwo\r\n```\r\ncode\r\n```\r\nthree"), "one  \r\ntwo  \r\n```\r\ncode\r\n```\r\nthree  ")
    }
}

final class NotePreviewDocumentLaTeXTests: XCTestCase {
    func testEquationArraysStayNative() {
        let eqnarray = "\\begin{eqnarray} a &=& b \\\\ c &=& d \\end{eqnarray}"
        XCTAssertEqual(LaTeXCompatibility.normalized(eqnarray), eqnarray)
        XCTAssertEqual(LaTeXCompatibility.normalized("\\begin{eqnarray*} a &=& b \\end{eqnarray*}"), "\\begin{eqnarray} a &=& b \\end{eqnarray}")
    }

    func testAlignmentsBecomeTwoColumnAligned() {
        XCTAssertEqual(LaTeXCompatibility.normalized("\\begin{align*} x = 1 \\\\ y = 2 \\end{align*}"), "\\begin{aligned} x = 1 &\\\\ y = 2 \\end{aligned}")
        XCTAssertEqual(LaTeXCompatibility.normalized("\\begin{alignat}{2} a &= b &\\quad c &= d \\end{alignat}"), "\\begin{aligned} a &= b \\qquad \\quad c = d \\end{aligned}")
        XCTAssertEqual(LaTeXCompatibility.normalized("\\begin{flalign} a &= b & c &= d \\\\[2pt] e &= f \\end{flalign}"),
                       "\\begin{aligned} a &= b \\qquad  c = d \\\\[2pt] e &= f \\end{aligned}")
        // Separators of a nested matrix belong to it.
        let matrix = "\\begin{align} A &= \\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix} \\\\ B &= 0 \\end{align}"
        XCTAssertEqual(LaTeXCompatibility.normalized(matrix), "\\begin{aligned} A &= \\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix} \\\\ B &= 0 \\end{aligned}")
        XCTAssertEqual(LaTeXCompatibility.normalized("\\begin{align} a \\& b &= c \\end{align}"), "\\begin{aligned} a \\& b &= c \\end{aligned}")
    }

    func testLabelsWithNestedBracesAreRemoved() {
        XCTAssertEqual(LaTeXCompatibility.normalized("x = 1 \\tag{\\ref{a}}"), "x = 1 ")
        XCTAssertEqual(LaTeXCompatibility.normalized("x \\tag*{1{a}} + \\label{eq:{b}} y"), "x  +  y")
        XCTAssertEqual(LaTeXCompatibility.normalized("\\tagged{x}"), "\\tagged{x}")
    }
}

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

/// Written once by the worker thread before it signals the semaphore, and read only after
/// the wait, so the semaphore orders the two accesses.
private final class StackThreadResultBox<Value>: @unchecked Sendable {
    var value: Value?
}
