import XCTest
import GraphiteFixtures
@testable import GraphiteCore

/// Every consumer that answers the same Markdown question classifies the same corpus
/// (`MarkdownCorpus`), and the answers are compared with one reference per question. A
/// consumer that disagrees today is listed in the question's divergence table with its
/// finding and its current answer, so the steps that give each rule one owner
/// (`MarkdownLineSyntax`, `MarkdownBlockLines`) show what they change by deleting rows.
///
/// A question fails when a consumer disagrees without a row, when a row's answer is no
/// longer the consumer's answer, and when a row no longer disagrees (delete it).
final class MarkdownRuleParityTests: XCTestCase {
    func testEveryConsumerFindsTheReferenceFencedCodeLinesExceptTheRecordedDivergences() throws {
        // `TextColorMarkup` protects code and display math alike, so it is asked about code
        // only in notes without `$$`.
        try assertParity(
            reference: ParityConsumer(.markdownCodeRanges, answer: FencedCodeAnswers.markdownCodeRanges),
            consumers: [
                ParityConsumer(.codeFenceTracker, answer: FencedCodeAnswers.codeFenceTracker),
                ParityConsumer(.markdownStyleScanner, answer: FencedCodeAnswers.markdownStyleScanner),
                ParityConsumer(.notePreviewDocumentBlocks, answer: FencedCodeAnswers.notePreviewDocumentBlocks),
                ParityConsumer(.livePreviewBlockScanner, answer: FencedCodeAnswers.livePreviewBlockScanner),
                ParityConsumer(.noteFolding, answer: FencedCodeAnswers.noteFolding),
                ParityConsumer(.textColorMarkup, answersNote: { note in !note.text.contains("$$") }, answer: FencedCodeAnswers.textColorMarkup),
                ParityConsumer(.footnotes, answer: FencedCodeAnswers.footnotes),
                ParityConsumer(.markdownEditing, answer: FencedCodeAnswers.markdownEditing),
                ParityConsumer(.markdownSemantics, answer: FencedCodeAnswers.markdownSemantics),
            ],
            expectedDivergences: Self.fencedCodeDivergences,
            literal: Self.lineSetLiteral)
    }

    func testEveryConsumerFindsTheReferenceHeadingsExceptTheRecordedDivergences() throws {
        try assertParity(
            reference: ParityConsumer(.notePreviewDocumentOutline, answer: HeadingAnswers.notePreviewDocumentOutline),
            consumers: [
                ParityConsumer(.markdownEditing, answer: HeadingAnswers.markdownEditing),
                ParityConsumer(.noteFolding, answer: HeadingAnswers.noteFolding),
                ParityConsumer(.markdownStyleScanner, answer: HeadingAnswers.markdownStyleScanner),
                ParityConsumer(.notePreviewDocumentBlocks, answer: HeadingAnswers.notePreviewDocumentBlocks),
                ParityConsumer(.textColorMarkup, answer: HeadingAnswers.textColorMarkup),
            ],
            expectedDivergences: Self.headingDivergences,
            literal: Self.headingsLiteral)
        // The index keeps a heading's text only, so it is compared on the texts.
        try assertParity(
            reference: ParityConsumer(.notePreviewDocumentOutline, answer: HeadingAnswers.notePreviewDocumentOutlineTexts),
            consumers: [ParityConsumer(.markdownSemantics, answer: HeadingAnswers.markdownSemanticsTexts)],
            expectedDivergences: Self.headingTextDivergences,
            literal: Self.headingTextsLiteral)
    }

