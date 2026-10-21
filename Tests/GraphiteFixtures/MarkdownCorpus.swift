import Foundation

/// Short notes that sit on the edges of Markdown's line rules: fences, headings, thematic
/// breaks, display math, code spans and line endings. `MarkdownRuleParityTests` asks every
/// consumer of one rule to classify the same notes, so each note is named after what it
/// exercises.
///
/// Every fence carries the info word `text`, so the reading view and Live Preview, which
/// show a fence as a block of its own only when a plugin draws its language, report it.
/// Every heading has a line of text under it, so folding, which folds only a heading with
/// something under it, reports it too. No code span is written inside a fence.
public enum MarkdownCorpus {
    public struct Note: Sendable {
        public let name: String
        public let text: String
    }

    /// The info word of every fence in the corpus.
    public static let fenceLanguage = "text"

    public static let notes: [Note] = fenceNotes + mathNotes + headingNotes + ruleNotes + codeSpanNotes + lineEndingNotes

    public static func note(named name: String) -> Note? {
        notes.first { note in note.name == name }
    }

    static let fenceNotes: [Note] = [
        Note(name: "backtickFence", text: "Before\n```text\n# not a heading\n```\nAfter"),
        Note(name: "tildeFence", text: "Before\n~~~text\n# not a heading\n~~~\nAfter"),
        Note(name: "longerFenceNotClosedByShorterFence", text: "````text\n```\nstill code\n````\nAfter"),
        Note(name: "fenceIndentedOneColumn", text: " ```text\n code\n ```\nAfter"),
        Note(name: "fenceIndentedThreeColumns", text: "   ```text\n   code\n   ```\nAfter"),
        Note(name: "fenceIndentedFourColumns", text: "    ```text\n    code\n    ```\nAfter"),
        Note(name: "fenceInListItemOneColumnPastItemContent", text: "- item\n   ```text\n   code\n   ```\nAfter"),
        Note(name: "fenceInListItemThreeColumnsPastItemContent", text: "- item\n     ```text\n     code\n     ```\nAfter"),
        Note(name: "fenceInListItemFourColumnsPastItemContent", text: "- item\n\n      ```text\n      code\n      ```\nAfter"),
        Note(name: "fenceInQuote", text: "> Quote\n> ```text\n> # not a heading\n> ```\nAfter"),
        Note(name: "fenceInCallout", text: "> [!note] Title\n> ```text\n> code\n> ```\nAfter"),
        Note(name: "unclosedFence", text: "Before\n```text\ncode\n# not a heading\nmore code"),
    ]

    static let mathNotes: [Note] = [
        Note(name: "displayMathDelimitersAloneOnTheirLines", text: "Before\n\n$$\nx = 1\n$$\n\nAfter"),
        Note(name: "displayMathOnOneLine", text: "Before\n\n$$x = 1$$\n\nAfter"),
        Note(name: "escapedDollarBeforeDollarInsideDisplayMath", text: "$$\nx = \\$$\nstill math\n$$\nAfter"),
        Note(name: "displayMathDelimiterInCodeSpan", text: "Text with `$$` in code\n\n$$\ny = 2\n$$\n\nAfter"),
        Note(name: "displayMathDelimiterInFence", text: "```text\n$$\n```\nAfter\n\n$$\ny = 2\n$$\n\nEnd"),
    ]

    static let headingNotes: [Note] = [
        Note(name: "atxHeadingsIndentedZeroToThreeSpaces", text: "# Zero\nbody\n # One\nbody\n  ## Two\nbody\n   ### Three\nbody"),
        Note(name: "atxHeadingIndentedFourSpaces", text: "    # Four spaces\nbody"),
        Note(name: "atxHeadingsWithClosingSequences", text: "# Closed #\nbody\n## Closed twice ##   \nbody\n### Learning C#\nbody"),
        Note(name: "hashAloneOnItsLine", text: "#\nbody"),
        Note(name: "hashtagAtLineStart", text: "#hashtag\nbody"),
        Note(name: "setextHeadingUnderlinedWithEquals", text: "Title\n=====\nbody"),
        Note(name: "setextHeadingUnderlinedWithDashes", text: "Title\n-----\nbody"),
        Note(name: "frontmatterFollowedByHeading", text: "---\ntitle: Note\n---\n# Heading\nbody"),
    ]

    static let ruleNotes: [Note] = [
        Note(name: "dashesAfterBlankLine", text: "Paragraph\n\n---\n\nAfter"),
        Note(name: "spacedDashesIndentedFourSpaces", text: "Paragraph\n\n    - - -\n\nAfter"),
        Note(name: "asterisksUnderParagraph", text: "Paragraph\n***\nAfter"),
    ]

    static let codeSpanNotes: [Note] = [
        Note(name: "multipleBacktickCodeSpans", text: "Use ``a`b`` and ``` c `` d ```.\n`` a`==b==`c ``"),
        Note(name: "unclosedBacktick", text: "An `unclosed span\nand `a closed one`"),
        Note(name: "escapedBacktickBeforeCodeSpan", text: "\\`not code\\` and `code`"),
    ]

    static let lineEndingNotes: [Note] = [
        Note(name: "carriageReturnLineFeedLineEndings",
             text: "# Title\r\nbody\r\n```text\r\ncode\r\n```\r\n\r\n$$\r\nx\r\n$$\r\n\r\n---\r\n\r\nAfter"),
        Note(name: "loneCarriageReturnLineEndings", text: "# Title\rbody\r```text\rcode\r```\r\r$$\rx\r$$\r\r---\r\rAfter"),
        Note(name: "lineSeparatorInsideLines", text: "# Title\u{2028}continued\nbody\n```text\ncode\u{2028}```\nstill code\n```\nAfter"),
    ]
}
