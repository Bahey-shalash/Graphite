import Foundation
import GraphiteFixtures
@testable import GraphiteCore

/// The code, parsers and patterns that answer one of the questions `MarkdownRuleParityTests`
/// asks. Each is named after the production type and member it reaches.
enum MarkdownRuleConsumer: String, CaseIterable {
    case markdownCodeRanges
    case codeFenceTracker
    case markdownStyleScanner
    case notePreviewDocumentBlocks
    case notePreviewDocumentOutline
    case livePreviewBlockScanner
    case noteFolding
    case noteBlocks
    case textColorMarkup
    case footnotes
    case markdownEditing
    case markdownSemantics
    case displayMathLines
    case readingHighlightCodeSpans
    case readingCodeSpans
    case textColorCodeSpans
    case displayMathCodeSpans
}

/// A heading as every consumer's answer is normalised: the corpus line it is on and its level.
struct HeadingAnswer: Equatable {
    let line: Int
    let level: Int
}

/// A corpus note split into lines where CommonMark ends them: at "\n", "\r\n" or a lone
/// "\r". U+2028 stays inside its line. Every consumer's answer is turned into these line
/// indices, so consumers that split lines differently are compared on the same lines.
struct SplitCorpusNote {
    struct Line {
        /// The line in the note, its line ending included.
        let range: NSRange
        let content: String
        let ending: String
    }

    let name: String
    let text: NSString
    let lines: [Line]
    /// UTF-16 length of the frontmatter, as `FrontmatterLocator` finds it.
    let frontmatterLength: Int
    /// The lines after the frontmatter. Questions are asked about these lines only.
    let bodyLineIndices: Range<Int>

    init(_ note: MarkdownCorpus.Note) {
        let text = note.text as NSString
        let lines = Self.lines(of: text)
        let frontmatterLength = FrontmatterLocator.length(in: text)
        let firstBodyLineIndex = lines.firstIndex { line in line.range.location >= frontmatterLength } ?? lines.count
        self.name = note.name
        self.text = text
        self.lines = lines
        self.frontmatterLength = frontmatterLength
        bodyLineIndices = firstBodyLineIndex..<lines.count
    }

    /// The note after the frontmatter, as the reading view and the outline are given it.
    var body: String { text.substring(from: frontmatterLength) }

    private static func lines(of text: NSString) -> [Line] {
        let lineFeed = UInt16(UInt8(ascii: "\n"))
        let carriageReturn = UInt16(UInt8(ascii: "\r"))
        var lines: [Line] = []
        var lineStart = 0
        var location = 0
        while location < text.length {
            let unit = text.character(at: location)
            guard unit == lineFeed || unit == carriageReturn else {
                location += 1
                continue
            }
            let isCarriageReturnLineFeed = unit == carriageReturn && location + 1 < text.length && text.character(at: location + 1) == lineFeed
            let endingLength = isCarriageReturnLineFeed ? 2 : 1
            lines.append(Line(range: NSRange(location: lineStart, length: location + endingLength - lineStart),
                              content: text.substring(with: NSRange(location: lineStart, length: location - lineStart)),
                              ending: text.substring(with: NSRange(location: location, length: endingLength))))
            location += endingLength
            lineStart = location
        }
        if lineStart < text.length {
            lines.append(Line(range: NSRange(location: lineStart, length: text.length - lineStart), content: text.substring(from: lineStart), ending: ""))
        }
        return lines
    }

    /// The line holding the UTF-16 offset `location` of the note.
    func lineIndex(containing location: Int) -> Int {
        lines.firstIndex { line in NSMaxRange(line.range) > location } ?? max(lines.count - 1, 0)
    }

    /// The body lines that `ranges` touch: a range touches a line it overlaps, and an empty
    /// range touches the line it starts.
    func bodyLines(touchedBy ranges: [NSRange]) -> Set<Int> {
        var touched = Set<Int>()
        for range in ranges {
            for lineIndex in bodyLineIndices {
                let lineRange = lines[lineIndex].range
                let isEmptyRangeAtLineStart = range.length == 0 && range.location == lineRange.location
                if isEmptyRangeAtLineStart || NSIntersectionRange(range, lineRange).length > 0 { touched.insert(lineIndex) }
            }
        }
        return touched
    }