    func testEveryConsumerFindsTheReferenceThematicBreaksExceptTheRecordedDivergences() throws {
        try assertParity(
            reference: ParityConsumer(.markdownStyleScanner, answer: ThematicBreakAnswers.markdownStyleScanner),
            consumers: [
                ParityConsumer(.markdownEditing, answer: ThematicBreakAnswers.markdownEditing),
                ParityConsumer(.noteBlocks, answer: ThematicBreakAnswers.noteBlocks),
                ParityConsumer(.livePreviewBlockScanner, answer: ThematicBreakAnswers.livePreviewBlockScanner),
                ParityConsumer(.textColorMarkup, answer: ThematicBreakAnswers.textColorMarkup),
            ],
            expectedDivergences: Self.thematicBreakDivergences,
            literal: Self.lineSetLiteral)
    }

    func testEveryConsumerFindsTheReferenceDisplayMathLinesExceptTheRecordedDivergences() throws {
        // `TextColorMarkup` protects code and display math alike, so it is asked about math
        // only in notes without fences or indented lines.
        let hasNoCodeBlocks: (SplitCorpusNote) -> Bool = { note in
            !note.text.contains("```") && !note.text.contains("~~~") && !note.lines.contains { line in line.content.hasPrefix("    ") }
        }
        try assertParity(
            reference: ParityConsumer(.displayMathLines, answer: DisplayMathAnswers.displayMathLines),
            consumers: [
                ParityConsumer(.markdownStyleScanner, answer: DisplayMathAnswers.markdownStyleScanner),
                ParityConsumer(.noteBlocks, answer: DisplayMathAnswers.noteBlocks),
                ParityConsumer(.notePreviewDocumentBlocks, answer: DisplayMathAnswers.notePreviewDocumentBlocks),
                ParityConsumer(.livePreviewBlockScanner, answer: DisplayMathAnswers.livePreviewBlockScanner),
                ParityConsumer(.textColorMarkup, answersNote: hasNoCodeBlocks, answer: DisplayMathAnswers.textColorMarkup),
            ],
            expectedDivergences: Self.displayMathDivergences,
            literal: Self.lineSetLiteral)
    }

    func testEveryCodeSpanPatternFindsTheReferenceCodeSpansExceptTheRecordedDivergences() throws {
        try assertParity(
            reference: ParityConsumer(.markdownCodeRanges, answer: CodeSpanAnswers.markdownCodeRanges),
            consumers: [
                ParityConsumer(.readingHighlightCodeSpanPattern, answer: CodeSpanAnswers.readingHighlightCodeSpanPattern),
                ParityConsumer(.readingCodeSpanPattern, answer: CodeSpanAnswers.readingCodeSpanPattern),
                ParityConsumer(.textColorCodeSpanPattern, answer: CodeSpanAnswers.textColorCodeSpanPattern),
                ParityConsumer(.displayMathCodeSpanPattern, answer: CodeSpanAnswers.displayMathCodeSpanPattern),
            ],
            expectedDivergences: Self.codeSpanDivergences,
            literal: Self.rangesLiteral)
    }

    func testCorpusNotesHaveDistinctNames() {
        let names = MarkdownCorpus.notes.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }

    // MARK: Expected divergences

