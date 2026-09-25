import Foundation

/// Presentation roles for Markdown source text. The editor maps roles to fonts and
/// colors; the source bytes are never changed by styling.
public enum MarkdownStyle: Equatable, Hashable, Sendable {
    case heading(level: Int)
    /// Markup that stays visible in every mode, such as `>` and code fences.
    case syntaxMarker
    /// Markup Live Preview hides away from the cursor: `#`, `**`, backticks, link brackets.
    case concealableMarker
    case strong
    case emphasis
    case strikethrough
    case highlight
    case inlineCode
    case codeBlock
    case link
    case embed
    case tag
    case math
    case quote
    case calloutTitle
    case listMarker
    case taskMarker
    /// The `#` between a note and its heading in `[[Note#Heading]]`, which Live Preview
    /// shows as "Note > Heading", as Obsidian does.
    case subpathSeparator
    case frontmatter
    case horizontalRule
    /// A footnote reference's label or an inline footnote's text, drawn small and raised.
    case footnote
}

public struct MarkdownStyleSpan: Equatable, Sendable {
    public let range: NSRange
    public let style: MarkdownStyle
    public init(range: NSRange, style: MarkdownStyle) {
        self.range = range
        self.style = style
    }
}

/// Multi-line constructs whose content is not ordinary Markdown.
public enum MarkdownBlockContext: Equatable, Sendable {
    case normal, fencedCode, mathBlock, frontmatter
}

/// The scanner's block state at the start of one line of one text. A caller that keeps
/// checkpoints for a text passes the nearest one back, so a lookup far down a long note
/// scans only from there. A checkpoint stays valid while the text before its line is
/// unchanged; the caller discards it otherwise.
public struct MarkdownBlockCheckpoint: Equatable, Sendable {
    public let lineStart: Int
    let state: MarkdownStyleScanner.BlockState
    /// The frontmatter's length when the checkpoint was made. The state after the
    /// frontmatter was scanned from its end, so it is reused only while that end is the same.
    let frontmatterEnd: Int

    public var context: MarkdownBlockContext { state.context }
}

/// A line-oriented scanner for editor styling. It is intentionally tolerant: it styles
/// what Obsidian users type and never needs a whole-document parse per keystroke. Only
/// the block context before the styled lines depends on earlier text, and finding it
/// reads the earlier lines' characters without building strings for ordinary lines.
public enum MarkdownStyleScanner {
    /// The block context in effect at the start of the line containing `location`.
    public static func blockContext(atLineContaining location: Int, in text: NSString) -> MarkdownBlockContext {
        let targetLineStart = text.lineRange(for: NSRange(location: min(location, text.length), length: 0)).location
        return blockState(atLineStart: targetLineStart, in: text, frontmatterEnd: FrontmatterLocator.length(in: text)).context
    }

    /// The checkpoint at `lineStart`, which must start a line, scanning from `checkpoint`
    /// when it lies at or before that line (from the top of the text otherwise).
    public static func blockCheckpoint(atLineStart lineStart: Int, in text: NSString, resumingFrom checkpoint: MarkdownBlockCheckpoint?) -> MarkdownBlockCheckpoint {
        let frontmatterEnd = FrontmatterLocator.length(in: text)
        let state = blockState(atLineStart: lineStart, in: text, frontmatterEnd: frontmatterEnd, resumingFrom: checkpoint)
        return MarkdownBlockCheckpoint(lineStart: lineStart, state: state, frontmatterEnd: frontmatterEnd)
    }