    /// The quote markers and indentation a line starts with, which a probe put in its place
    /// keeps, so the probe stays in the same quote and list item.
    func containerMarkup(ofLineAt lineIndex: Int) -> String {
        let line = lines.indices.contains(lineIndex) ? lines[lineIndex] : lines.last
        return String((line?.content ?? "").prefix { character in character == " " || character == "\t" || character == ">" })
    }

    /// The note with the line at `lineIndex` replaced by `probeLines` (or the probe lines added
    /// after the last line when `lineIndex` is the line count), and where the first probe line
    /// starts. The lines before it are unchanged, so a consumer finds the same block state
    /// at the probe as at the line it replaces.
    func replacingLine(at lineIndex: Int, with probeLines: [String]) -> (text: String, probeLineRange: NSRange) {
        let fallbackEnding = lines.first { line in !line.ending.isEmpty }?.ending ?? "\n"
        var rows = lines.map { line in (content: line.content, ending: line.ending) }
        if lineIndex == rows.count {
            if let lastIndex = rows.indices.last, rows[lastIndex].ending.isEmpty { rows[lastIndex].ending = fallbackEnding }
            rows.append((content: "", ending: ""))
        }
        rows[lineIndex].content = probeLines[0]
        var insertedRows = probeLines.dropFirst().map { probeLine in (content: probeLine, ending: fallbackEnding) }
        if !insertedRows.isEmpty {
            insertedRows[insertedRows.count - 1].ending = rows[lineIndex].ending
            rows[lineIndex].ending = fallbackEnding
            rows.insert(contentsOf: insertedRows, at: lineIndex + 1)
        }
        let probeLineStart = rows[..<lineIndex].reduce(0) { length, row in length + (row.content + row.ending).utf16.count }
        return (rows.map { row in row.content + row.ending }.joined(), NSRange(location: probeLineStart, length: probeLines[0].utf16.count))
    }

    /// The body lines a consumer treats as code, fences included, for a consumer that only
    /// tells whether a probe line is code: a line is code when a probe in its place is (the
    /// block state before it), or, for a line that can open a block, when a probe on the
    /// next line is (the state after it). An opening fence is code only after itself, a
    /// closing fence only before itself.
    func codeLines(probeIsCode: (_ lineIndex: Int) throws -> Bool) rethrows -> Set<Int> {
        var isCodeBefore: [Int: Bool] = [:]
        for lineIndex in bodyLineIndices.lowerBound...bodyLineIndices.upperBound { isCodeBefore[lineIndex] = try probeIsCode(lineIndex) }
        return Set(bodyLineIndices.filter { lineIndex in
            isCodeBefore[lineIndex] == true || (canOpenBlock(lineAt: lineIndex) && isCodeBefore[lineIndex + 1] == true)
        })
    }

    /// Whether the line's first character after its quote markers and indentation is a
    /// fence character or `$`. Only such a line opens fenced code or display math; asking
    /// after any other line would ask about the next line's own indentation instead.
    private func canOpenBlock(lineAt lineIndex: Int) -> Bool {
        let content = lines[lineIndex].content.drop { character in character == " " || character == "\t" || character == ">" }
        return content.first.map { character in "`~$".contains(character) } ?? false
    }

    /// Ranges of the lines `text` splits into at "\n", the split the reading view makes.
    static func lineFeedSeparatedLineRanges(of text: String) -> [NSRange] {
        var location = 0
        return text.components(separatedBy: "\n").map { line in
            defer { location += line.utf16.count + 1 }
            return NSRange(location: location, length: line.utf16.count)
        }
    }
}

// MARK: Question 1: is this line fenced code?

