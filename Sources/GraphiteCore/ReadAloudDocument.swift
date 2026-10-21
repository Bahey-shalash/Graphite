import Foundation
import Markdown

/// Source and speech ranges use UTF-16. Native PDF character coordinates require
/// separate validation before these ranges can be used for PDF highlighting.
public struct ReadAloudSpan: Equatable, Sendable {
    public let speechRange: NSRange
    public let sourceRange: NSRange
    public let isVerbatim: Bool
    public var isEquation: Bool = false
    /// For words said differently from how they are written ("e.g." read as "for example",
    /// a web address read as "link to example.com"): the written text, so a rendered note
    /// can still match its words one by one.
    public var writtenText: String? = nil
    /// An IPA transcription for voices that accept one; the speech text is its respelling.
    public var phoneticNotation: String? = nil

    public func sourceRange(for spokenRange: NSRange) -> NSRange? {
        let overlap = NSIntersectionRange(speechRange, spokenRange)
        guard overlap.length > 0 else { return nil }
        return isVerbatim
            ? NSRange(location: sourceRange.location + overlap.location - speechRange.location, length: overlap.length)
            : sourceRange
    }
}

/// What a passage is in the document, which decides the pause after it: a heading gets a
/// longer breath than a list item, the way a person reading aloud would.
public enum ReadAloudPassageKind: Equatable, Sendable {
    case heading, paragraph, listItem, tableRow, line

    public var pauseAfterSeconds: Double {
        switch self {
        case .heading: 0.6
        case .paragraph: 0.35
        case .listItem, .tableRow, .line: 0.25
        }
    }
}

public struct ReadAloudPassage: Equatable, Sendable, Identifiable {
    public let id: Int
    public let text: String
    public let spans: [ReadAloudSpan]
    public var kind: ReadAloudPassageKind = .paragraph

    public func sourceRange(for spokenRange: NSRange) -> NSRange? {
        spans.compactMap { span in span.sourceRange(for: spokenRange) }.reduce(nil) { combined, range in
            combined.map { previous in NSUnionRange(previous, range) } ?? range
        }
    }
}

public struct ReadAloudDocument: Equatable, Sendable {
    public let passages: [ReadAloudPassage]
    public let notices: [String]
    /// A PDF page's running header or footer text (without the page number), so the next
    /// pages can skip the same text even when the layout splits it into pieces.
    public var runningText: [String] = []

    public static let maximumSourceUTF16Count = 1_048_576
    public static let maximumPassageUTF16Count = 1_200

    public static func plainText(_ source: String, selectedRange: NSRange? = nil) throws -> ReadAloudDocument {
        guard source.utf16.count <= maximumSourceUTF16Count else { throw ReadAloudError.passageTooLarge }
        let range = try readingRange(in: source, selectedRange: selectedRange)
        let selectedText = (source as NSString).substring(with: range)
        let span = ReadAloudSpan(speechRange: NSRange(location: 0, length: range.length), sourceRange: range, isVerbatim: true)
        let passages = try split(text: selectedText, spans: [span], startingIdentifier: 0)
        guard !passages.isEmpty else { throw ReadAloudError.noReadableText }
        return ReadAloudDocument(passages: passages, notices: [])
    }