    /// Question 1. Reference: `MarkdownCodeRanges`, which is `CodeFenceTracker` with the fence
    /// indentation limit of `ListItemContainers`.
    static let fencedCodeDivergences: [ExpectedDivergence<Set<Int>>] = [
        // A fence indented four columns: the plain tracker has no indentation limit; colours and the index read indented code.
        ExpectedDivergence(note: "fenceIndentedFourColumns", consumer: .codeFenceTracker, finding: "BUG-MDCORE-03", currentAnswer: [0, 1, 2]),
        ExpectedDivergence(note: "fenceIndentedFourColumns", consumer: .noteFolding, finding: "BUG-MDCORE-03", currentAnswer: [0, 1, 2]),
        ExpectedDivergence(note: "fenceIndentedFourColumns", consumer: .footnotes, finding: "BUG-MDCORE-03", currentAnswer: [0, 1, 2]),
        ExpectedDivergence(note: "fenceIndentedFourColumns", consumer: .markdownEditing, finding: "BUG-MDCORE-03", currentAnswer: [0, 1, 2]),
        ExpectedDivergence(note: "fenceIndentedFourColumns", consumer: .textColorMarkup, finding: "SRP-MDCORE-03", currentAnswer: [0, 1, 2]),
        ExpectedDivergence(note: "fenceIndentedFourColumns", consumer: .markdownSemantics, finding: "LSP-MDCORE-04", currentAnswer: [0, 1, 2]),
        // A fence four columns past a list item's content: the same split, inside the item.
        ExpectedDivergence(note: "fenceInListItemFourColumnsPastItemContent", consumer: .codeFenceTracker, finding: "BUG-MDCORE-03", currentAnswer: [2, 3, 4]),
        ExpectedDivergence(note: "fenceInListItemFourColumnsPastItemContent", consumer: .noteFolding, finding: "BUG-MDCORE-03", currentAnswer: [2, 3, 4]),
        ExpectedDivergence(note: "fenceInListItemFourColumnsPastItemContent", consumer: .footnotes, finding: "BUG-MDCORE-03", currentAnswer: [2, 3, 4]),
        ExpectedDivergence(note: "fenceInListItemFourColumnsPastItemContent", consumer: .markdownEditing, finding: "BUG-MDCORE-03", currentAnswer: [2, 3, 4]),
        ExpectedDivergence(note: "fenceInListItemFourColumnsPastItemContent", consumer: .textColorMarkup, finding: "SRP-MDCORE-03", currentAnswer: [2, 3, 4]),
        ExpectedDivergence(note: "fenceInListItemFourColumnsPastItemContent", consumer: .markdownSemantics, finding: "LSP-MDCORE-04", currentAnswer: [2, 3, 4]),
        // A fence in a quote: code for the readers that follow quote depth, text for the reference.
        ExpectedDivergence(note: "fenceInQuote", consumer: .markdownStyleScanner, finding: "LSP-MDCORE-01", currentAnswer: [1, 2, 3]),
        ExpectedDivergence(note: "fenceInQuote", consumer: .textColorMarkup, finding: "LSP-MDCORE-01", currentAnswer: [1, 2, 3]),
        ExpectedDivergence(note: "fenceInQuote", consumer: .markdownEditing, finding: "LSP-MDCORE-01", currentAnswer: [1, 2, 3]),
        ExpectedDivergence(note: "fenceInQuote", consumer: .markdownSemantics, finding: "LSP-MDCORE-01", currentAnswer: [1, 2, 3]),
        // A fence in a callout: the same, and the reading view finds it in the callout's body.
        ExpectedDivergence(note: "fenceInCallout", consumer: .markdownStyleScanner, finding: "LSP-MDCORE-01", currentAnswer: [1, 2, 3]),
        ExpectedDivergence(note: "fenceInCallout", consumer: .notePreviewDocumentBlocks, finding: "LSP-MDCORE-01", currentAnswer: [1, 2, 3]),
        ExpectedDivergence(note: "fenceInCallout", consumer: .textColorMarkup, finding: "LSP-MDCORE-01", currentAnswer: [1, 2, 3]),
        ExpectedDivergence(note: "fenceInCallout", consumer: .markdownEditing, finding: "LSP-MDCORE-01", currentAnswer: [1, 2, 3]),
        ExpectedDivergence(note: "fenceInCallout", consumer: .markdownSemantics, finding: "LSP-MDCORE-01", currentAnswer: [1, 2, 3]),
        // A line indented four spaces that starts a block: indented code for colours and the index, text for the reference.
        ExpectedDivergence(note: "atxHeadingIndentedFourSpaces", consumer: .textColorMarkup, finding: "SRP-MDCORE-03", currentAnswer: [0]),
        ExpectedDivergence(note: "atxHeadingIndentedFourSpaces", consumer: .markdownSemantics, finding: "LSP-MDCORE-04", currentAnswer: [0]),
        ExpectedDivergence(note: "spacedDashesIndentedFourSpaces", consumer: .textColorMarkup, finding: "SRP-MDCORE-03", currentAnswer: [2]),
        ExpectedDivergence(note: "spacedDashesIndentedFourSpaces", consumer: .markdownSemantics, finding: "LSP-MDCORE-04", currentAnswer: [2]),
        // Lone CR line endings: the reading view splits lines at "\n" only, so it sees one line and no fence.
        ExpectedDivergence(note: "loneCarriageReturnLineEndings", consumer: .notePreviewDocumentBlocks, finding: "LSP-MDCORE-05", currentAnswer: []),
        // U+2028 inside a line: NSString lines (the reference, the editor, folding, footnotes, Return) end there and close the fence early; CommonMark readers do not.
        ExpectedDivergence(note: "lineSeparatorInsideLines", consumer: .codeFenceTracker, finding: "LSP-MDCORE-06", currentAnswer: [2, 3, 4, 5]),
        ExpectedDivergence(note: "lineSeparatorInsideLines", consumer: .notePreviewDocumentBlocks, finding: "LSP-MDCORE-06", currentAnswer: [2, 3, 4, 5]),
        ExpectedDivergence(note: "lineSeparatorInsideLines", consumer: .livePreviewBlockScanner, finding: "LSP-MDCORE-06", currentAnswer: [2, 3, 4, 5]),
        ExpectedDivergence(note: "lineSeparatorInsideLines", consumer: .markdownSemantics, finding: "LSP-MDCORE-06", currentAnswer: [2, 3, 4, 5]),
    ]