enum FencedCodeAnswers {
    /// `MarkdownCodeRanges.ranges(in:)` without its code spans: `CodeFenceTracker`, which
    /// applies the fence indentation limit of `ListItemContainers`.
    static func markdownCodeRanges(_ note: SplitCorpusNote) -> Set<Int> {
        let wholeText = NSRange(location: 0, length: note.text.length)
        let codeSpans = Set(MarkdownCodeRanges.codeSpans(in: note.text, range: wholeText).map(\.range))
        return note.bodyLines(touchedBy: MarkdownCodeRanges.ranges(in: note.text).filter { range in !codeSpans.contains(range) })
    }

    /// `CodeFenceTracker` fed every line as written, as folding, footnotes and the outline feed it.
    static func codeFenceTracker(_ note: SplitCorpusNote) -> Set<Int> {
        var tracker = CodeFenceTracker()
        return Set(note.bodyLineIndices.filter { lineIndex in tracker.isCodeLine(untrimmedLine: note.lines[lineIndex].content) })
    }

    /// Lines with a `.codeBlock` span or a fence (a `.syntaxMarker` that names its block).
    static func markdownStyleScanner(_ note: SplitCorpusNote) -> Set<Int> {
        let spans = MarkdownStyleScanner.spans(in: note.text, range: NSRange(location: 0, length: note.text.length))
        let codeSpans = spans.filter { span in span.style == .codeBlock || (span.style == .syntaxMarker && span.fencedCodeBlock != nil) }
        return note.bodyLines(touchedBy: codeSpans.map(\.range))
    }

    /// The reading view's fenced blocks, each a block of its own because a plugin draws the
    /// corpus's fence language; callout bodies included.
    static func notePreviewDocumentBlocks(_ note: SplitCorpusNote) -> Set<Int> {
        let blocks = NotePreviewDocument.locatedBlocks(from: note.body, pluginCodeBlockLanguages: [MarkdownCorpus.fenceLanguage])
        let codeBlocks = ReadingBlocks.flattened(blocks).filter { block in
            if case .pluginCodeBlock = block.block { return true }
            return false
        }
        return note.bodyLines(touchedBy: codeBlocks.flatMap { block in
            ReadingBlocks.bodyRanges(startingAt: block.startOffset, lineCount: block.lineCount, in: note)
        })
    }

    static func livePreviewBlockScanner(_ note: SplitCorpusNote) -> Set<Int> {
        let blocks = LivePreviewBlockScanner.blocks(in: note.text, pluginCodeBlockLanguages: [MarkdownCorpus.fenceLanguage])
        return note.bodyLines(touchedBy: blocks.filter { block in block.kind == .pluginCodeBlock(language: MarkdownCorpus.fenceLanguage) }.map(\.range))
    }

    /// Folding does not fold a heading in code: a probe heading with a line under it folds
    /// only outside code. The line under it is a list item, which no setext underline below
    /// it can turn into a heading.
    static func noteFolding(_ note: SplitCorpusNote) -> Set<Int> {
        note.codeLines { lineIndex in
            let probe = note.replacingLine(at: lineIndex, with: ["# probe", "- probe body"])
            return !NoteFolding.regions(in: probe.text).contains { region in
                region.kind == .heading(level: 1) && region.headerRange.location == probe.probeLineRange.location
            }
        }
    }

    /// Colors are not read in code (nor in display math or indented code): a probe color
    /// makes a section only outside them.
    static func textColorMarkup(_ note: SplitCorpusNote) -> Set<Int> {
        note.codeLines { lineIndex in
            let probe = note.replacingLine(at: lineIndex, with: [note.containerMarkup(ofLineAt: lineIndex) + "~={#ff0000}probe=~"])
            return !TextColorMarkup.sections(in: probe.text as NSString).contains { section in
                NSLocationInRange(section.openingMarkerRange.location, probe.probeLineRange)
            }
        }
    }

