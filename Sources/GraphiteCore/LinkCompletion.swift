import Foundation

/// What the text before the cursor is in the middle of typing, for Obsidian's suggestions.
public enum CompletionContext: Equatable, Sendable {
    /// Inside `[[…`: `query` is what was typed after the brackets.
    case link(LinkQuery)
    /// A `#tag` being typed; `query` excludes the `#`.
    case tag(query: String, replacementRange: NSRange)
}

/// The typed part of a link, split the way Obsidian's suggestions read it.
public struct LinkQuery: Equatable, Sendable {
    /// Everything between `[[` and the cursor.
    public let text: String
    /// The characters to replace when a suggestion is chosen: from after `[[` to the
    /// cursor, and, when the link is already closed after the cursor, the rest of it
    /// through its `]]`, which the suggestion brings back.
    public let replacementRange: NSRange
    /// Whether the link is closed after the cursor, so the replacement covers its `]]`.
    public let hasClosingBrackets: Bool
    public let isEmbed: Bool
    /// The `|alias` of a closed link the cursor is inside (`[[No|te|alias]]`), without the
    /// bar. The replacement covers it, so a suggestion without an alias of its own keeps it.
    public var writtenAlias: String? = nil

    /// The note part, before any `#`.
    public var notePart: String { String(text.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "") }
    /// After `#`, unless it starts with `^`: a heading being typed.
    public var headingQuery: String? {
        let parts = text.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[1].hasPrefix("^") else { return nil }
        return String(parts[1])
    }
    /// After `#^`: a block being typed.
    public var blockQuery: String? {
        let parts = text.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].hasPrefix("^") else { return nil }
        return String(parts[1].dropFirst())
    }
}

public enum LinkCompletion {
    /// Suggestions stop after this many characters, for text that only looks like a link.
    static let maximumQueryLength = 200
    /// A paragraph is read this far on each side of the cursor for code spans that cross lines.
    static let maximumParagraphScanLength = 4_000