    /// Spans for every line intersecting `range`, extended to whole lines. A paragraph
    /// line just before them and a `---` or `===` line just after them are styled too:
    /// whether such a line underlines the paragraph as a setext heading or draws a rule
    /// depends on its neighbor.
    ///
    /// `checkpoint`, when it lies at or before the line before `range`, spares scanning the
    /// text before it; the spans are the same either way.
    public static func spans(in text: NSString, range: NSRange, resumingFrom checkpoint: MarkdownBlockCheckpoint? = nil) -> [MarkdownStyleSpan] {
        let wholeLines = text.lineRange(for: NSRange(location: min(range.location, text.length), length: min(range.length, text.length - min(range.location, text.length))))
        let frontmatterEnd = FrontmatterLocator.length(in: text)
        var lineStart = wholeLines.location
        var state = BlockState()
        var previousLineIsParagraphText = false
        if lineStart > 0 && lineStart > frontmatterEnd {
            let previousLineRange = text.lineRange(for: NSRange(location: lineStart - 1, length: 0))
            let previousLine = text.substring(with: previousLineRange)
            let previousLineState = blockState(atLineStart: previousLineRange.location, in: text, frontmatterEnd: frontmatterEnd, resumingFrom: checkpoint)
            let previousState = stateForStyling(line: previousLine, previousLineState)
            if previousState.context == .normal && isParagraphText(previousLine) {
                lineStart = previousLineRange.location
                state = previousState
            } else {
                state = nextState(after: previousLine, previousState)
            }
        }
        var spans: [MarkdownStyleSpan] = []
        var styledEnd = NSMaxRange(wholeLines)
        var line = text.substring(with: text.lineRange(for: NSRange(location: lineStart, length: 0)))
        repeat {
            let nextLineStart = lineStart + (line as NSString).length
            let nextLine = nextLineStart < text.length ? text.substring(with: text.lineRange(for: NSRange(location: nextLineStart, length: 0))) : nil
            // Only a line followed by a possible underline needs its paragraph test.
            let nextLineUnderlineLevel = nextLine.flatMap(setextUnderlineLevel)
            if lineStart < frontmatterEnd {
                spans.append(contentsOf: frontmatterSpans(line: line as NSString, lineLocation: lineStart))
                state = BlockState()
                previousLineIsParagraphText = false
            } else {
                state = stateForStyling(line: line, state)
                let isParagraphText = nextLineUnderlineLevel != nil && state.context == .normal && isParagraphText(line)
                let neighbors = LineNeighbors(isAfterParagraphText: previousLineIsParagraphText, setextHeadingLevel: isParagraphText ? nextLineUnderlineLevel : nil)
                spans.append(contentsOf: lineSpans(line: line as NSString, lineLocation: lineStart, state: state, neighbors: neighbors))
                state = nextState(after: line, state)
                previousLineIsParagraphText = isParagraphText
            }
            lineStart = nextLineStart
            guard let nextLine else { break }
            if lineStart == styledEnd && nextLineUnderlineLevel != nil { styledEnd += (nextLine as NSString).length }
            line = nextLine
        } while lineStart < styledEnd
        return spans
    }

    /// True when editing this line could change how later lines are styled.
    public static func lineAffectsFollowingLines(_ line: String) -> Bool {
        let content = contentWithoutQuoteMarkers(line)
        return content.hasPrefix("```") || content.hasPrefix("~~~") || content.hasPrefix("$$") || line.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
    }

    // MARK: Block structure

    /// The block state carried from line to line.
    struct BlockState: Equatable, Sendable {
        var context = MarkdownBlockContext.normal
        /// The run of backticks or tildes that opened the current code block.
        var openFence: String?
        /// Quote markers before that opening fence. A line with fewer ends the quote, and
        /// a code block cannot continue lazily past it, so the code block ends too.
        var fenceQuoteDepth = 0
    }

    private static let dollar = UInt16(UInt8(ascii: "$"))
    private static let backslash = UInt16(UInt8(ascii: "\\"))