    /// Footnote references in code are text: a probe reference counts only outside code.
    static func footnotes(_ note: SplitCorpusNote) -> Set<Int> {
        note.codeLines { lineIndex in
            let probe = note.replacingLine(at: lineIndex, with: [note.containerMarkup(ofLineAt: lineIndex) + "[^probe]"])
            return !Footnotes.parse(probe.text).references.contains { reference in reference.label == "probe" }
        }
    }

    /// Return continues a list except in code and frontmatter: a probe list item is
    /// continued only outside code.
    static func markdownEditing(_ note: SplitCorpusNote) -> Set<Int> {
        note.codeLines { lineIndex in
            let probe = note.replacingLine(at: lineIndex, with: [note.containerMarkup(ofLineAt: lineIndex) + "- probe"])
            let cursor = NSRange(location: NSMaxRange(probe.probeLineRange), length: 0)
            return MarkdownEditing.continuingList(in: probe.text as NSString, selection: cursor, indentUnit: "\t") == nil
        }
    }

    /// The index (swift-markdown) keeps no link found in code: a probe Wikilink is indexed
    /// only outside code, fenced or indented.
    static func markdownSemantics(_ note: SplitCorpusNote) throws -> Set<Int> {
        try note.codeLines { lineIndex in
            let probe = note.replacingLine(at: lineIndex, with: [note.containerMarkup(ofLineAt: lineIndex) + "[[probe]]"])
            return try !MarkdownSemantics.parse(probe.text).links.contains { link in link.isWiki && link.target == "probe" }
        }
    }
}

// MARK: Question 2: is this line a heading, and of what level?

enum HeadingAnswers {
    /// The outline's headings, each placed by `headingLineLocation(ofHeadingWithAnchor:occurrence:in:)`.
    static func notePreviewDocumentOutline(_ note: SplitCorpusNote) -> [HeadingAnswer] {
        let body = note.body
        var occurrencesByAnchor: [String: Int] = [:]
        return NotePreviewDocument.outline(of: body).map { heading in
            let occurrence = occurrencesByAnchor[heading.anchor, default: 0]
            occurrencesByAnchor[heading.anchor] = occurrence + 1
            // A heading the outline lists but cannot place is on line -1, which no other answer has.
            guard let bodyLocation = NotePreviewDocument.headingLineLocation(ofHeadingWithAnchor: heading.anchor, occurrence: occurrence, in: body) else {
                return HeadingAnswer(line: -1, level: heading.level)
            }
            return HeadingAnswer(line: note.lineIndex(containing: note.frontmatterLength + bodyLocation), level: heading.level)
        }
    }

    /// The outline's heading texts, the only part of a heading the index keeps.
    static func notePreviewDocumentOutlineTexts(_ note: SplitCorpusNote) -> [String] {
        NotePreviewDocument.outline(of: note.body).map(\.text)
    }

    static func markdownSemanticsTexts(_ note: SplitCorpusNote) throws -> [String] {
        try MarkdownSemantics.parse(note.text as String).headings
    }

    /// The ATX line rule `MarkdownHeadingSyntax.level(of:)` with the setext rule, as folding
    /// and block references compose them, on the lines outside the reference's code, math
    /// and frontmatter.
    static func markdownEditing(_ note: SplitCorpusNote) -> [HeadingAnswer] {
        lineRuleHeadings(note) { content, nextContent in
            MarkdownHeadingSyntax.level(of: content) ?? MarkdownHeadingSyntax.setextHeadingLevel(ofLine: content, nextLine: nextContent)
        }
    }

    /// The ATX line rule `MarkdownHeadingSyntax.level(of:)`, which `TextColorMarkup` asks
    /// whether a line is a heading. It has no setext rule: an underline only ends a paragraph.
    static func textColorMarkup(_ note: SplitCorpusNote) -> [HeadingAnswer] {
        lineRuleHeadings(note) { content, _ in MarkdownHeadingSyntax.level(of: content) }
    }

    static func noteFolding(_ note: SplitCorpusNote) -> [HeadingAnswer] {
        NoteFolding.regions(in: note.text as String).compactMap { region in
            guard case .heading(let level) = region.kind else { return nil }
            return HeadingAnswer(line: note.lineIndex(containing: region.headerRange.location), level: level)
        }
    }