    /// Question 2. Reference: `NotePreviewDocument.outline(of:)`, the headings the outline,
    /// heading links and section embeds use.
    static let headingDivergences: [ExpectedDivergence<[HeadingAnswer]>] = [
        // `#` alone: an empty level-1 heading for the ATX line rule; the outline needs heading text.
        ExpectedDivergence(note: "hashAloneOnItsLine", consumer: .markdownEditing, finding: "LSP-MDCORE-01", currentAnswer: [HeadingAnswer(line: 0, level: 1)]),
        ExpectedDivergence(note: "hashAloneOnItsLine", consumer: .noteFolding, finding: "LSP-MDCORE-01", currentAnswer: [HeadingAnswer(line: 0, level: 1)]),
        ExpectedDivergence(note: "hashAloneOnItsLine", consumer: .textColorMarkup, finding: "LSP-MDCORE-01", currentAnswer: [HeadingAnswer(line: 0, level: 1)]),
        // Setext headings: the colour block parser ends the paragraph at the underline but has no setext heading.
        ExpectedDivergence(note: "setextHeadingUnderlinedWithEquals", consumer: .textColorMarkup, finding: "SRP-MDCORE-03", currentAnswer: []),
        ExpectedDivergence(note: "setextHeadingUnderlinedWithDashes", consumer: .textColorMarkup, finding: "SRP-MDCORE-03", currentAnswer: []),
        // Lone CR line endings: the outline splits at "\n" only, so `# Title` runs into the next lines and is no heading.
        ExpectedDivergence(note: "loneCarriageReturnLineEndings", consumer: .markdownEditing, finding: "LSP-MDCORE-05", currentAnswer: [HeadingAnswer(line: 0, level: 1)]),
        ExpectedDivergence(note: "loneCarriageReturnLineEndings", consumer: .noteFolding, finding: "LSP-MDCORE-05", currentAnswer: [HeadingAnswer(line: 0, level: 1)]),
        ExpectedDivergence(note: "loneCarriageReturnLineEndings", consumer: .markdownStyleScanner, finding: "LSP-MDCORE-05", currentAnswer: [HeadingAnswer(line: 0, level: 1)]),
        ExpectedDivergence(note: "loneCarriageReturnLineEndings", consumer: .textColorMarkup, finding: "LSP-MDCORE-05", currentAnswer: [HeadingAnswer(line: 0, level: 1)]),
        // U+2028 inside a heading: the outline's pattern stops at it and finds no heading; the line rules read the marker only.
        ExpectedDivergence(note: "lineSeparatorInsideLines", consumer: .markdownEditing, finding: "LSP-MDCORE-06", currentAnswer: [HeadingAnswer(line: 0, level: 1)]),
        ExpectedDivergence(note: "lineSeparatorInsideLines", consumer: .noteFolding, finding: "LSP-MDCORE-06", currentAnswer: [HeadingAnswer(line: 0, level: 1)]),
        ExpectedDivergence(note: "lineSeparatorInsideLines", consumer: .markdownStyleScanner, finding: "LSP-MDCORE-06", currentAnswer: [HeadingAnswer(line: 0, level: 1)]),
        ExpectedDivergence(note: "lineSeparatorInsideLines", consumer: .textColorMarkup, finding: "LSP-MDCORE-06", currentAnswer: [HeadingAnswer(line: 0, level: 1)]),
    ]