    /// The state at `targetLineStart`, after the frontmatter, found without building a
    /// string for every earlier line: only a line whose first visible character (after
    /// quote markers) is a fence character or `$` can open or close a block, and only a
    /// line ending in `$` closes display math. The characters are read in chunks, because
    /// on the editor's text storage every call goes through a slow proxy, and the old
    /// line-by-line walk dominated each keystroke far down a long note. A code block
    /// inside a quote also ends at a line outside the quote, so it is followed line by line.
    ///
    /// A `checkpoint` at or before `targetLineStart`, made after the same frontmatter,
    /// holds the state at its line, so the walk starts there instead.
    private static func blockState(atLineStart targetLineStart: Int, in text: NSString, frontmatterEnd: Int,
                                   resumingFrom checkpoint: MarkdownBlockCheckpoint? = nil) -> BlockState {
        if targetLineStart < frontmatterEnd { return BlockState(context: .frontmatter) }
        var state = BlockState()
        var lineStart = frontmatterEnd
        if let checkpoint, checkpoint.frontmatterEnd == frontmatterEnd, checkpoint.lineStart >= frontmatterEnd, checkpoint.lineStart <= targetLineStart {
            state = checkpoint.state
            lineStart = checkpoint.lineStart
        }
        while lineStart < targetLineStart {
            let lineRange: NSRange
            if state.context == .fencedCode && state.fenceQuoteDepth > 0 {
                lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            } else {
                let searchedRange = NSRange(location: lineStart, length: targetLineStart - lineStart)
                guard let candidateLineStart = firstLineThatMayChangeState(state, in: text, range: searchedRange) else { break }
                lineRange = text.lineRange(for: NSRange(location: candidateLineStart, length: 0))
            }
            state = nextState(after: text.substring(with: lineRange), state)
            lineStart = NSMaxRange(lineRange)
        }
        return state
    }

    private static let unitsPerChunk = 4_096
    private static let greaterThan = UInt16(UInt8(ascii: ">"))
    private static let space = UInt16(UInt8(ascii: " "))
    private static let lineFeed = UInt16(UInt8(ascii: "\n"))
    private static let carriageReturn = UInt16(UInt8(ascii: "\r"))
    /// Next line, line separator and paragraph separator, which also end NSString lines.
    private static let unicodeLineTerminators: [UInt16] = [0x0085, 0x2028, 0x2029]

    /// Where the first line in `range` that may change `state` starts, or nil. `range`
    /// starts at a line start. A cheap, conservative test before building the line's
    /// string; the line's string then decides.
    private static func firstLineThatMayChangeState(_ state: BlockState, in text: NSString, range: NSRange) -> Int? {
        let isMathBlock = state.context == .mathBlock
        let significantUnits: [UInt16] = switch state.context {
        case .normal, .frontmatter: [UInt16(UInt8(ascii: "`")), UInt16(UInt8(ascii: "~")), dollar]
        case .fencedCode: [state.openFence?.first == "~" ? UInt16(UInt8(ascii: "~")) : UInt16(UInt8(ascii: "`"))]
        case .mathBlock: [dollar]
        }
        var chunk = [UInt16](repeating: 0, count: unitsPerChunk)
        var lineStart = range.location
        // Outside display math: whether the line holds only indentation and quote markers so far.
        var lineIsIndentationSoFar = true
        // In display math: whether the line's last visible character so far is `$`.
        var lastVisibleIsDollar = false
        var chunkStart = range.location
        while chunkStart < NSMaxRange(range) {
            let chunkLength = min(unitsPerChunk, NSMaxRange(range) - chunkStart)
            text.getCharacters(&chunk, range: NSRange(location: chunkStart, length: chunkLength))
            for offset in 0..<chunkLength {
                let unit = chunk[offset]
                if unit == lineFeed || unit == carriageReturn || unicodeLineTerminators.contains(unit) {
                    if lastVisibleIsDollar { return lineStart }
                    lineStart = chunkStart + offset + 1
                    lineIsIndentationSoFar = true
                } else if isMathBlock {
                    if unit == dollar {
                        lastVisibleIsDollar = true
                    } else if lastVisibleIsDollar && !isWhitespaceOrNewline(unit) {
                        lastVisibleIsDollar = false
                    }
                } else if lineIsIndentationSoFar {
                    if significantUnits.contains(unit) { return lineStart }
                    lineIsIndentationSoFar = unit == greaterThan || isWhitespaceOrNewline(unit)
                }
            }
            chunkStart += chunkLength
        }
        return lastVisibleIsDollar ? lineStart : nil
    }

    private static let whitespaceAndNewlineCharacters = CharacterSet.whitespacesAndNewlines