    /// A PDF page's text, read the way a person reads a slide or a paper: bullet and dot-leader
    /// glyphs are not spoken, a running footer or header with the page number is skipped,
    /// a word broken across lines is joined, and a line that ends without punctuation before
    /// a new capitalized line or bullet (a title, a slide bullet) gets its own pause instead
    /// of running into the next one. Every spoken word keeps its exact place on the page.
    public static func pageText(_ source: String, selectedRange: NSRange? = nil, pageLabels: [String] = [],
                                knownRunningText: [String] = [],
                                pronunciations: ReadAloudPronunciations = .standard,
                                hyphenationDictionaryWords: Set<String> = []) throws -> ReadAloudDocument {
        let original = source as NSString
        guard original.length <= maximumSourceUTF16Count else { throw ReadAloudError.passageTooLarge }
        let requestedRange = try readingRange(in: source, selectedRange: selectedRange)
        struct Line {
            var range: NSRange
            var hasBullet: Bool
            let followsBlankLine: Bool
        }
        var lines: [Line] = []
        var followsBlankLine = false
        original.enumerateSubstrings(in: NSRange(location: 0, length: original.length), options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            var range = lineRange
            while range.length > 0, CharacterSet.whitespaces.contains(Unicode.Scalar(original.character(at: range.location)) ?? " ") {
                range = NSRange(location: range.location + 1, length: range.length - 1)
            }
            while range.length > 0, CharacterSet.whitespaces.contains(Unicode.Scalar(original.character(at: NSMaxRange(range) - 1)) ?? " ") {
                range.length -= 1
            }
            guard range.length > 0 else { followsBlankLine = true; return }
            var hasBullet = false
            if let bullet = Self.leadingBulletLength(in: original.substring(with: range)) {
                hasBullet = true
                range = NSRange(location: range.location + bullet, length: range.length - bullet)
            }
            if range.length > 0 { lines.append(Line(range: range, hasBullet: hasBullet, followsBlankLine: followsBlankLine)) }
            followsBlankLine = false
        }
        var notices = Set<String>()
        var runningText: [String] = []
        func words(_ line: Line) -> [String] {
            original.substring(with: line.range).split(whereSeparator: \.isWhitespace).map(String.init)
        }
        // A footer or header is the first or last line, short, without closing punctuation,
        // and carries the page number as a word of its own: "L05 Static logic v1.0 EE-330 2026 2".
        func isRunningHeaderOrFooter(_ line: Line) -> Bool {
            let text = original.substring(with: line.range)
            guard text.count <= 90, !pageLabels.isEmpty, let last = text.last, !".!?:;".contains(last) else { return false }
            let lineWords = words(line)
            guard let firstWord = lineWords.first, let lastWord = lineWords.last else { return false }
            if pageLabels.contains(lastWord) {
                if lineWords.count > 1 { runningText.append(lineWords.dropLast().joined(separator: " ")) }
                return true
            }
            if pageLabels.contains(firstWord) {
                if lineWords.count > 1 { runningText.append(lineWords.dropFirst().joined(separator: " ")) }
                return true
            }
            return false
        }
        // A piece of a running text found on an earlier page ("EE-330 2026" alone, when the
        // page layout split the footer), near the top or bottom of the page.
        func isKnownRunningPiece(_ line: Line) -> Bool {
            let text = words(line).joined(separator: " ")
            guard !text.isEmpty, text.count <= 60 else { return false }
            return knownRunningText.contains { known in known == text || known.hasPrefix(text + " ") || known.hasSuffix(" " + text) || known.contains(" " + text + " ") }
        }
        var removedRunningText = false
        if let last = lines.last, lines.count > 1, isRunningHeaderOrFooter(last) { lines.removeLast(); removedRunningText = true }
        if let first = lines.first, lines.count > 1, isRunningHeaderOrFooter(first) { lines.removeFirst(); removedRunningText = true }
        if !knownRunningText.isEmpty {
            for index in lines.indices.reversed() where (index >= lines.count - 4 || index < 2) && lines.count > 1 {
                if isKnownRunningPiece(lines[index]) || pageLabels.contains(words(lines[index]).joined(separator: " ")) {
                    lines.remove(at: index)
                    removedRunningText = true
                }
            }
        }
        if removedRunningText { notices.insert("Page numbers, headers and footers are skipped.") }

        var passages: [ReadAloudPassage] = []
        var unitText = ""
        var unitSpans: [ReadAloudSpan] = []
        var unitLineCount = 0
        func flushUnit() throws {
            guard !unitText.isEmpty else { return }
            let lastCharacter = unitText.trimmingCharacters(in: .whitespaces).last
            let kind: ReadAloudPassageKind = unitLineCount == 1 && !(lastCharacter.map { ".!?".contains($0) } ?? false) ? .line : .paragraph
            passages += try split(text: unitText, spans: unitSpans, startingIdentifier: passages.count, kind: kind)
            unitText = ""
            unitSpans = []
            unitLineCount = 0
        }
        func appendSource(_ range: NSRange) {
            let overlap = NSIntersectionRange(range, requestedRange)
            guard overlap.length > 0 else { return }
            let written = original.substring(with: overlap)
            var offset = 0
            for replacement in spokenReplacements(in: written, pronunciations: pronunciations)
                + [SpokenReplacement(range: NSRange(location: (written as NSString).length, length: 0), speech: "")] {
                if replacement.range.location > offset {
                    let verbatim = NSRange(location: offset, length: replacement.range.location - offset)
                    let text = (written as NSString).substring(with: verbatim)
                    unitSpans.append(ReadAloudSpan(speechRange: NSRange(location: unitText.utf16.count, length: verbatim.length),
                                                   sourceRange: NSRange(location: overlap.location + verbatim.location, length: verbatim.length), isVerbatim: true))
                    unitText += text
                }
                guard replacement.range.length > 0 else { break }
                let writtenText = (written as NSString).substring(with: replacement.range)
                unitSpans.append(ReadAloudSpan(speechRange: NSRange(location: unitText.utf16.count, length: replacement.speech.utf16.count),
                                               sourceRange: NSRange(location: overlap.location + replacement.range.location, length: replacement.range.length),
                                               isVerbatim: false, writtenText: writtenText, phoneticNotation: replacement.phoneticNotation))
                unitText += replacement.speech
                offset = NSMaxRange(replacement.range)
            }
        }
        var previous: (text: String, line: Line)?
        var previousJoinsWord = false
        for (lineIndex, line) in lines.enumerated() {
            try Task.checkCancellation()
            guard NSIntersectionRange(line.range, requestedRange).length > 0 else { continue }
            let text = original.substring(with: line.range)
            if let previous, !unitText.isEmpty {
                let previousEnd = previous.text.last ?? " "
                let startsLowercase = text.first?.isLowercase ?? false
                let continuesSentence = ",(".contains(previousEnd) || Self.lineEndHyphens.contains(previousEnd) || startsLowercase
                let endsClause = ".!?:;".contains(previousEnd)
                if line.followsBlankLine || line.hasBullet || (!endsClause && !continuesSentence) {
                    try flushUnit()
                } else if previousJoinsWord || (Self.lineEndHyphens.contains(previousEnd) && startsLowercase) {
                    // "tran-" + "sistor", or "low-" + "power": the word goes on without a space.
                } else {
                    unitText += " "
                }
            }
            previousJoinsWord = false
            var lineRange = line.range
            // A word broken across lines: "tran-|sistor" is read "transistor", without the hyphen;
            // a compound broken at its own hyphen, "low-|power", keeps it. The highlight
            // covers both halves.
            if let last = text.last, Self.lineEndHyphens.contains(last), lineIndex + 1 < lines.count, !lines[lineIndex + 1].hasBullet {
                let nextText = original.substring(with: lines[lineIndex + 1].range)
                let leftFragment = String(text.dropLast().reversed().prefix(while: \.isLetter).reversed())
                let rightFragment = String(nextText.prefix(while: \.isLetter))
                if !leftFragment.isEmpty, rightFragment.first?.isLowercase == true,
                   Self.joinsHyphenatedBreak(left: leftFragment, right: rightFragment, hyphen: last, pageText: source,
                                             dictionaryWords: hyphenationDictionaryWords) {
                    lineRange.length -= String(last).utf16.count
                    previousJoinsWord = true
                }
            }
            // Dot leaders in a table of contents (". . . . 144") are not read.
            var segmentStart = line.range.location
            for leader in Self.dotLeader.matches(in: source, range: line.range) {
                appendSource(NSRange(location: segmentStart, length: leader.range.location - segmentStart))
                unitText += " "
                segmentStart = NSMaxRange(leader.range)
            }
            appendSource(NSRange(location: segmentStart, length: NSMaxRange(lineRange) - segmentStart))
            unitLineCount += 1
            previous = (text, line)
        }
        try flushUnit()
        guard !passages.isEmpty else { throw ReadAloudError.noReadableText }
        return ReadAloudDocument(passages: passages, notices: notices.sorted(), runningText: runningText)
    }