    static let headingTextDivergences: [ExpectedDivergence<[String]>] = [
        // The index (swift-markdown) reads `#` alone as an empty heading.
        ExpectedDivergence(note: "hashAloneOnItsLine", consumer: .markdownSemantics, finding: "LSP-MDCORE-01", currentAnswer: [""]),
        // The index ends lines at a lone CR and keeps a U+2028 heading whole; the outline finds neither heading.
        ExpectedDivergence(note: "loneCarriageReturnLineEndings", consumer: .markdownSemantics, finding: "LSP-MDCORE-05", currentAnswer: ["Title"]),
        ExpectedDivergence(note: "lineSeparatorInsideLines", consumer: .markdownSemantics, finding: "LSP-MDCORE-06", currentAnswer: ["Title\u{2028}continued"]),
    ]

    /// Question 3. Reference: the editor's `.horizontalRule` spans, which read past quote
    /// markers and leave a `---` under paragraph text to the setext heading.
    static let thematicBreakDivergences: [ExpectedDivergence<Set<Int>>] = [
        // `    - - -` after a blank line: the line rule allows any indentation; CommonMark reads indented code.
        ExpectedDivergence(note: "spacedDashesIndentedFourSpaces", consumer: .markdownEditing, finding: "LSP-MDCORE-01", currentAnswer: [2]),
    ]

    /// Question 4. Reference: `DisplayMathLines`, the one `$$` pairing, outside fenced code.
    static let displayMathDivergences: [ExpectedDivergence<Set<Int>>] = [
        // `$$x = 1$$` alone: colours open no block for a closed pair, and their inline pattern skips `$$`.
        ExpectedDivergence(note: "displayMathOnOneLine", consumer: .textColorMarkup, finding: "LSP-MDCORE-01", currentAnswer: []),
        // A formula line ending in `\$$`: closed there by a suffix test; DisplayMathLines counts no delimiter and closes at the next `$$`.
        ExpectedDivergence(note: "escapedDollarBeforeDollarInsideDisplayMath", consumer: .markdownStyleScanner, finding: "LSP-MDCORE-01", currentAnswer: [0, 1, 3, 4]),
        ExpectedDivergence(note: "escapedDollarBeforeDollarInsideDisplayMath", consumer: .noteBlocks, finding: "LSP-MDCORE-01", currentAnswer: [0, 1, 3, 4]),
        ExpectedDivergence(note: "escapedDollarBeforeDollarInsideDisplayMath", consumer: .textColorMarkup, finding: "LSP-MDCORE-01", currentAnswer: [0, 1, 3, 4]),
        // Lone CR line endings: the reading view sees one line, so no `$$` line of its own.
        ExpectedDivergence(note: "loneCarriageReturnLineEndings", consumer: .notePreviewDocumentBlocks, finding: "LSP-MDCORE-05", currentAnswer: []),
    ]