    static func markdownStyleScanner(_ note: SplitCorpusNote) -> [HeadingAnswer] {
        var levelsByLine: [Int: Int] = [:]
        for span in MarkdownStyleScanner.spans(in: note.text, range: NSRange(location: 0, length: note.text.length)) {
            guard case .heading(let level) = span.style else { continue }
            levelsByLine[note.lineIndex(containing: span.range.location)] = level
        }
        return levelsByLine.keys.sorted().map { line in HeadingAnswer(line: line, level: levelsByLine[line] ?? 0) }
    }

    /// The reading view's heading blocks, callout bodies included.
    static func notePreviewDocumentBlocks(_ note: SplitCorpusNote) -> [HeadingAnswer] {
        ReadingBlocks.flattened(NotePreviewDocument.locatedBlocks(from: note.body)).compactMap { block in
            guard case .heading(let level, _, _) = block.block else { return nil }
            return HeadingAnswer(line: note.lineIndex(containing: note.frontmatterLength + block.startOffset), level: level)
        }
    }

    private static func lineRuleHeadings(_ note: SplitCorpusNote, level: (_ content: String, _ nextContent: String?) -> Int?) -> [HeadingAnswer] {
        let blockLines = ReferenceBlockContext.lines(of: note)
        return note.bodyLineIndices.compactMap { lineIndex in
            guard !blockLines.contains(lineIndex) else { return nil }
            let nextIndex = lineIndex + 1
            let nextContent = note.bodyLineIndices.contains(nextIndex) && !blockLines.contains(nextIndex) ? note.lines[nextIndex].content : nil
            return level(note.lines[lineIndex].content, nextContent).map { headingLevel in HeadingAnswer(line: lineIndex, level: headingLevel) }
        }
    }
}

// MARK: Question 3: is this line a thematic break?

enum ThematicBreakAnswers {
    static func markdownStyleScanner(_ note: SplitCorpusNote) -> Set<Int> {
        let spans = MarkdownStyleScanner.spans(in: note.text, range: NSRange(location: 0, length: note.text.length))
        return note.bodyLines(touchedBy: spans.filter { span in span.style == .horizontalRule }.map(\.range))
    }

    /// The line rule `MarkdownListSyntax.isThematicBreak(_:)`, which the editing commands read
    /// before a list item, on the lines outside the reference's code, math and frontmatter
    /// that do not underline a setext heading.
    static func markdownEditing(_ note: SplitCorpusNote) -> Set<Int> {
        lineRuleBreaks(note, isThematicBreak: MarkdownListSyntax.isThematicBreak)
    }

    /// The same line rule, which `TextColorMarkup` asks whether a line ends a paragraph,
    /// composed like `markdownEditing`.
    static func textColorMarkup(_ note: SplitCorpusNote) -> Set<Int> {
        lineRuleBreaks(note, isThematicBreak: MarkdownListSyntax.isThematicBreak)
    }

    static func livePreviewBlockScanner(_ note: SplitCorpusNote) -> Set<Int> {
        note.bodyLines(touchedBy: LivePreviewBlockScanner.blocks(in: note.text).filter { block in block.kind == .horizontalRule }.map(\.range))
    }

    /// A thematic break is no block, so it is read from what `NoteBlocks.blocks(in:)` leaves
    /// out: a non-blank line in no block that is no ATX heading (`MarkdownHeadingSyntax.level`,
    /// which NoteBlocks asks) and not part of a setext heading, which is a text
    /// line in no block directly over its underline in no block.
    static func noteBlocks(_ note: SplitCorpusNote) -> Set<Int> {
        let blockLines = note.bodyLines(touchedBy: NoteBlocks.blocks(in: note.text as String).map(\.range))
        func isLeftOut(_ lineIndex: Int) -> Bool {
            guard note.bodyLineIndices.contains(lineIndex), !blockLines.contains(lineIndex) else { return false }
            let content = note.lines[lineIndex].content
            return !content.trimmingCharacters(in: .whitespaces).isEmpty && MarkdownHeadingSyntax.level(of: content) == nil
        }
        return Set(note.bodyLineIndices.filter { lineIndex in isLeftOut(lineIndex) && !isLeftOut(lineIndex - 1) && !isLeftOut(lineIndex + 1) })
    }