    private static func isWhitespaceOrNewline(_ unit: UInt16) -> Bool {
        if unit == space { return true }
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return whitespaceAndNewlineCharacters.contains(scalar)
    }

    /// The state that styles `line`: a quoted code block ends at a line outside its quote.
    private static func stateForStyling(line: String, _ state: BlockState) -> BlockState {
        guard state.context == .fencedCode, quoteMarkersAndContent(of: line, maximumDepth: state.fenceQuoteDepth).depth < state.fenceQuoteDepth else { return state }
        return BlockState()
    }

    static func nextState(after line: String, _ state: BlockState) -> BlockState {
        switch state.context {
        case .fencedCode:
            let (depth, content) = quoteMarkersAndContent(of: line, maximumDepth: state.fenceQuoteDepth)
            // Leaving the quote ends the code block, and the line is read afresh.
            if depth < state.fenceQuoteDepth { return nextState(after: line, BlockState()) }
            guard let fence = state.openFence, !CodeFence.closes(fence, content) else { return BlockState() }
            return state
        case .mathBlock:
            return contentWithoutQuoteMarkers(line).hasSuffix("$$") ? BlockState() : state
        case .normal, .frontmatter:
            let (depth, content) = quoteMarkersAndContent(of: line, maximumDepth: .max)
            if let (fence, _) = CodeFence.opening(content) { return BlockState(context: .fencedCode, openFence: fence, fenceQuoteDepth: depth) }
            if opensDisplayMathBlock(content) { return BlockState(context: .mathBlock) }
            return BlockState()
        }
    }

    /// Whether a line starting with `$$` leaves display math open: its unescaped `$$`
    /// delimiters are odd in number. `$$E=mc^2$$ where…` opens and closes on its line.
    static func opensDisplayMathBlock(_ content: String) -> Bool {
        content.hasPrefix("$$") && displayMathDelimiterCount(in: content) % 2 == 1
    }

    /// Unescaped `$$` pairs in `line`, counted left to right without overlap.
    static func displayMathDelimiterCount(in line: String) -> Int {
        let units = Array(line.utf16)
        var count = 0
        var index = 0
        while index < units.count {
            if units[index] == backslash {
                index += 2
            } else if units[index] == dollar && index + 1 < units.count && units[index + 1] == dollar {
                count += 1
                index += 2
            } else {
                index += 1
            }
        }
        return count
    }

    /// A line that is a whole display formula, such as `$$f = x$$`.
    private static func isSingleLineMathBlock(_ content: String) -> Bool {
        content.count > 4 && content.hasPrefix("$$") && content.hasSuffix("$$") && displayMathDelimiterCount(in: content) == 2
    }

    /// Line content after blockquote and callout markers, used for block detection.
    private static func contentWithoutQuoteMarkers(_ line: String) -> String {
        quoteMarkersAndContent(of: line, maximumDepth: .max).content
    }

    /// Up to `maximumDepth` leading quote markers, and the trimmed text after them.
    private static func quoteMarkersAndContent(of line: String, maximumDepth: Int) -> (depth: Int, content: String) {
        var remainder = Substring(line.trimmingCharacters(in: .whitespacesAndNewlines))
        var depth = 0
        while depth < maximumDepth && remainder.hasPrefix(">") {
            remainder = remainder.dropFirst().drop { character in character == " " }
            depth += 1
        }
        return (depth, String(remainder))
    }

    /// The level of a setext heading `line` underlines (`===` is 1, `---` is 2), or nil.
    static func setextUnderlineLevel(_ line: String) -> Int? {
        guard let firstVisible = line.first(where: { character in character != " " }), firstVisible == "=" || firstVisible == "-",
              line.prefix(while: { character in character == " " }).count < 4 else { return nil }
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let marker = trimmedLine.first, marker == "=" || marker == "-", trimmedLine.allSatisfy({ character in character == marker }) else { return nil }
        return marker == "=" ? 1 : 2
    }