    /// What is being typed at `cursor`, or nil when no suggestions apply.
    public static func context(in text: NSString, cursor: Int) -> CompletionContext? {
        guard cursor > 0, cursor <= text.length else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: cursor, length: 0))
        // Only the end of the line before the cursor can hold a query: a longer one is
        // refused anyway, and the extra characters are `[[` or `#` and the one before them.
        // A character is looked up only inside the line: an empty last line starts at the end
        // of the text, where there is no character.
        let earliestStart = cursor - maximumQueryLength - 3
        let windowStart = earliestStart > lineRange.location
            ? max(lineRange.location, text.rangeOfComposedCharacterSequence(at: earliestStart).location)
            : lineRange.location
        let beforeCursor = text.substring(with: NSRange(location: windowStart, length: cursor - windowStart))
        // The query only reads the cursor's line; the code check reads the lines before it,
        // so it runs only when there is something to suggest.
        let lineEnd = contentEnd(of: lineRange, in: text)
        guard let candidate = linkQuery(beforeCursor: beforeCursor, text: text, cursor: cursor, lineEnd: lineEnd).map(CompletionContext.link)
                ?? tagQuery(beforeCursor: beforeCursor, text: text, cursor: cursor, lineEnd: lineEnd),
              !isInCode(text, lineRange: lineRange, cursor: cursor) else { return nil }
        return candidate
    }

    /// The end of a line without its line ending.
    private static func contentEnd(of lineRange: NSRange, in text: NSString) -> Int {
        var end = NSMaxRange(lineRange)
        while end > lineRange.location, [0x0A, 0x0D].contains(text.character(at: end - 1)) { end -= 1 }
        return end
    }

    private static func linkQuery(beforeCursor: String, text: NSString, cursor: Int, lineEnd: Int) -> LinkQuery? {
        let line = beforeCursor as NSString
        let opening = line.range(of: "[[", options: .backwards)
        guard opening.location != NSNotFound else { return nil }
        let openingLocation = cursor - line.length + opening.location
        // `\[[` is text, not a link.
        guard !MarkdownLinkSyntax.isEscaped(openingLocation, in: text) else { return nil }
        let queryStart = NSMaxRange(opening)
        let query = line.substring(from: queryStart)
        // Closed already, or past the alias bar: nothing to suggest.
        guard !query.contains("]]"), !query.contains("|"), query.utf16.count <= maximumQueryLength else { return nil }
        let isEmbed = openingLocation > 0 && text.character(at: openingLocation - 1) == 33 // "!"
        let replacementStart = openingLocation + 2
        guard let closing = closingBrackets(after: cursor, in: text, lineEnd: lineEnd) else {
            return LinkQuery(text: query, replacementRange: NSRange(location: replacementStart, length: cursor - replacementStart), hasClosingBrackets: false, isEmbed: isEmbed)
        }
        // The rest of the link after the cursor is replaced too, or it would be left behind
        // after the chosen target (`[[Chosen]]te]]`).
        let rest = text.substring(with: NSRange(location: cursor, length: closing - cursor))
        let writtenAlias = rest.firstIndex(of: "|").map { bar in String(rest[rest.index(after: bar)...]) }
        return LinkQuery(text: query, replacementRange: NSRange(location: replacementStart, length: closing + 2 - replacementStart),
                         hasClosingBrackets: true, isEmbed: isEmbed, writtenAlias: writtenAlias)
    }

    /// Where the `]]` closing the link around the cursor starts, when the link is closed on
    /// its line before another one opens.
    private static func closingBrackets(after cursor: Int, in text: NSString, lineEnd: Int) -> Int? {
        let searchRange = NSRange(location: cursor, length: min(lineEnd, cursor + maximumQueryLength + 2) - cursor)
        guard searchRange.length >= 2 else { return nil }
        let closing = text.range(of: "]]", options: .literal, range: searchRange)
        guard closing.location != NSNotFound else { return nil }
        let nextOpening = text.range(of: "[[", options: .literal, range: NSRange(location: cursor, length: closing.location - cursor))
        return nextOpening.location == NSNotFound ? closing.location : nil
    }

    /// A tag being typed, as `TagSyntax` (the index's rule) reads tags: after any character
    /// that does not continue a word or a path, with letters, numbers, emoji, `_`, `-` and `/`.
    private static func tagQuery(beforeCursor: String, text: NSString, cursor: Int, lineEnd: Int) -> CompletionContext? {
        // Digits alone are not a tag yet, but may start one ("#2026-exam"), so they still get
        // suggestions: a letter after the cursor makes any tag start a complete tag.
        let probe = (beforeCursor + "a") as NSString
        guard let match = TagSyntax.pattern.matches(in: probe as String, range: NSRange(location: 0, length: probe.length)).last,
              NSMaxRange(match.range) == probe.length else { return nil }
        let queryRange = NSRange(location: match.range(at: 1).location, length: match.range(at: 1).length - 1)
        guard queryRange.length > 0, queryRange.length <= maximumQueryLength else { return nil }
        let replacementLocation = cursor - queryRange.length
        // The rest of a tag the cursor is inside (`#ta|g`) is replaced too.
        let followingLength = tagCharacterCount(after: cursor, in: text, lineEnd: lineEnd)
        return .tag(query: probe.substring(with: queryRange), replacementRange: NSRange(location: replacementLocation, length: queryRange.length + followingLength))
    }

    /// How many UTF-16 units of tag characters follow `location` on its line.
    private static func tagCharacterCount(after location: Int, in text: NSString, lineEnd: Int) -> Int {
        let length = min(lineEnd, location + maximumQueryLength) - location
        guard length > 0 else { return 0 }
        let following = text.substring(with: text.rangeOfComposedCharacterSequences(for: NSRange(location: location, length: length)))
        // `#a` in front makes the characters a tag whatever they start with.
        let probe = ("#a" + following) as NSString
        guard let match = TagSyntax.pattern.firstMatch(in: probe as String, range: NSRange(location: 0, length: probe.length)),
              match.range.location == 0 else { return 0 }
        return match.range(at: 1).length - 1
    }

    /// Whether the cursor is in code or an HTML comment: inline code on its line or across
    /// the lines of its paragraph, or a fenced block, including one in a block quote. Earlier
    /// lines are read only in notes of a reasonable size, to keep typing fast.
    private static func isInCode(_ text: NSString, lineRange: NSRange, cursor: Int) -> Bool {
        let line = text.substring(with: lineRange)
        let localCursor = cursor - lineRange.location
        let codeRanges = MarkdownCodeRanges.ranges(in: line as NSString)
        if codeRanges.contains(where: { range in range.location < localCursor && localCursor <= NSMaxRange(range) }) { return true }
        guard lineRange.location <= maximumScannedLengthForFences else { return false }
        if isInCodeSpanAcrossLines(text, cursor: cursor) { return true }
        return isInFenceOrComment(text, lineRange: lineRange, cursor: cursor)
    }

    /// Whether a code span that crosses a line ending holds the cursor. Code spans can run
    /// over several lines of one paragraph, which ends at a blank line.
    private static func isInCodeSpanAcrossLines(_ text: NSString, cursor: Int) -> Bool {
        let paragraph = paragraphRange(around: cursor, in: text)
        guard text.range(of: "`", options: .literal, range: paragraph).location != NSNotFound else { return false }
        var index = paragraph.location
        let limit = NSMaxRange(paragraph)
        while index < limit, index < cursor {
            let character = text.character(at: index)
            if character == 0x5C /* \ */ { index += 2; continue }
            guard character == 0x60 /* ` */ else { index += 1; continue }
            let runLength = MarkdownLinkSyntax.backtickRunLength(at: index, in: text, limit: limit)
            guard let spanEnd = MarkdownLinkSyntax.codeSpanEnd(openingRunAt: index, runLength: runLength, in: text, limit: limit) else {
                index += runLength
                continue
            }
            if index < cursor && cursor <= spanEnd { return true }
            index = spanEnd
        }
        return false
    }

    /// The lines around `location` up to a blank line or a fence on either side, at most
    /// `maximumParagraphScanLength` away.
    private static func paragraphRange(around location: Int, in text: NSString) -> NSRange {
        let lowerLimit = max(0, location - maximumParagraphScanLength), upperLimit = min(text.length, location + maximumParagraphScanLength)
        let cursorLine = text.lineRange(for: NSRange(location: location, length: 0))
        var start = cursorLine.location
        while start > lowerLimit {
            let previousLine = text.lineRange(for: NSRange(location: start - 1, length: 0))
            guard !endsParagraph(text.substring(with: previousLine)) else { break }
            start = previousLine.location
        }
        var end = NSMaxRange(cursorLine)
        while end < upperLimit {
            let nextLine = text.lineRange(for: NSRange(location: end, length: 0))
            guard !endsParagraph(text.substring(with: nextLine)) else { break }
            end = NSMaxRange(nextLine)
        }
        let paragraphStart = max(start, lowerLimit)
        return NSRange(location: paragraphStart, length: min(end, upperLimit) - paragraphStart)
    }

    private static func endsParagraph(_ line: String) -> Bool {
        let content = quoteMarkers(in: line, maximumDepth: Int.max).content.trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty || CodeFence.opening(content) != nil
    }

    /// Whether the lines before the cursor's line leave a fenced block or an HTML comment
    /// open where the cursor is. A fence inside a block quote (`> ` + three backticks) is
    /// read without its quote markers and ends with the quote.
    private static func isInFenceOrComment(_ text: NSString, lineRange: NSRange, cursor: Int) -> Bool {
        let linePrefix = text.substring(with: NSRange(location: lineRange.location, length: cursor - lineRange.location))
        var previousLines = text.substring(to: lineRange.location)
        var openBlocks = OpenBlocks()
        previousLines.withUTF8 { bytes in openBlocks.read(bytes) }
        if openBlocks.fenceTracker.isInsideFence { return quoteMarkers(in: linePrefix, maximumDepth: Int.max).depth >= openBlocks.fenceQuoteDepth }
        return endsInsideComment(linePrefix, startsInside: openBlocks.isInsideComment)
    }

    /// Fenced code and HTML comments left open by a run of lines, read as UTF-8 bytes. This
    /// runs on the main thread for each keystroke while a suggestion is open, over up to
    /// `maximumScannedLengthForFences` characters, so a line becomes a String only when its
    /// first character could open or close a fence, or it holds a comment marker.
    private struct OpenBlocks {
        var fenceTracker = CodeFenceTracker()
        /// How many block quote markers the open fence is inside.
        var fenceQuoteDepth = 0
        var isInsideComment = false

        private static let space: UInt8 = 0x20, tab: UInt8 = 0x09, lineFeed: UInt8 = 0x0A, carriageReturn: UInt8 = 0x0D
        private static let greaterThan: UInt8 = 0x3E, backtick: UInt8 = 0x60, tilde: UInt8 = 0x7E

        mutating func read(_ bytes: UnsafeBufferPointer<UInt8>) {
            var lineStart = 0
            while lineStart < bytes.count {
                var lineEnd = lineStart
                var nextLineStart = bytes.count
                // Line endings as NSString reads them: \n, \r, \r\n, U+0085, U+2028 and U+2029.
                while lineEnd < bytes.count {
                    let byte = bytes[lineEnd]
                    if byte == Self.lineFeed { nextLineStart = lineEnd + 1; break }
                    if byte == Self.carriageReturn {
                        nextLineStart = lineEnd + 1 < bytes.count && bytes[lineEnd + 1] == Self.lineFeed ? lineEnd + 2 : lineEnd + 1
                        break
                    }
                    if byte == 0xC2, lineEnd + 1 < bytes.count, bytes[lineEnd + 1] == 0x85 { nextLineStart = lineEnd + 2; break }
                    if byte == 0xE2, lineEnd + 2 < bytes.count, bytes[lineEnd + 1] == 0x80, bytes[lineEnd + 2] == 0xA8 || bytes[lineEnd + 2] == 0xA9 {
                        nextLineStart = lineEnd + 3
                        break
                    }
                    lineEnd += 1
                }
                readLine(UnsafeBufferPointer(rebasing: bytes[lineStart..<lineEnd]))
                lineStart = nextLineStart
            }
        }

        private mutating func readLine(_ line: UnsafeBufferPointer<UInt8>) {
            let (quoteDepth, contentStart) = Self.quoteMarkers(in: line, maximumDepth: Int.max)
            if fenceTracker.isInsideFence {
                // A fence in a block quote ends where the quote ends; deeper markers are code.
                if quoteDepth < fenceQuoteDepth {
                    fenceTracker = CodeFenceTracker()
                } else {
                    let fenceContentStart = quoteDepth == fenceQuoteDepth ? contentStart : Self.quoteMarkers(in: line, maximumDepth: fenceQuoteDepth).contentStart
                    // Only a line starting with the fence's character can close it.
                    if Self.mayBeFence(line, from: fenceContentStart) { _ = fenceTracker.isCodeLine(Self.trimmedText(line, from: fenceContentStart)) }
                    return
                }
            }
            if !isInsideComment, Self.mayBeFence(line, from: contentStart), fenceTracker.isCodeLine(Self.trimmedText(line, from: contentStart)) {
                fenceQuoteDepth = quoteDepth
                return
            }
            if isInsideComment || Self.containsCommentOpening(line, from: contentStart) {
                isInsideComment = LinkCompletion.endsInsideComment(String(decoding: UnsafeBufferPointer(rebasing: line[contentStart...]), as: UTF8.self),
                                                                   startsInside: isInsideComment)
            }
        }

        /// The `>` markers at the start of a line, each indented by at most three spaces,
        /// and where the text after them starts.
        private static func quoteMarkers(in line: UnsafeBufferPointer<UInt8>, maximumDepth: Int) -> (depth: Int, contentStart: Int) {
            var depth = 0, contentStart = 0
            while depth < maximumDepth {
                var markerIndex = contentStart
                while markerIndex < line.count, markerIndex - contentStart <= 3, line[markerIndex] == space || line[markerIndex] == tab { markerIndex += 1 }
                guard markerIndex - contentStart <= 3, markerIndex < line.count, line[markerIndex] == greaterThan else { break }
                contentStart = markerIndex + 1
                if contentStart < line.count, line[contentStart] == space { contentStart += 1 }
                depth += 1
            }
            return (depth, contentStart)
        }

        /// Whether the first character after the leading spaces is a backtick or a tilde, or
        /// beyond ASCII, where it may be other whitespace that the trimmed line check skips.
        private static func mayBeFence(_ line: UnsafeBufferPointer<UInt8>, from start: Int) -> Bool {
            var index = start
            while index < line.count, line[index] == space || line[index] == tab { index += 1 }
            guard index < line.count else { return false }
            return line[index] == backtick || line[index] == tilde || line[index] >= 0x80
        }

        private static func trimmedText(_ line: UnsafeBufferPointer<UInt8>, from start: Int) -> String {
            String(decoding: UnsafeBufferPointer(rebasing: line[start...]), as: UTF8.self).trimmingCharacters(in: .whitespaces)
        }

        private static func containsCommentOpening(_ line: UnsafeBufferPointer<UInt8>, from start: Int) -> Bool {
            let opening: [UInt8] = [0x3C, 0x21, 0x2D, 0x2D] // "<!--"
            guard line.count - start >= opening.count else { return false }
            for index in start...(line.count - opening.count) where line[index] == opening[0] {
                if line[index + 1] == opening[1] && line[index + 2] == opening[2] && line[index + 3] == opening[3] { return true }
            }
            return false
        }
    }

    /// The block quote markers (`>`) at the start of a line, at most `maximumDepth` of them,
    /// and the text after them.
    private static func quoteMarkers<Line: StringProtocol>(in line: Line, maximumDepth: Int) -> (depth: Int, content: Substring) {
        var content = Substring(line)
        var depth = 0
        while depth < maximumDepth {
            // A marker may be indented by up to three spaces.
            var markerIndex = content.startIndex
            var indentation = 0
            while markerIndex < content.endIndex, indentation <= 3, content[markerIndex] == " " || content[markerIndex] == "\t" {
                indentation += 1
                markerIndex = content.index(after: markerIndex)
            }
            guard indentation <= 3, markerIndex < content.endIndex, content[markerIndex] == ">" else { break }
            content = content[content.index(after: markerIndex)...]
            if content.first == " " { content = content.dropFirst() }
            depth += 1
        }
        return (depth, content)
    }

    /// Whether `text` ends inside an HTML comment (`<!--` without its `-->`), given whether
    /// it starts inside one. Markers in inline code are text.
    private static func endsInsideComment<Text: StringProtocol>(_ text: Text, startsInside: Bool) -> Bool {
        guard startsInside || text.contains("<!--") else { return false }
        let source = String(text) as NSString
        let codeRanges = MarkdownCodeRanges.ranges(in: source)
        var isInside = startsInside
        var searchLocation = 0
        while searchLocation < source.length {
            let marker = isInside ? "-->" : "<!--"
            let found = source.range(of: marker, options: .literal, range: NSRange(location: searchLocation, length: source.length - searchLocation))
            guard found.location != NSNotFound else { break }
            searchLocation = NSMaxRange(found)
            if !isInside && MarkdownCodeRanges.range(found, isInside: codeRanges) { continue }
            isInside.toggle()
        }
        return isInside
    }

    static let maximumScannedLengthForFences = 400_000

    /// The link text a chosen file gets: its name when that is unique in the vault (or
    /// with the vault's link format), without `.md` for notes.
    public static func linkTarget(for path: VaultPath, from note: VaultPath, settings: ObsidianSettings, isNameUnique: Bool) -> String {
        let target: String
        switch settings.linkFormat {
        case .shortest: target = isNameUnique ? path.name : path.rawValue
        case .relative: target = path.relativePath(from: note.parent)
        case .absolute: target = path.rawValue
        }
        return DocumentKind(path: path) == .markdown ? (target as NSString).deletingPathExtension : target
    }
}

