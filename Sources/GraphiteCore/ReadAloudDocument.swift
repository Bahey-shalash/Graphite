import Foundation
import Markdown

/// Source and speech ranges use UTF-16. Native PDF character coordinates require
/// separate validation before these ranges can be used for PDF highlighting.
public struct ReadAloudSpan: Equatable, Sendable {
    public let speechRange: NSRange
    public let sourceRange: NSRange
    public let isVerbatim: Bool
    public var isEquation: Bool = false

    public func sourceRange(for spokenRange: NSRange) -> NSRange? {
        let overlap = NSIntersectionRange(speechRange, spokenRange)
        guard overlap.length > 0 else { return nil }
        return isVerbatim
            ? NSRange(location: sourceRange.location + overlap.location - speechRange.location, length: overlap.length)
            : sourceRange
    }
}

public struct ReadAloudPassage: Equatable, Sendable, Identifiable {
    public let id: Int
    public let text: String
    public let spans: [ReadAloudSpan]

    public func sourceRange(for spokenRange: NSRange) -> NSRange? {
        spans.compactMap { span in span.sourceRange(for: spokenRange) }.reduce(nil) { combined, range in
            combined.map { previous in NSUnionRange(previous, range) } ?? range
        }
    }
}

public struct ReadAloudDocument: Equatable, Sendable {
    public let passages: [ReadAloudPassage]
    public let notices: [String]

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

    /// Parses the whole note before filtering a range, so a selection inside code,
    /// frontmatter, or a hidden comment cannot accidentally narrate private metadata.
    public static func markdown(_ source: String, selectedRange: NSRange? = nil,
                                paletteHexByName: [String: String] = [:],
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
        for range in ObsidianInlineMarkup.commentRanges(in: source) { mask(range) }
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
            let writtenMath = original.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            let delimiter = writtenMath.hasPrefix("$$") ? "$$" : "$"
            let hasClosingDelimiter = writtenMath.count >= delimiter.count * 2 && writtenMath.hasPrefix(delimiter) && writtenMath.hasSuffix(delimiter)
            let expression = hasClosingDelimiter ? String(writtenMath.dropFirst(delimiter.count).dropLast(delimiter.count)) : ""
            let speech = hasClosingDelimiter ? try mathematicalSpeech(expression) : nil
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
        let parsed = Document(parsing: parsedSource)
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
        func flush() throws {
            passages += try split(text: passageText, spans: passageSpans, startingIdentifier: passages.count)
            passageText = ""
            passageUTF16Count = 0
            passageSpans = []
        }
        func append(_ text: String, sourceRange: NSRange, isVerbatim: Bool, isEquation: Bool = false) throws {
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
                passageSpans.append(ReadAloudSpan(speechRange: speechRange, sourceRange: spokenSourceRange, isVerbatim: isVerbatim, isEquation: isEquation))
            }
            passageText += spokenText
            passageUTF16Count += speechRange.length
        }
        for entry in leaves {
            try Task.checkCancellation()
            if entry.node is Paragraph || entry.node is Heading || entry.node is Table.Cell { try flush(); continue }
            if entry.node is SoftBreak || entry.node is LineBreak { passageText += " "; passageUTF16Count += 1; continue }
            guard let range = entry.node.range else { continue }
            let role: SourceRangeRole? = entry.node is InlineCode ? .inlineCode : nil
            var sourceRange = converter.utf16Range(of: range, role: role, containerIndex: entry.containerIndex)
            guard NSIntersectionRange(sourceRange, requestedRange).length > 0 else { continue }
            let text: String
            if let node = entry.node as? Text { text = node.string }
            else if let node = entry.node as? InlineCode { text = node.code }
            else { continue }
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
            for character in text {
                if emittedCharacterCount % 256 == 0 { try Task.checkCancellation() }
                emittedCharacterCount += 1
                let characterText = String(character)
                let characterLength = characterText.utf16.count
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
                        let decoded = Document(parsing: prepared.substring(with: entityRange)).child(at: 0)?.child(at: 0) as? Text
                        if decoded?.string == characterText { mappedRange = entityRange; hasExactMapping = true }
                    }
                }
                if !hasExactMapping, remainingLength >= characterLength,
                   prepared.substring(with: NSRange(location: sourceOffset, length: characterLength)) == characterText {
                    mappedRange = NSRange(location: sourceOffset, length: characterLength)
                    isVerbatim = true
                    hasExactMapping = true
                }
                if let math = mathByMarker[character] {
                    try append(math.speech, sourceRange: math.sourceRange, isVerbatim: false, isEquation: true)
                } else if character != "\u{2060}" {
                    guard hasExactMapping else { throw ReadAloudError.sourceMappingUnavailable }
                    try append(characterText, sourceRange: mappedRange, isVerbatim: isVerbatim)
                }
                sourceOffset = NSMaxRange(mappedRange)
            }
        }
        try flush()
        guard !passages.isEmpty else { throw ReadAloudError.noReadableText }
        return ReadAloudDocument(passages: passages, notices: notices.sorted())
    }

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

    private static func split(text: String, spans: [ReadAloudSpan], startingIdentifier: Int) throws -> [ReadAloudPassage] {
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
                                         sourceRange: sourceRange, isVerbatim: span.isVerbatim, isEquation: span.isEquation)
                }
                passages.append(ReadAloudPassage(id: startingIdentifier + passages.count, text: trimmed, spans: chunkSpans))
            }
            start = end
        }
        return passages
    }
}

public enum ReadAloudError: LocalizedError {
    case emptyRange, noReadableText, passageTooLarge, excessiveNesting, partialEquation, partialFormattedText, sourceMappingUnavailable

    public var errorDescription: String? {
        switch self {
        case .emptyRange: "Choose a non-empty passage within this document."
        case .noReadableText: "No readable text was found in this passage. Try a clearer page or another passage."
        case .passageTooLarge: "This document or passage exceeds the reader’s current size limit."
        case .excessiveNesting: "This note is nested too deeply to read safely. Choose a simpler passage."
        case .partialEquation: "Select the complete equation so it can be read accurately."
        case .partialFormattedText: "This selection cuts through escaped or formatted text. Select the complete passage."
        case .sourceMappingUnavailable: "The reader could not safely match this passage to its source. Choose another passage or use the transcript."
        }
    }
}