    private static func lineRuleBreaks(_ note: SplitCorpusNote, isThematicBreak: (String) -> Bool) -> Set<Int> {
        let blockLines = ReferenceBlockContext.lines(of: note)
        return Set(note.bodyLineIndices.filter { lineIndex in
            guard !blockLines.contains(lineIndex), isThematicBreak(note.lines[lineIndex].content) else { return false }
            let previousIndex = lineIndex - 1
            guard note.bodyLineIndices.contains(previousIndex), !blockLines.contains(previousIndex) else { return true }
            return MarkdownHeadingSyntax.setextHeadingLevel(ofLine: note.lines[previousIndex].content, nextLine: note.lines[lineIndex].content) == nil
        })
    }
}

// MARK: Question 4: where does display math open and close?

enum DisplayMathAnswers {
    /// `DisplayMathLines` read line by line outside the reference's fenced code: an opener
    /// marks its lines through its closing line (or the end), and a line outside math that
    /// starts and ends with `$$` around an even count of delimiters holds a whole formula.
    static func displayMathLines(_ note: SplitCorpusNote) -> Set<Int> {
        let firstBodyLineIndex = note.bodyLineIndices.lowerBound
        let contents = note.bodyLineIndices.map { lineIndex in note.lines[lineIndex].content }
        let mathLines = DisplayMathLines(contents)
        let fencedLines = FencedCodeAnswers.markdownCodeRanges(note)
        var formulaLines = Set<Int>()
        var position = 0
        while position < contents.count {
            defer { position += 1 }
            guard !fencedLines.contains(firstBodyLineIndex + position) else { continue }
            if let opening = mathLines.opening(at: position) {
                let lastPosition = opening.closingLineIndex ?? contents.count - 1
                formulaLines.formUnion((position...lastPosition).map { linePosition in firstBodyLineIndex + linePosition })
                position = lastPosition
                continue
            }
            let trimmedContent = contents[position].trimmingCharacters(in: .whitespaces)
            let delimiterCount = DisplayMathLines.delimiterOffsets(in: trimmedContent, skippingCodeSpans: true).count
            if trimmedContent.hasPrefix("$$"), trimmedContent.hasSuffix("$$"), delimiterCount > 0, delimiterCount % 2 == 0 {
                formulaLines.insert(firstBodyLineIndex + position)
            }
        }
        return formulaLines
    }

    /// Lines styled as one `.math` span of their own (inline formulas carry their element range).
    static func markdownStyleScanner(_ note: SplitCorpusNote) -> Set<Int> {
        let spans = MarkdownStyleScanner.spans(in: note.text, range: NSRange(location: 0, length: note.text.length))
        return note.bodyLines(touchedBy: spans.filter { span in span.style == .math && span.inlineElementRange == nil }.map(\.range))
    }

    static func noteBlocks(_ note: SplitCorpusNote) -> Set<Int> {
        note.bodyLines(touchedBy: NoteBlocks.blocks(in: note.text as String).filter { block in block.kind == .math }.map(\.range))
    }

    static func notePreviewDocumentBlocks(_ note: SplitCorpusNote) -> Set<Int> {
        let ranges = ReadingBlocks.flattened(NotePreviewDocument.locatedBlocks(from: note.body)).flatMap { block -> [NSRange] in
            guard case .displayMath(let formula) = block.block else { return [] }
            let lineCount = formula.components(separatedBy: "\n").count
            return ReadingBlocks.bodyRanges(startingAt: block.startOffset, lineCount: lineCount, in: note)
        }
        return note.bodyLines(touchedBy: ranges)
    }