    /// Hyphens a line can end with: ASCII, the soft hyphen, the Unicode hyphen, the
    /// non-breaking hyphen and the en dash some typesetters use.
    static let lineEndHyphens: Set<Character> = ["-", "\u{00AD}", "\u{2010}", "\u{2011}", "\u{2013}"]

    /// Whether "left-" at a line's end and "right" on the next line are one word broken by
    /// hyphenation (joined without the hyphen) rather than a compound ("low-power"). A soft
    /// hyphen always joins. A form seen with its hyphen elsewhere on the page stays a compound;
    /// a joined form seen elsewhere, or known to the system dictionary, joins.
    static func joinsHyphenatedBreak(left: String, right: String, hyphen: Character, pageText: String,
                                     dictionaryWords: Set<String>) -> Bool {
        if hyphen == "\u{00AD}" { return true }
        let joined = left + right
        let hyphenated = left + "-" + right
        if pageText.range(of: hyphenated, options: .caseInsensitive) != nil { return false }
        if dictionaryWords.contains(joined.lowercased()) { return true }
        let flattened = pageText.replacingOccurrences(of: "\n", with: " ")
        return flattened.range(of: "\\b" + NSRegularExpression.escapedPattern(for: joined) + "\\b",
                               options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The words that a hyphenated line break on this page would form if joined, for the caller
    /// to look up in the system's spelling dictionary.
    public static func hyphenationCandidates(in pageText: String) -> Set<String> {
        let lines = pageText.components(separatedBy: .newlines)
        var candidates = Set<String>()
        for (index, line) in lines.enumerated() where index + 1 < lines.count {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let last = trimmed.last, lineEndHyphens.contains(last) else { continue }
            let left = String(trimmed.dropLast().reversed().prefix(while: \.isLetter).reversed())
            let right = String(lines[index + 1].trimmingCharacters(in: .whitespaces).prefix(while: \.isLetter))
            if !left.isEmpty, right.first?.isLowercase == true { candidates.insert((left + right).lowercased()) }
        }
        return candidates
    }

    private static let dotLeader = ReadAloudDocumentPattern.dotLeader.compiled()

    /// The length of a bullet glyph and the spaces after it at the start of a line, if any.
    private static func leadingBulletLength(in line: String) -> Int? {
        guard let first = line.first else { return nil }
        let glyphs: Set<Character> = ["•", "▪", "◦", "●", "○", "■", "□", "➢", "►", "▶", "‣", "⁃", "◆", "◇", "✓", "✔", "\u{F0A7}", "\u{F0B7}", "\u{F0D8}"]
        let dashes: Set<Character> = ["-", "–", "—", "*", "·"]
        let rest = line.dropFirst()
        // Slides set in a symbol font (Wingdings) extract their bullets as letters: "n", "q",
        // "l", "§", "Ø", "ü" alone before a capitalized line ("n DRAM stores charge").
        let symbolFontBullets: Set<Character> = ["n", "q", "l", "§", "Ø", "ü", "o"]
        let isSymbolFontBullet = symbolFontBullets.contains(first) && rest.first == " "
            && (rest.dropFirst().first.map { character in character.isUppercase || character.isNumber } ?? false)
        if glyphs.contains(first) || isSymbolFontBullet || (dashes.contains(first) && (rest.first?.isWhitespace ?? false)) {
            let spaces = rest.prefix(while: \.isWhitespace)
            return String(first).utf16.count + String(spaces).utf16.count
        }
        return nil
    }

    /// Parses the whole note before filtering a range, so a selection inside code,
    /// frontmatter, or a hidden comment cannot accidentally narrate private metadata.
    public static func markdown(_ source: String, selectedRange: NSRange? = nil,
                                paletteHexByName: [String: String] = [:],
                                pronunciations: ReadAloudPronunciations = .standard,
                                hiddenRanges: [NSRange] = [],
                                mathematicalSpeech: (String) throws -> String? = MathSpeech.expression) throws -> ReadAloudDocument {
        let original = source as NSString
        guard original.length <= maximumSourceUTF16Count else { throw ReadAloudError.passageTooLarge }
        guard !MarkdownNesting.exceedsSafeDepth(source) else { throw ReadAloudError.excessiveNesting }
        let requestedRange = try readingRange(in: source, selectedRange: selectedRange)
        try Task.checkCancellation()
        let prepared = NSMutableString(string: source)
        // Masking keeps offsets and line endings intact. It never changes the note.
        func mask(_ range: NSRange) {
            let whitespace = (original.substring(with: range) as NSString)
            // A space at a line's start would turn visible prose after a removed
            // color/comment marker into indented code. Word joiners keep the same
            // columns without creating indentation and are omitted from speech.
            var units = Array(repeating: UInt16(0x2060), count: range.length)
            for index in units.indices where whitespace.character(at: index) == 10 || whitespace.character(at: index) == 13 {
                units[index] = whitespace.character(at: index)
            }
            prepared.replaceCharacters(in: range, with: String(decoding: units, as: UTF16.self))
        }
        mask(NSRange(location: 0, length: FrontmatterLocator.length(in: original)))
        // Folded away by the person (`ReadAloudFolding`): not read.
        for range in hiddenRanges where range.location >= 0 && NSMaxRange(range) <= original.length { mask(range) }
        for range in ObsidianComments.commentRanges(in: source) { mask(range) }
        let footnotes = Footnotes.parse(prepared as String)
        for definition in footnotes.definitions { mask(definition.range) }
        for reference in footnotes.references { mask(reference.range) }
        let visibleSource = prepared as String
        let styles = MarkdownStyleScanner.spans(in: prepared, range: NSRange(location: 0, length: prepared.length))
        var mathRanges: [NSRange] = []
        var lastMathWasDisplay = false
        for span in styles.filter({ span in span.style == .math }).sorted(by: { first, second in first.range.location < second.range.location }) {
            let range = span.inlineElementRange ?? span.range
            let isDisplay = span.inlineElementRange == nil
            if isDisplay, lastMathWasDisplay, let lastRange = mathRanges.last,
               original.substring(with: NSRange(location: NSMaxRange(lastRange), length: max(0, range.location - NSMaxRange(lastRange))))
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                mathRanges[mathRanges.count - 1] = NSUnionRange(lastRange, range)
            } else if mathRanges.last != range { mathRanges.append(range) }
            lastMathWasDisplay = isDisplay
        }
        var notices = Set<String>()
        var mathByMarker: [Character: (speech: String, sourceRange: NSRange)] = [:]
        let occupiedScalars = Set(source.unicodeScalars.map(\.value))
        var markerCodePoint: UInt32 = 0xE100
        for range in mathRanges {
            try Task.checkCancellation()
            guard NSIntersectionRange(range, requestedRange).length > 0 else { mask(range); continue }
            guard NSIntersectionRange(range, requestedRange) == range else { throw ReadAloudError.partialEquation }
            while occupiedScalars.contains(markerCodePoint) { markerCodePoint += 1 }
            guard markerCodePoint <= 0xF8FF, let scalar = Unicode.Scalar(markerCodePoint) else { throw ReadAloudError.passageTooLarge }
            markerCodePoint += 1
            let writtenMath = Self.removingQuoteMarkers(original.substring(with: range)).trimmingCharacters(in: .whitespacesAndNewlines)
            let delimiter = writtenMath.hasPrefix("$$") ? "$$" : "$"
            let hasClosingDelimiter = writtenMath.count >= delimiter.count * 2 && writtenMath.hasPrefix(delimiter) && writtenMath.hasSuffix(delimiter)
            let expression = hasClosingDelimiter ? String(writtenMath.dropFirst(delimiter.count).dropLast(delimiter.count)) : ""
            // A lone subscripted quantity, $V_{DD}$ or $V_{th}$, is said as engineers say it
            // ("V D D", "V threshold") rather than "V sub D D"; anything else goes to the interpreter.
            let speech = hasClosingDelimiter
                ? try (ReadAloudPronunciations.singleSubscriptedSymbol(expression) ?? mathematicalSpeech(expression)) : nil
            if speech == nil { notices.insert("Some equations are not supported yet. They are announced rather than guessed.") }
            let marker = Character(scalar)
            mathByMarker[marker] = (speech ?? "Equation not yet supported.", range)
            mask(range)
            prepared.replaceCharacters(in: NSRange(location: range.location, length: 1), with: String(marker))
        }
        // Markdown itself is handled by swift-markdown. Only Obsidian extensions
        // unknown to CommonMark are masked here, using the existing syntax scanner.
        for span in styles {
            if span.style == .calloutTitle { mask(span.range) }
            if let elementRange = span.inlineElementRange {
                let writtenElement = (visibleSource as NSString).substring(with: elementRange)
                if writtenElement.hasPrefix("![[") {
                    if NSIntersectionRange(elementRange, requestedRange).length > 0 { notices.insert("Embedded files are skipped. Open an embedded document to read it.") }
                    mask(elementRange)
                } else if writtenElement.hasPrefix("[["), span.style == .concealableMarker {
                    mask(span.range)
                } else if writtenElement.hasPrefix("=="), span.style == .concealableMarker {
                    mask(span.range)
                }
            } else if span.style == .concealableMarker, original.substring(with: span.range).trimmingCharacters(in: .whitespaces).hasPrefix("^") {
                mask(span.range)
            }
        }
        for section in TextColorMarkup.sections(in: visibleSource as NSString, paletteHexByName: paletteHexByName) {
            mask(section.openingMarkerRange)
            if let range = section.closingMarkerRange { mask(range) }
        }
        let parsedSource = prepared as String
        guard let parsed = BoundedMarkdownParser.document(parsing: parsedSource) else { throw ReadAloudError.excessiveNesting }
        var converter = MarkdownSourceLocationConverter(parsedSource)
        var leaves: [(node: any Markup, containerIndex: Int?)] = []
        var stack: [(node: any Markup, containerIndex: Int?, followsBreak: Bool)] = [(parsed, nil, false)]
        // Calibrate inline positions exactly as link indexing does, including lazy
        // quote/list continuations and UTF-8 columns in CRLF and Unicode notes.
        while let entry = stack.popLast() {
            try Task.checkCancellation()
            let node = entry.node
            let containerIndex = node is Paragraph || node is Heading ? converter.addInlineContainer(node) : entry.containerIndex
            let role: SourceRangeRole? = node is InlineCode ? .inlineCode : node is InlineHTML ? .inlineHTML : nil
            if let range = node.range, node is InlineMarkup, let containerIndex {
                converter.recordInlineRange(range, of: role, startsLineText: entry.followsBreak, inContainer: containerIndex)
            }
            if node is CodeBlock || node is HTMLBlock || node is InlineHTML || node is Markdown.Image {
                if let range = node.range {
                    let sourceRange = converter.utf16Range(of: range, role: .codeBlock, containerIndex: nil)
                    if NSIntersectionRange(sourceRange, requestedRange).length > 0 { notices.insert("Code blocks, HTML, and images are skipped in this reader.") }
                }
                continue
            }
            if node is Text || node is InlineCode || node is SoftBreak || node is LineBreak || node is Paragraph || node is Heading || node is Table.Cell {
                leaves.append((node, containerIndex))
            }
            let children = Array(node.children)
            for (childIndex, child) in children.enumerated().reversed() {
                let followsBreak = childIndex > 0 && (children[childIndex - 1] is SoftBreak || children[childIndex - 1] is LineBreak)
                stack.append((child, containerIndex, followsBreak))
            }
        }
        converter.resolveInlineLines()
        var passages: [ReadAloudPassage] = []
        var passageText = ""
        var passageUTF16Count = 0
        var passageSpans: [ReadAloudSpan] = []
        var totalSpeechUTF16Count = 0
        var passageKind = ReadAloudPassageKind.paragraph
        /// "Delay (ps): " before a table cell's words, so a row reads "Gate: NAND, Inputs: 2".
        var pendingCellPrefix: String?
        let calloutTitleLines = styles.filter { span in span.style == .calloutTitle }.map { span in original.lineRange(for: span.range) }
        func flush(as kind: ReadAloudPassageKind? = nil) throws {
            passages += try split(text: passageText, spans: passageSpans, startingIdentifier: passages.count, kind: kind ?? passageKind)
            passageText = ""
            passageUTF16Count = 0
            passageSpans = []
        }
        func appendUnmapped(_ separator: String) {
            passageText += separator
            passageUTF16Count += separator.utf16.count
        }
        func append(_ text: String, sourceRange: NSRange, isVerbatim: Bool, isEquation: Bool = false, writtenText: String? = nil,
                    phoneticNotation: String? = nil) throws {
            let overlap = NSIntersectionRange(sourceRange, requestedRange)
            guard overlap.length > 0 else { return }
            var spokenText = text
            var spokenSourceRange = sourceRange
            if isVerbatim {
                spokenText = (text as NSString).substring(with: NSRange(location: overlap.location - sourceRange.location, length: overlap.length))
                spokenSourceRange = overlap
            } else if overlap != sourceRange { throw ReadAloudError.partialFormattedText }
            guard !spokenText.isEmpty else { return }
            totalSpeechUTF16Count += spokenText.utf16.count
            guard totalSpeechUTF16Count <= maximumSourceUTF16Count * 2 else { throw ReadAloudError.passageTooLarge }
            let speechRange = NSRange(location: passageUTF16Count, length: spokenText.utf16.count)
            if isVerbatim, let lastSpan = passageSpans.last, lastSpan.isVerbatim,
               NSMaxRange(lastSpan.speechRange) == speechRange.location, NSMaxRange(lastSpan.sourceRange) == spokenSourceRange.location {
                passageSpans[passageSpans.count - 1] = ReadAloudSpan(speechRange: NSUnionRange(lastSpan.speechRange, speechRange),
                                                                  sourceRange: NSUnionRange(lastSpan.sourceRange, spokenSourceRange), isVerbatim: true)
            } else {
                passageSpans.append(ReadAloudSpan(speechRange: speechRange, sourceRange: spokenSourceRange, isVerbatim: isVerbatim,
                                                  isEquation: isEquation, writtenText: writtenText, phoneticNotation: phoneticNotation))
            }
            passageText += spokenText
            passageUTF16Count += speechRange.length
        }
        for entry in leaves {
            try Task.checkCancellation()
            if let cell = entry.node as? Table.Cell {
                // A table is read row by row; each body cell is introduced by its column's header.
                if cell.indexInParent == 0 { try flush(); passageKind = .tableRow } else if !passageText.isEmpty { appendUnmapped(", ") }
                pendingCellPrefix = nil
                if !(cell.parent is Table.Head), let table = cell.parent?.parent?.parent as? Table,
                   let header = Array(table.head.cells).dropFirst(cell.indexInParent).first {
                    let headerText = header.plainText.unicodeScalars.filter { scalar in !(0xE000...0xF8FF).contains(scalar.value) && scalar != "\u{2060}" }
                    let title = String(String.UnicodeScalarView(headerText)).trimmingCharacters(in: .whitespaces)
                    if !title.isEmpty { pendingCellPrefix = title + ": " }
                }
                continue
            }
            if entry.node is Paragraph || entry.node is Heading {
                try flush()
                passageKind = entry.node is Heading ? .heading : (entry.node.parent is ListItem ? .listItem : .paragraph)
                continue
            }
            if entry.node is SoftBreak || entry.node is LineBreak {
                // A callout's title line ends there: it is read like a heading, then its body.
                if let lastSpan = passageSpans.last, calloutTitleLines.contains(where: { line in
                    NSLocationInRange(NSMaxRange(lastSpan.sourceRange) - 1, line)
                }) {
                    try flush(as: .heading)
                } else { appendUnmapped(" ") }
                continue
            }
            guard let range = entry.node.range else { continue }
            let role: SourceRangeRole? = entry.node is InlineCode ? .inlineCode : nil
            var sourceRange = converter.utf16Range(of: range, role: role, containerIndex: entry.containerIndex)
            guard NSIntersectionRange(sourceRange, requestedRange).length > 0 else { continue }
            let text: String
            if let node = entry.node as? Text { text = node.string }
            else if let node = entry.node as? InlineCode { text = node.code }
            else { continue }
            if let prefix = pendingCellPrefix {
                pendingCellPrefix = nil
                try append(prefix, sourceRange: sourceRange, isVerbatim: false, writtenText: "")
            }
            if entry.node is InlineCode {
                try append(text, sourceRange: sourceRange, isVerbatim: false)
                continue
            }
            let writtenText = prepared.substring(with: sourceRange)
            let exactRange = (writtenText as NSString).range(of: text, options: .literal)
            if exactRange.location != NSNotFound {
                sourceRange = NSRange(location: sourceRange.location + exactRange.location, length: exactRange.length)
            }
            var sourceOffset = sourceRange.location
            var emittedCharacterCount = 0
            let replacements = spokenReplacements(in: text, pronunciations: pronunciations)
            var textOffset = 0
            var skipsUntilTextOffset = 0
            for character in text {
                if emittedCharacterCount % 256 == 0 { try Task.checkCancellation() }
                emittedCharacterCount += 1
                let characterText = String(character)
                let characterLength = characterText.utf16.count
                defer { textOffset += characterLength }
                if textOffset < skipsUntilTextOffset { continue }
                if let replacement = replacements.first(where: { replacement in replacement.range.location == textOffset }) {
                    let written = (text as NSString).substring(with: replacement.range)
                    let writtenRange = NSRange(location: sourceOffset, length: replacement.range.length)
                    if NSMaxRange(writtenRange) <= NSMaxRange(sourceRange), prepared.substring(with: writtenRange) == written {
                        try append(replacement.speech, sourceRange: writtenRange, isVerbatim: false, writtenText: written,
                                   phoneticNotation: replacement.phoneticNotation)
                        sourceOffset = NSMaxRange(writtenRange)
                        skipsUntilTextOffset = NSMaxRange(replacement.range)
                        continue
                    }
                }
                let remainingLength = max(0, NSMaxRange(sourceRange) - sourceOffset)
                var mappedRange = sourceRange
                var isVerbatim = false
                var hasExactMapping = false
                if remainingLength > characterLength, prepared.character(at: sourceOffset) == 92,
                          prepared.substring(with: NSRange(location: sourceOffset + 1, length: characterLength)) == characterText {
                    mappedRange = NSRange(location: sourceOffset, length: characterLength + 1)
                    hasExactMapping = true
                } else if remainingLength > 0, prepared.character(at: sourceOffset) == 38 {
                    let searchRange = NSRange(location: sourceOffset, length: min(remainingLength, 64))
                    let semicolon = prepared.range(of: ";", range: searchRange)
                    if semicolon.location != NSNotFound {
                        let entityRange = NSRange(location: sourceOffset, length: semicolon.location - sourceOffset + 1)
                        let decoded = BoundedMarkdownParser.document(parsing: prepared.substring(with: entityRange))?.child(at: 0)?.child(at: 0) as? Text
                        if decoded?.string == characterText { mappedRange = entityRange; hasExactMapping = true }
                    }
                }
                if !hasExactMapping, remainingLength >= characterLength,
                   prepared.substring(with: NSRange(location: sourceOffset, length: characterLength)) == characterText {
                    mappedRange = NSRange(location: sourceOffset, length: characterLength)
                    isVerbatim = true
                    hasExactMapping = true
                }
                // The parser's smart punctuation turns ' " -- --- ... into typographic marks,
                // so "Shannon's" in the note arrives as "Shannon’s". Map each mark back to the
                // plain characters actually written.
                if !hasExactMapping, let writtenForms = Self.typographicSourceForms[character] {
                    for writtenForm in writtenForms where remainingLength >= writtenForm.utf16.count
                        && prepared.substring(with: NSRange(location: sourceOffset, length: writtenForm.utf16.count)) == writtenForm {
                        mappedRange = NSRange(location: sourceOffset, length: writtenForm.utf16.count)
                        hasExactMapping = true
                        break
                    }
                }
                if let math = mathByMarker[character] {
                    try append(math.speech, sourceRange: math.sourceRange, isVerbatim: false, isEquation: true)
                } else if character != "\u{2060}" {
                    // Any other rewrite the parser makes is still read: the character is tied to
                    // the rest of its text run, so the highlight covers the run instead of
                    // pointing at a wrong word, and the note is never refused for one mark.
                    if !hasExactMapping {
                        let runRange = remainingLength > 0 ? NSRange(location: sourceOffset, length: remainingLength) : sourceRange
                        try append(characterText, sourceRange: runRange, isVerbatim: false)
                        // Stay in place, so the following characters can match exactly again.
                        continue
                    }
                    try append(characterText, sourceRange: mappedRange, isVerbatim: isVerbatim)
                }
                sourceOffset = NSMaxRange(mappedRange)
            }
        }
        try flush()
        guard !passages.isEmpty else { throw ReadAloudError.noReadableText }
        return ReadAloudDocument(passages: passages, notices: notices.sorted())
    }

    /// Written forms that a voice would read badly, with what a person would say instead.
    /// A web address is announced rather than spelled out ("h t t p s colon slash slash…");
    /// common abbreviations are expanded. Ranges are UTF-16 offsets in `text`.
    struct SpokenReplacement {
        let range: NSRange
        let speech: String
        var phoneticNotation: String? = nil
    }

    static func spokenReplacements(in text: String, pronunciations: ReadAloudPronunciations = .standard) -> [SpokenReplacement] {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        var replacements: [SpokenReplacement] = []
        if text.contains("://") || text.contains("www.") {
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            for match in detector?.matches(in: text, range: fullRange) ?? [] {
                guard let url = match.url, let host = url.host(), url.scheme == "http" || url.scheme == "https" else { continue }
                let shortHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                replacements.append(SpokenReplacement(range: match.range, speech: "link to \(shortHost)"))
            }
        }
        for (pattern, speech) in abbreviationSpeech {
            for match in pattern.matches(in: text, range: fullRange)
            where !replacements.contains(where: { existing in NSIntersectionRange(existing.range, match.range).length > 0 }) {
                replacements.append(SpokenReplacement(range: match.range, speech: speech))
            }
        }
        // Technical words, numbers with units, subscripts in prose and symbols: CMOS as
        // "see moss", "10 nm" as "10 nanometers", V_DD as "V D D", "≈" as "approximately".
        for replacement in pronunciations.replacements(in: text)
        where !replacements.contains(where: { existing in NSIntersectionRange(existing.range, replacement.range).length > 0 }) {
            replacements.append(SpokenReplacement(range: replacement.range, speech: replacement.speech,
                                                  phoneticNotation: replacement.phoneticNotation))
        }
        return replacements.sorted { first, second in first.range.location < second.range.location }
    }

    /// Only abbreviations whose meaning is unambiguous where they match; "Fig.", "Eq.",
    /// "No." and "pp." only before a number.
    private static let abbreviationSpeech: [(NSRegularExpression, String)] = [
        (ReadAloudDocumentPattern.forExampleAbbreviation.compiled(), "for example"),
        (ReadAloudDocumentPattern.thatIsAbbreviation.compiled(), "that is"),
        (ReadAloudDocumentPattern.withRespectToAbbreviation.compiled(), "with respect to"),
        (ReadAloudDocumentPattern.versusAbbreviation.compiled(), "versus"),
        (ReadAloudDocumentPattern.compareAbbreviation.compiled(), "compare"),
        (ReadAloudDocumentPattern.figuresAbbreviation.compiled(), "Figures"),
        (ReadAloudDocumentPattern.figureAbbreviation.compiled(), "Figure"),
        (ReadAloudDocumentPattern.equationAbbreviation.compiled(), "Equation"),
        (ReadAloudDocumentPattern.numberAbbreviation.compiled(), "number"),
        (ReadAloudDocumentPattern.pagesAbbreviation.compiled(), "pages")
    ]

    /// Display math inside a callout or quote carries the "> " of every line it spans; those
    /// markers belong to the quote, not to the equation.
    private static func removingQuoteMarkers(_ writtenMath: String) -> String {
        writtenMath.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            var remainder = line[...]
            while let first = remainder.first(where: { character in character != " " && character != "\t" }), first == ">" {
                remainder = remainder.drop(while: { character in character == " " || character == "\t" }).dropFirst()
            }
            return String(remainder)
        }.joined(separator: "\n")
    }