    /// Whether `line`, outside code, math and frontmatter, is ordinary paragraph text,
    /// which a following `---` or `===` turns into a setext heading. After a heading, a
    /// list item, a quote or another block, `---` is a horizontal rule instead.
    static func isParagraphText(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix(">"), !trimmedLine.hasPrefix("$$"), !trimmedLine.hasSuffix("$$"),
              line.prefix(while: { character in character == " " }).count < 4 else { return false }
        let lineRange = NSRange(location: 0, length: (trimmedLine as NSString).length)
        let isBlockSyntax = CodeFence.opening(trimmedLine) != nil || (trimmedLine.count >= 3 && trimmedLine.allSatisfy { character in character == "`" || character == "~" })
            || setextUnderlineLevel(trimmedLine) != nil
            || [Patterns.horizontalRule, Patterns.heading, Patterns.listMarker, Patterns.emptyListItem].contains { pattern in pattern.firstMatch(in: trimmedLine, range: lineRange) != nil }
        return !isBlockSyntax
    }

    // MARK: Line styling

    /// What the lines around a line decide about it.
    private struct LineNeighbors {
        /// The previous line is paragraph text, so a `---` or `===` line underlines it.
        let isAfterParagraphText: Bool
        /// The next line underlines this one as a heading of this level.
        let setextHeadingLevel: Int?
    }

    private static func frontmatterSpans(line: NSString, lineLocation: Int) -> [MarkdownStyleSpan] {
        let contentLength = lengthWithoutLineEnding(line)
        guard contentLength > 0 else { return [] }
        return [MarkdownStyleSpan(range: NSRange(location: lineLocation, length: contentLength), style: .frontmatter)]
    }

    private static func lineSpans(line: NSString, lineLocation: Int, state: BlockState, neighbors: LineNeighbors) -> [MarkdownStyleSpan] {
        let contentLength = lengthWithoutLineEnding(line)
        guard contentLength > 0 else { return [] }
        let lineContent = NSRange(location: 0, length: contentLength)
        func span(_ range: NSRange, _ style: MarkdownStyle) -> MarkdownStyleSpan {
            MarkdownStyleSpan(range: NSRange(location: lineLocation + range.location, length: range.length), style: style)
        }
        let trimmedLine = line.substring(with: lineContent).trimmingCharacters(in: .whitespaces)
        let content = contentWithoutQuoteMarkers(trimmedLine)
        switch state.context {
        case .frontmatter:
            return [span(lineContent, .frontmatter)]
        case .fencedCode:
            let fenceContent = quoteMarkersAndContent(of: trimmedLine, maximumDepth: state.fenceQuoteDepth).content
            let isClosingFence = state.openFence.map { fence in CodeFence.closes(fence, fenceContent) } ?? false
            return [span(lineContent, isClosingFence ? .syntaxMarker : .codeBlock)]
        case .mathBlock:
            return [span(lineContent, .math)]
        case .normal:
            if CodeFence.opening(content) != nil { return [span(lineContent, .syntaxMarker)] }
            if opensDisplayMathBlock(content) || isSingleLineMathBlock(content) { return [span(lineContent, .math)] }
        }
        var spans: [MarkdownStyleSpan] = []
        var cursor = 0
        // Blockquote and callout markers.
        if let quoteMatch = Patterns.quotePrefix.firstMatch(in: line as String, range: lineContent) {
            spans.append(span(quoteMatch.range, .syntaxMarker))
            spans.append(span(NSRange(location: NSMaxRange(quoteMatch.range), length: contentLength - NSMaxRange(quoteMatch.range)), .quote))
            cursor = NSMaxRange(quoteMatch.range)
            // A callout's type comes right after the quote marker, as in Obsidian.
            if let calloutMatch = Patterns.calloutTitle.firstMatch(in: line as String, options: .anchored, range: NSRange(location: cursor, length: contentLength - cursor)) {
                spans.append(span(calloutMatch.range, .calloutTitle))
            }
        }
        let remainder = NSRange(location: cursor, length: contentLength - cursor)
        if cursor == 0 && neighbors.isAfterParagraphText && setextUnderlineLevel(line.substring(with: lineContent)) != nil {
            return [span(lineContent, .syntaxMarker)]
        }
        if Patterns.horizontalRule.firstMatch(in: line as String, range: remainder) != nil {
            return spans + [span(remainder, .horizontalRule)]
        }
        if let headingMatch = Patterns.heading.firstMatch(in: line as String, range: remainder) {
            let markerRange = headingMatch.range(at: 1)
            let level = line.substring(with: markerRange).filter { character in character == "#" }.count
            // The heading span includes the marker so both share the heading size; the
            // marker span that follows only dims it.
            spans.append(span(NSRange(location: markerRange.location, length: NSMaxRange(remainder) - markerRange.location), .heading(level: level)))
            spans.append(span(markerRange, .concealableMarker))
            cursor = NSMaxRange(markerRange)
        } else if cursor == 0, let level = neighbors.setextHeadingLevel {
            spans.append(span(remainder, .heading(level: level)))
        } else if let taskMatch = Patterns.task.firstMatch(in: line as String, range: remainder) {
            spans.append(span(taskMatch.range(at: 1), .listMarker))
            spans.append(span(taskMatch.range(at: 2), .taskMarker))
            cursor = NSMaxRange(taskMatch.range)
        } else if let listMatch = Patterns.listMarker.firstMatch(in: line as String, range: remainder) {
            spans.append(span(listMatch.range(at: 1), .listMarker))
            cursor = NSMaxRange(listMatch.range)
        }
        spans.append(contentsOf: inlineSpans(line: line, range: NSRange(location: cursor, length: contentLength - cursor)).map { inlineSpan in span(inlineSpan.range, inlineSpan.style) })
        return spans
    }

