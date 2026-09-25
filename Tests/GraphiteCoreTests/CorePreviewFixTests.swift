import XCTest
@testable import GraphiteCore

/// Regression tests for reading-view preparation: display math delimiters, comments,
/// headings, sections, embeds, tasks, markers and LaTeX rewriting.
final class CorePreviewDisplayMathTests: XCTestCase {
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

final class CorePreviewCommentTests: XCTestCase {
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

final class CorePreviewHeadingAndSectionTests: XCTestCase {
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
        let unchecked = String(ObsidianInlineMarkup.uncheckedTaskMarker)
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

final class CorePreviewBlockTests: XCTestCase {
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

final class CorePreviewInlineMarkupTests: XCTestCase {
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
        let unchecked = String(ObsidianInlineMarkup.uncheckedTaskMarker)
        let checked = String(ObsidianInlineMarkup.checkedTaskMarker)
        XCTAssertEqual(ObsidianInlineMarkup.markingTasks(in: "- [/] in progress\n- [-] cancelled\n- [x] done\n- [ ] open\n- [] empty"),
                       "- \(checked) in progress\n- \(checked) cancelled\n- \(checked) done\n- \(unchecked) open\n- [] empty")
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

final class CorePreviewLaTeXTests: XCTestCase {
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