    /// The plain characters swift-markdown's smart punctuation can turn into each mark.
    private static let typographicSourceForms: [Character: [String]] = [
        "\u{2019}": ["'"], "\u{2018}": ["'"], "\u{201C}": ["\""], "\u{201D}": ["\""],
        "\u{2014}": ["---"], "\u{2013}": ["--"], "\u{2026}": ["..."]
    ]

    private static func readingRange(in source: String, selectedRange: NSRange?) throws -> NSRange {
        let original = source as NSString
        var requestedRange = selectedRange ?? NSRange(location: 0, length: original.length)
        guard requestedRange.location >= 0, requestedRange.length > 0,
              requestedRange.location <= original.length, requestedRange.length <= original.length - requestedRange.location,
              original.rangeOfComposedCharacterSequences(for: requestedRange) == requestedRange else { throw ReadAloudError.emptyRange }
        // Prose endpoints include complete words. Markdown equations are checked
        // separately; this helper does not guess their semantic boundaries.
        if selectedRange != nil {
            let originalRange = requestedRange
            source.enumerateSubstrings(in: source.startIndex..<source.endIndex, options: [.byWords, .substringNotRequired]) { _, wordRange, _, stop in
                let word = NSRange(wordRange, in: source)
                if word.location >= NSMaxRange(originalRange) { stop = true; return }
                if NSIntersectionRange(word, originalRange).length > 0 { requestedRange = NSUnionRange(requestedRange, word) }
            }
        }
        return requestedRange
    }