    /// Inline constructs in priority order; code and math hide everything inside them.
    private static func inlineSpans(line: NSString, range: NSRange) -> [MarkdownStyleSpan] {
        guard range.length > 0 else { return [] }
        var spans: [MarkdownStyleSpan] = []
        var claimedRanges: [NSRange] = []
        func isUnclaimed(_ candidate: NSRange) -> Bool {
            !claimedRanges.contains { claimedRange in NSIntersectionRange(claimedRange, candidate).length > 0 }
        }
        func addDelimited(_ whole: NSRange, style: MarkdownStyle, delimiterLength: Int) {
            spans.append(MarkdownStyleSpan(range: NSRange(location: whole.location, length: delimiterLength), style: .concealableMarker))
            spans.append(MarkdownStyleSpan(range: NSRange(location: whole.location + delimiterLength, length: whole.length - 2 * delimiterLength), style: style))
            spans.append(MarkdownStyleSpan(range: NSRange(location: NSMaxRange(whole) - delimiterLength, length: delimiterLength), style: .concealableMarker))
        }
        let lineString = line as String
        for codeSpan in MarkdownCodeRanges.codeSpans(in: line, range: range) {
            addDelimited(codeSpan.range, style: .inlineCode, delimiterLength: codeSpan.delimiterLength)
            claimedRanges.append(codeSpan.range)
        }
        // A block's `^id` at the end of its line hides away from the cursor, as in Obsidian.
        for match in Patterns.blockIdentifier.matches(in: lineString, range: range) where isUnclaimed(match.range) {
            spans.append(MarkdownStyleSpan(range: match.range, style: .concealableMarker))
            claimedRanges.append(match.range)
        }
        for pattern in [Patterns.inlineDisplayMath, Patterns.inlineMath] {
            for match in pattern.matches(in: lineString, range: range) where isUnclaimed(match.range) {
                spans.append(MarkdownStyleSpan(range: match.range, style: .math))
                claimedRanges.append(match.range)
            }
        }
        // A footnote definition's `[^label]:` at the start of its line reads as a label.
        for match in Patterns.footnoteDefinition.matches(in: lineString, range: range) where isUnclaimed(match.range) {
            spans.append(MarkdownStyleSpan(range: match.range, style: .syntaxMarker))
            claimedRanges.append(match.range)
        }
        // `[^label]` and `^[text]` show their label or text, small and raised.
        for pattern in [Patterns.footnoteReference, Patterns.inlineFootnote] {
            for match in pattern.matches(in: lineString, range: range) where isUnclaimed(match.range) {
                let content = match.range(at: 1)
                spans.append(MarkdownStyleSpan(range: NSRange(location: match.range.location, length: content.location - match.range.location), style: .concealableMarker))
                spans.append(MarkdownStyleSpan(range: content, style: .footnote))
                spans.append(MarkdownStyleSpan(range: NSRange(location: NSMaxRange(content), length: NSMaxRange(match.range) - NSMaxRange(content)), style: .concealableMarker))
                claimedRanges.append(match.range)
            }
        }
        for match in Patterns.wikilink.matches(in: lineString, range: range) where isUnclaimed(match.range) {
            let isEmbed = match.range(at: 1).length > 0
            let openingLength = isEmbed ? 3 : 2
            let contentRange = NSRange(location: match.range.location + openingLength, length: match.range.length - openingLength - 2)
            let aliasSeparator = line.range(of: "|", range: contentRange)
            let subpathSeparator = line.range(of: "#", range: contentRange)
            if !isEmbed && aliasSeparator.location != NSNotFound {
                // `[[target|alias]]` reads as "alias": the target is markup like the brackets.
                spans.append(MarkdownStyleSpan(range: NSRange(location: match.range.location, length: NSMaxRange(aliasSeparator) - match.range.location), style: .concealableMarker))
                spans.append(MarkdownStyleSpan(range: NSRange(location: NSMaxRange(aliasSeparator), length: NSMaxRange(contentRange) - NSMaxRange(aliasSeparator)), style: .link))
            } else if !isEmbed && line.substring(with: contentRange).hasPrefix("#") {
                // `[[#Heading]]` reads as "Heading", as in Obsidian.
                spans.append(MarkdownStyleSpan(range: NSRange(location: match.range.location, length: openingLength + 1), style: .concealableMarker))
                spans.append(MarkdownStyleSpan(range: NSRange(location: contentRange.location + 1, length: contentRange.length - 1), style: .link))
            } else if !isEmbed && subpathSeparator.location != NSNotFound {
                spans.append(MarkdownStyleSpan(range: NSRange(location: match.range.location, length: openingLength), style: .concealableMarker))
                spans.append(MarkdownStyleSpan(range: NSRange(location: contentRange.location, length: subpathSeparator.location - contentRange.location), style: .link))
                spans.append(MarkdownStyleSpan(range: subpathSeparator, style: .subpathSeparator))
                spans.append(MarkdownStyleSpan(range: NSRange(location: NSMaxRange(subpathSeparator), length: NSMaxRange(contentRange) - NSMaxRange(subpathSeparator)), style: .link))
            } else {
                spans.append(MarkdownStyleSpan(range: NSRange(location: match.range.location, length: openingLength), style: .concealableMarker))
                spans.append(MarkdownStyleSpan(range: contentRange, style: isEmbed ? .embed : .link))
            }
            spans.append(MarkdownStyleSpan(range: NSRange(location: NSMaxRange(match.range) - 2, length: 2), style: .concealableMarker))
            claimedRanges.append(match.range)
        }
        for match in Patterns.markdownLink.matches(in: lineString, range: range) where isUnclaimed(match.range) {
            let isEmbed = match.range(at: 1).length > 0
            let labelRange = match.range(at: 2)
            spans.append(MarkdownStyleSpan(range: NSRange(location: match.range.location, length: labelRange.location - match.range.location), style: .concealableMarker))
            spans.append(MarkdownStyleSpan(range: labelRange, style: isEmbed ? .embed : .link))
            spans.append(MarkdownStyleSpan(range: NSRange(location: NSMaxRange(labelRange), length: NSMaxRange(match.range) - NSMaxRange(labelRange)), style: .concealableMarker))
            claimedRanges.append(match.range)
        }
        for match in Patterns.strong.matches(in: lineString, range: range) where isUnclaimed(match.range) {
            addDelimited(match.range, style: .strong, delimiterLength: 2)
        }
        for match in Patterns.emphasis.matches(in: lineString, range: range) where isUnclaimed(match.range) {
            addDelimited(match.range, style: .emphasis, delimiterLength: 1)
        }
        for match in Patterns.strikethrough.matches(in: lineString, range: range) where isUnclaimed(match.range) {
            addDelimited(match.range, style: .strikethrough, delimiterLength: 2)
        }
        for match in Patterns.highlight.matches(in: lineString, range: range) where isUnclaimed(match.range) {
            addDelimited(match.range, style: .highlight, delimiterLength: 2)
        }
        for match in TagSyntax.pattern.matches(in: lineString, range: range) where isUnclaimed(match.range) {
            spans.append(MarkdownStyleSpan(range: match.range, style: .tag))
        }
        return spans
    }