    static func livePreviewBlockScanner(_ note: SplitCorpusNote) -> Set<Int> {
        note.bodyLines(touchedBy: LivePreviewBlockScanner.blocks(in: note.text).filter { block in block.kind == .mathBlock }.map(\.range))
    }

    /// Colors are not read in a `$$` block (nor in code): a probe color makes a section only
    /// outside them.
    static func textColorMarkup(_ note: SplitCorpusNote) -> Set<Int> {
        FencedCodeAnswers.textColorMarkup(note)
    }
}

// MARK: Question 5: where are the inline code spans?

enum CodeSpanAnswers {
    static func markdownCodeRanges(_ note: SplitCorpusNote) -> [NSRange] {
        MarkdownCodeRanges.codeSpans(in: note.text, range: NSRange(location: 0, length: note.text.length)).map(\.range)
    }

    /// The reading view's highlight pass, which asks `MarkdownCodeRanges.codeSpans` line by
    /// line at "\n".
    static func readingHighlightCodeSpans(_ note: SplitCorpusNote) -> [NSRange] {
        codeSpansLineByLine(in: note)
    }

    /// The reading view's comment and math protection, which ask the same, line by line at "\n".
    static func readingCodeSpans(_ note: SplitCorpusNote) -> [NSRange] {
        codeSpansLineByLine(in: note)
    }

    /// `TextColorMarkup` asks `MarkdownCodeRanges.codeSpans` over the whole note.
    static func textColorCodeSpans(_ note: SplitCorpusNote) -> [NSRange] {
        MarkdownCodeRanges.codeSpans(in: note.text, range: NSRange(location: 0, length: note.text.length)).map(\.range)
    }

    /// `DisplayMathLines` asks it on the lines the reading view splits at "\n".
    static func displayMathCodeSpans(_ note: SplitCorpusNote) -> [NSRange] {
        codeSpansLineByLine(in: note)
    }

    private static func codeSpansLineByLine(in note: SplitCorpusNote) -> [NSRange] {
        SplitCorpusNote.lineFeedSeparatedLineRanges(of: note.text as String).flatMap { lineRange in
            let line = note.text.substring(with: lineRange) as NSString
            return MarkdownCodeRanges.codeSpans(in: line, range: NSRange(location: 0, length: line.length)).map { codeSpan in
                NSRange(location: lineRange.location + codeSpan.range.location, length: codeSpan.range.length)
            }
        }
    }
}

// MARK: Shared readings

/// The lines a line rule is not asked about: the reference's fenced code and display math.
/// A line rule classifies one line; the block context is its caller's.
enum ReferenceBlockContext {
    static func lines(of note: SplitCorpusNote) -> Set<Int> {
        FencedCodeAnswers.markdownCodeRanges(note).union(DisplayMathAnswers.displayMathLines(note))
    }
}

/// Reading-view blocks placed in the corpus note.
enum ReadingBlocks {
    /// The blocks with the blocks of every callout's body after their callout.
    static func flattened(_ blocks: [NotePreviewDocument.LocatedBlock]) -> [NotePreviewDocument.LocatedBlock] {
        blocks.flatMap { block in [block] + flattened(block.body) }
    }

    /// The note ranges of `lineCount` reading-view lines (split at "\n") from the one holding
    /// the body offset `startOffset`.
    static func bodyRanges(startingAt startOffset: Int, lineCount: Int, in note: SplitCorpusNote) -> [NSRange] {
        let bodyLineRanges = SplitCorpusNote.lineFeedSeparatedLineRanges(of: note.body)
        guard let firstIndex = bodyLineRanges.firstIndex(where: { lineRange in NSMaxRange(lineRange) >= startOffset }) else { return [] }
        let lastIndex = min(firstIndex + lineCount, bodyLineRanges.count) - 1
        guard firstIndex <= lastIndex else { return [] }
        return bodyLineRanges[firstIndex...lastIndex].map { lineRange in
            NSRange(location: note.frontmatterLength + lineRange.location, length: lineRange.length)
        }
    }
}