    private static func split(text: String, spans: [ReadAloudSpan], startingIdentifier: Int,
                              kind: ReadAloudPassageKind = .paragraph) throws -> [ReadAloudPassage] {
        let source = text as NSString
        var passages: [ReadAloudPassage] = []
        var start = 0
        while start < source.length {
            let maximumEnd = min(start + maximumPassageUTF16Count, source.length)
            var end = maximumEnd
            if maximumEnd < source.length {
                let searchRange = NSRange(location: start, length: maximumEnd - start)
                let whitespace = source.rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards, range: searchRange)
                if whitespace.location > start, whitespace.location != NSNotFound { end = whitespace.location }
                else { end = source.rangeOfComposedCharacterSequence(at: maximumEnd - 1).location }
            }
            if end <= start { end = NSMaxRange(source.rangeOfComposedCharacterSequence(at: start)) }
            guard end - start <= maximumPassageUTF16Count else { throw ReadAloudError.passageTooLarge }
            let chunkRange = NSRange(location: start, length: end - start)
            let chunk = source.substring(with: chunkRange)
            let leadingCount = chunk.prefix(while: \.isWhitespace).utf16.count
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let trimmedRange = NSRange(location: start + leadingCount, length: trimmed.utf16.count)
                let chunkSpans = spans.compactMap { span -> ReadAloudSpan? in
                    let overlap = NSIntersectionRange(span.speechRange, trimmedRange)
                    guard overlap.length > 0, let sourceRange = span.sourceRange(for: overlap) else { return nil }
                    return ReadAloudSpan(speechRange: NSRange(location: overlap.location - trimmedRange.location, length: overlap.length),
                                         sourceRange: sourceRange, isVerbatim: span.isVerbatim, isEquation: span.isEquation,
                                         writtenText: span.writtenText,
                                         phoneticNotation: overlap == span.speechRange ? span.phoneticNotation : nil)
                }
                passages.append(ReadAloudPassage(id: startingIdentifier + passages.count, text: trimmed, spans: chunkSpans, kind: kind))
            }
            start = end
        }
        return passages
    }
}