    private static func lengthWithoutLineEnding(_ line: NSString) -> Int {
        var length = line.length
        while length > 0, let scalar = Unicode.Scalar(line.character(at: length - 1)), CharacterSet.newlines.contains(scalar) { length -= 1 }
        return length
    }

    /// Compiled once. The patterns are fixed, so compilation cannot fail at run time.
    private enum Patterns {
        static let quotePrefix = compile("^\\s*(?:>\\s?)+")
        static let calloutTitle = compile("\\[![A-Za-z0-9_-]+\\][+-]?")
        static let horizontalRule = compile("^\\s*(?:(?:-\\s*){3,}|(?:\\*\\s*){3,}|(?:_\\s*){3,})$")
        static let heading = compile("^\\s{0,3}(#{1,6}\\s+)")
        static let task = compile("^\\s*([-*+]|\\d+[.)])\\s+(\\[[ xX/-]\\])\\s")
        static let listMarker = compile("^\\s*([-*+]|\\d+[.)])\\s")
        /// A list marker alone on its line, which `listMarker` (needing a space) misses.
        static let emptyListItem = compile("^\\s*(?:[-*+]|\\d+[.)])$")
        static let blockIdentifier = compile("(?<=[ \\t])\\^[A-Za-z0-9-]+[ \\t]*$|^\\^[A-Za-z0-9-]+[ \\t]*$")
        /// `$$…$$` inside a line, as Obsidian renders it.
        static let inlineDisplayMath = compile("(?<![\\\\$])\\$\\$(?:[^$\\n\\\\]|\\\\.)+?\\$\\$")
        /// Pandoc's and Obsidian's rules: no space inside either `$`, the closing `$` is not
        /// followed by a digit (so "$5 and $10" are prices), and `\$` is a literal dollar.
        static let inlineMath = compile("(?<![\\\\$])\\$(?![\\s$])(?:[^$\\n\\\\]|\\\\.)+?(?<!\\s)\\$(?![$\\d])")
        static let wikilink = compile("(!?)\\[\\[[^\\]\\n]+\\]\\]")
        static let footnoteDefinition = compile("^\\[\\^[^\\]\\s]+\\]:")
        static let footnoteReference = compile("\\[\\^([^\\]\\s]+)\\](?!:)")
        static let inlineFootnote = compile("(?<![\\\\!\\]])\\^\\[([^\\]\\n]+)\\]")
        /// The destination may hold one level of balanced parentheses, as Wikipedia URLs do.
        static let markdownLink = compile("(!?)\\[([^\\]\\n]*)\\]\\((?:[^()\\n]|\\([^()\\n]*\\))*\\)")
        static let strong = compile("(?<![*_])(\\*\\*|__)(?!\\s)[^\\n]+?(?<!\\s)\\1(?![*_])")
        static let emphasis = compile("(?<![*\\w])[*_](?![\\s*_])[^*_\\n]+?(?<![\\s])[*_](?![*\\w])")
        static let strikethrough = compile("~~(?!\\s)[^~\\n]+?(?<!\\s)~~")
        static let highlight = compile("==(?!\\s)[^=\\n]+?(?<!\\s)==")

        private static func compile(_ pattern: String) -> NSRegularExpression {
            // Patterns are compile-time constants covered by tests.
            try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }
    }
}