/// A link written in a note: to a vault file or heading, or to the web.
public enum LinkInText: Equatable, Sendable {
    /// A Wikilink target (`Note#Heading`, without the alias) or a Markdown link's destination.
    case note(target: String, isWiki: Bool)
    case web(URL)
}

public enum LinkLocator {
    private static let wikilinkPattern = try? NSRegularExpression(pattern: "(!?)\\[\\[([^\\]|\\n]+)(?:\\|[^\\]\\n]+)?\\]\\]")
    private static let markdownLinkPattern = try? NSRegularExpression(pattern: "(?<!!)\\[[^\\]\\n]*\\]\\(([^)\\n]+)\\)")

    /// The link around a character of a line, if any. Embeds are not links.
    /// - Parameter includesEnd: Also counts the position right after the link's last
    ///   character, where the cursor sits after typing it.
    public static func link(in line: String, at index: Int, includesEnd: Bool) -> LinkInText? {
        let lineLength = (line as NSString).length
        let wholeLine = NSRange(location: 0, length: lineLength)
        let contains = { (range: NSRange) in NSLocationInRange(index, range) || (includesEnd && index == NSMaxRange(range)) }
        if let match = wikilinkPattern?.matches(in: line, range: wholeLine).first(where: { match in contains(match.range) }) {
            guard match.range(at: 1).length == 0 else { return nil }
            return .note(target: (line as NSString).substring(with: match.range(at: 2)), isWiki: true)
        }
        if let match = markdownLinkPattern?.matches(in: line, range: wholeLine).first(where: { match in contains(match.range) }) {
            let destination = (line as NSString).substring(with: match.range(at: 1))
            if let webLocation = URL(string: destination), webLocation.scheme != nil { return .web(webLocation) }
            return .note(target: destination, isWiki: false)
        }
        return nil
    }
}