public enum ReadAloudError: LocalizedError {
    case emptyRange, noReadableText, passageTooLarge, excessiveNesting, partialEquation, partialFormattedText, sourceMappingUnavailable
    /// The device's text recognition failed on a page that has no text of its own. It is not a blank page.
    case textRecognitionUnavailable

    public var errorDescription: String? {
        switch self {
        case .emptyRange: "Choose a non-empty passage within this document."
        case .noReadableText: "No readable text was found in this passage. Try a clearer page or another passage."
        case .passageTooLarge: "This document or passage exceeds the reader’s current size limit."
        case .excessiveNesting: "This note is nested too deeply to read safely. Choose a simpler passage."
        case .partialEquation: "Select the complete equation so it can be read accurately."
        case .partialFormattedText: "This selection cuts through escaped or formatted text. Select the complete passage."
        case .sourceMappingUnavailable: "The reader could not safely match this passage to its source. Choose another passage or use the transcript."
        case .textRecognitionUnavailable: "This device could not recognize the text on this scanned page, so nothing was read. Try again, or choose a page with selectable text."
        }
    }
}

/// The constant patterns of `ReadAloudDocument`; `StaticPatternTests` compiles every case.
enum ReadAloudDocumentPattern: String, StaticPatternSet {
    case forExampleAbbreviation = #"\be\.g\."#
    case thatIsAbbreviation = #"\bi\.e\."#
    case withRespectToAbbreviation = #"\bw\.r\.t\."#
    case versusAbbreviation = #"\bvs\."#
    case compareAbbreviation = #"\bcf\."#
    case figuresAbbreviation = #"\bFigs\.(?=\s*[\d(])"#
    case figureAbbreviation = #"\bFig\.(?=\s*[\d(])"#
    case equationAbbreviation = #"\bEqs?\.(?=\s*\(?\d)"#
    case numberAbbreviation = #"\bNo\.(?=\s*\d)"#
    case pagesAbbreviation = #"\bpp\.(?=\s*\d)"#
    case dotLeader = #"(?:\s*\.){4,}\s*"#
}