    /// Question 5. Reference: `MarkdownCodeRanges.codeSpans(in:range:)`, which is escape-aware
    /// and pairs runs of equal length.
    static let codeSpanDivergences: [ExpectedDivergence<[NSRange]>] = [
        // Multi-backtick spans: the highlight pass pairs single backticks only.
        ExpectedDivergence(note: "multipleBacktickCodeSpans", consumer: .readingHighlightCodeSpanPattern, finding: "LSP-MDCORE-01", currentAnswer: [NSRange(location: 5, length: 3), NSRange(location: 10, length: 7), NSRange(location: 18, length: 5), NSRange(location: 23, length: 5), NSRange(location: 33, length: 4), NSRange(location: 42, length: 4)]),
        // An escaped backtick: the copied patterns have no escape rule and open a span at it.
        ExpectedDivergence(note: "escapedBacktickBeforeCodeSpan", consumer: .readingHighlightCodeSpanPattern, finding: "LSP-MDCORE-01", currentAnswer: [NSRange(location: 1, length: 11), NSRange(location: 17, length: 6)]),
        ExpectedDivergence(note: "escapedBacktickBeforeCodeSpan", consumer: .readingCodeSpanPattern, finding: "LSP-MDCORE-01", currentAnswer: [NSRange(location: 1, length: 11), NSRange(location: 17, length: 6)]),
        ExpectedDivergence(note: "escapedBacktickBeforeCodeSpan", consumer: .textColorCodeSpanPattern, finding: "LSP-MDCORE-01", currentAnswer: [NSRange(location: 1, length: 11), NSRange(location: 17, length: 6)]),
        ExpectedDivergence(note: "escapedBacktickBeforeCodeSpan", consumer: .displayMathCodeSpanPattern, finding: "LSP-MDCORE-01", currentAnswer: [NSRange(location: 1, length: 11), NSRange(location: 17, length: 6)]),
        // Lone CR line endings: the patterns let a span cross a lone CR, joining the two fences of a block.
        ExpectedDivergence(note: "loneCarriageReturnLineEndings", consumer: .readingHighlightCodeSpanPattern, finding: "LSP-MDCORE-05", currentAnswer: [NSRange(location: 15, length: 12)]),
        ExpectedDivergence(note: "loneCarriageReturnLineEndings", consumer: .readingCodeSpanPattern, finding: "LSP-MDCORE-05", currentAnswer: [NSRange(location: 13, length: 16)]),
        ExpectedDivergence(note: "loneCarriageReturnLineEndings", consumer: .textColorCodeSpanPattern, finding: "LSP-MDCORE-05", currentAnswer: [NSRange(location: 13, length: 16)]),
        ExpectedDivergence(note: "loneCarriageReturnLineEndings", consumer: .displayMathCodeSpanPattern, finding: "LSP-MDCORE-05", currentAnswer: [NSRange(location: 13, length: 16)]),
    ]

    // MARK: Harness

    private func assertParity<Answer: Equatable & Sendable>(reference: ParityConsumer<Answer>, consumers: [ParityConsumer<Answer>],
                                                 expectedDivergences: [ExpectedDivergence<Answer>], literal: (Answer) -> String,
                                                 file: StaticString = #filePath, line: UInt = #line) throws {
        assertWellFormed(expectedDivergences, consumers: consumers, file: file, line: line)
        for corpusNote in MarkdownCorpus.notes {
            let note = SplitCorpusNote(corpusNote)
            let referenceAnswer = try reference.answer(note)
            for consumer in consumers where consumer.answersNote(note) {
                let answer = try consumer.answer(note)
                let row = expectedDivergences.first { row in row.note == note.name && row.consumer == consumer.name }
                let suggestedRow = "ExpectedDivergence(note: \"\(note.name)\", consumer: .\(consumer.name.rawValue), finding: \"\", currentAnswer: \(literal(answer)))"
                guard let row else {
                    XCTAssertEqual(answer, referenceAnswer, "\(consumer.name) disagrees with \(reference.name) (\(literal(referenceAnswer))) on \(note.name): "
                                   + suggestedRow, file: file, line: line)
                    continue
                }
                XCTAssertEqual(answer, row.currentAnswer, "\(consumer.name) changed its answer on \(note.name): \(suggestedRow)", file: file, line: line)
                XCTAssertNotEqual(answer, referenceAnswer, "\(consumer.name) agrees with \(reference.name) on \(note.name) now; delete its row", file: file, line: line)
            }
        }
    }

    /// Each row names a corpus note, a compared consumer that answers that note, and a
    /// finding of `Docs/solid/findings-index.md`; no pair has two rows.
    private func assertWellFormed<Answer: Equatable & Sendable>(_ rows: [ExpectedDivergence<Answer>], consumers: [ParityConsumer<Answer>], file: StaticString, line: UInt) {
        let findingPattern = #"^(SRP|OCP|LSP|ISP|DIP|CC|BUG)-[A-Z]+-[0-9]{2}$"#
        var seenPairs = Set<String>()
        for row in rows {
            XCTAssertTrue(seenPairs.insert(row.note + "|" + row.consumer.rawValue).inserted, "Two rows for \(row.consumer) on \(row.note)", file: file, line: line)
            XCTAssertNotNil(row.finding.range(of: findingPattern, options: .regularExpression), "Row \(row.consumer) on \(row.note) names no finding", file: file, line: line)
            guard let corpusNote = MarkdownCorpus.note(named: row.note) else {
                XCTFail("Row \(row.consumer) names no corpus note: \(row.note)", file: file, line: line)
                continue
            }
            guard let consumer = consumers.first(where: { consumer in consumer.name == row.consumer }) else {
                XCTFail("Row on \(row.note) names a consumer this question does not compare: \(row.consumer)", file: file, line: line)
                continue
            }
            XCTAssertTrue(consumer.answersNote(SplitCorpusNote(corpusNote)), "\(row.consumer) is not asked about \(row.note)", file: file, line: line)
        }
    }

    private static func lineSetLiteral(_ lines: Set<Int>) -> String {
        "[" + lines.sorted().map(String.init).joined(separator: ", ") + "]"
    }

    private static func headingsLiteral(_ headings: [HeadingAnswer]) -> String {
        "[" + headings.map { heading in "HeadingAnswer(line: \(heading.line), level: \(heading.level))" }.joined(separator: ", ") + "]"
    }

    private static func headingTextsLiteral(_ texts: [String]) -> String {
        "[" + texts.map { text in "\"\(text)\"" }.joined(separator: ", ") + "]"
    }

    private static func rangesLiteral(_ ranges: [NSRange]) -> String {
        "[" + ranges.map { range in "NSRange(location: \(range.location), length: \(range.length))" }.joined(separator: ", ") + "]"
    }
}

/// One consumer's answer to a question, normalised to the question's shape.
struct ParityConsumer<Answer: Equatable & Sendable> {
    let name: MarkdownRuleConsumer
    /// Whether the consumer's answer can be read on the note; true unless the consumer
    /// mixes this question's answer with another's.
    let answersNote: (SplitCorpusNote) -> Bool
    let answer: (SplitCorpusNote) throws -> Answer

    init(_ name: MarkdownRuleConsumer, answersNote: @escaping (SplitCorpusNote) -> Bool = { _ in true },
         answer: @escaping (SplitCorpusNote) throws -> Answer) {
        self.name = name
        self.answersNote = answersNote
        self.answer = answer
    }
}

/// A consumer's current answer on a note where it disagrees with the reference, and the
/// finding that records the disagreement.
struct ExpectedDivergence<Answer: Equatable & Sendable>: Sendable {
    let note: String
    let consumer: MarkdownRuleConsumer
    let finding: String
    let currentAnswer: Answer
}
