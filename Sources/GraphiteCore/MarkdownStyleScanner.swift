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
    /// The inline element the span is part of, with its markup: the whole `**bold**`
    /// around either `**`, the whole `[[Note|alias]]` around its brackets and its alias.
    /// Nil for a span that belongs to its line instead: a heading's `#`, a list, task or
    /// quote marker, a block's `^id`. Live Preview shows an inline element's markup while
    /// the selection touches the element, and a line's markup while the selection is on it.
    public let inlineElementRange: NSRange?
    /// For a `.codeBlock` line or a code fence (a `.syntaxMarker`), the fenced block it
    /// belongs to, which the editor highlights and draws in a box.
    public let fencedCodeBlock: FencedCodeBlock?

    public init(range: NSRange, style: MarkdownStyle, inlineElementRange: NSRange? = nil, fencedCodeBlock: FencedCodeBlock? = nil) {
        self.range = range
        self.style = style
        self.inlineElementRange = inlineElementRange
        self.fencedCodeBlock = fencedCodeBlock
    }
}

/// A fenced code block as its lines' spans describe it. It depends only on the text before
/// those lines, as the scanner's block state does.
public struct FencedCodeBlock: Equatable, Sendable {
    /// The first word of the opening fence's info text, as written: `cpp` in ```` ```cpp ````.
    public let language: String
    /// Where the line after the opening fence starts.
    public let codeStart: Int
    /// Quote markers before the opening fence, which every line of the block repeats.
    public let quoteDepth: Int
    /// The run of backticks or tildes that opened the block, which a closing fence repeats.
    public let fence: String

    /// The block's code: from `codeStart` to the start of its closing fence's line, or to the
    /// end of the text for a block left open. A line with fewer quote markers ends a quoted
    /// block too.
    public func codeRange(in text: NSString) -> NSRange {
        let start = min(codeStart, text.length)
        var lineStart = start
        while lineStart < text.length {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            let line = text.substring(with: lineRange)
            let (depth, content) = MarkdownStyleScanner.quoteMarkersAndContent(of: line, maximumDepth: quoteDepth)
            if depth < quoteDepth || CodeFence.closes(fence, content) { break }
            lineStart = NSMaxRange(lineRange)
        }
        return NSRange(location: start, length: lineStart - start)
    }

    /// Whether `location` is in the block's code, found without reading every line of the
    /// block: only a closing fence between the code's start and `location` ends it first.
    public func contains(_ location: Int, in text: NSString) -> Bool {
        guard location >= codeStart, location <= text.length else { return false }
        var searchStart = codeStart
        while searchStart < location {
            let found = text.range(of: fence, options: .literal, range: NSRange(location: searchStart, length: location - searchStart))
            guard found.location != NSNotFound else { return true }
            let lineRange = text.lineRange(for: NSRange(location: found.location, length: 0))
            let (depth, content) = MarkdownStyleScanner.quoteMarkersAndContent(of: text.substring(with: lineRange), maximumDepth: quoteDepth)
            if depth == quoteDepth, CodeFence.closes(fence, content), lineRange.location <= location { return false }
            searchStart = max(NSMaxRange(found), lineRange.location + 1)
        }
        return true
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
                state = nextState(after: previousLine, endingAt: NSMaxRange(previousLineRange), in: text, previousState)
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
                spans.append(contentsOf: lineSpans(line: line as NSString, lineLocation: lineStart, state: state, neighbors: neighbors, in: text))
                state = nextState(after: line, endingAt: nextLineStart, in: text, state)
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
        /// The current code block, for its lines' spans.
        var fencedCodeBlock: FencedCodeBlock?
    }

    private static let dollar = UInt16(UInt8(ascii: "$"))
    private static let backslash = UInt16(UInt8(ascii: "\\"))

    /// The state at `targetLineStart`, after the frontmatter, found without building a
    /// string for every earlier line: only a line whose first visible character (after
    /// quote markers) is a fence character or `$` can open or close a block, and only a
    /// line ending in `$` closes display math. The characters are read in chunks, because
    /// on the editor's text storage every call goes through a slow proxy, and a walk line
    /// by line would cost each keystroke time in proportion to the note's length. A code block
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
            state = nextState(after: text.substring(with: lineRange), endingAt: NSMaxRange(lineRange), in: text, state)
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

    /// The state after `line`, which ends (line break included) at `lineEnd` in `text`.
    static func nextState(after line: String, endingAt lineEnd: Int, in text: NSString, _ state: BlockState) -> BlockState {
        switch state.context {
        case .fencedCode:
            let (depth, content) = quoteMarkersAndContent(of: line, maximumDepth: state.fenceQuoteDepth)
            // Leaving the quote ends the code block, and the line is read afresh.
            if depth < state.fenceQuoteDepth { return nextState(after: line, endingAt: lineEnd, in: text, BlockState()) }
            guard let fence = state.openFence, !CodeFence.closes(fence, content) else { return BlockState() }
            return state
        case .mathBlock:
            return contentWithoutQuoteMarkers(line).hasSuffix("$$") ? BlockState() : state
        case .normal, .frontmatter:
            let (depth, content) = quoteMarkersAndContent(of: line, maximumDepth: .max)
            if let (fence, info) = fenceOpening(content, ofLine: line, startingAt: lineEnd - (line as NSString).length, in: text) {
                let codeBlock = FencedCodeBlock(language: NotePreviewDocument.codeBlockLanguage(ofFenceInfo: info), codeStart: lineEnd, quoteDepth: depth, fence: fence)
                return BlockState(context: .fencedCode, openFence: fence, fenceQuoteDepth: depth, fencedCodeBlock: codeBlock)
            }
            if opensDisplayMathBlock(content) { return BlockState(context: .mathBlock) }
            return BlockState()
        }
    }

    /// The fence that `content`, the text of `line` (which starts at `lineStart` in `text`)
    /// after its quote markers, opens. Indented past `CodeFence.maximumIndentation` columns,
    /// a line opens one only within that many columns of the content of the list item
    /// holding it, as `MarkdownCodeRanges` reads fences; only such a line looks up its list
    /// item. Indentation is counted before any quote marker, so a quoted line's content
    /// is not checked.
    private static func fenceOpening(_ content: String, ofLine line: String, startingAt lineStart: Int, in text: NSString) -> (fence: String, info: String)? {
        guard let opening = CodeFence.opening(content) else { return nil }
        let indentation = ListItemContainers.leadingColumns(of: line)
        guard indentation <= CodeFence.maximumIndentation
                || indentation <= ListItemContainers.containerColumn(ofLineAt: lineStart, in: text) + CodeFence.maximumIndentation else { return nil }
        return opening
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
    static func quoteMarkersAndContent(of line: String, maximumDepth: Int) -> (depth: Int, content: String) {
        var remainder = Substring(line.trimmingCharacters(in: .whitespacesAndNewlines))
        var depth = 0
        while depth < maximumDepth && remainder.hasPrefix(">") {
            remainder = remainder.dropFirst().drop { character in character == " " }
            depth += 1
        }
        return (depth, String(remainder))
    }

    /// The level of the setext heading that `line` is the text of when `nextLine` underlines
    /// it, or nil. The one rule for setext headings: the editor's styling, the outline,
    /// heading links, section embeds, the reading view and folding all read it here.
    static func setextHeadingLevel(ofLine line: String, nextLine: String?) -> Int? {
        guard let nextLine, let level = setextUnderlineLevel(nextLine), isParagraphText(line) else { return nil }
        return level
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

    private static func lineSpans(line: NSString, lineLocation: Int, state: BlockState, neighbors: LineNeighbors, in text: NSString) -> [MarkdownStyleSpan] {
        let contentLength = lengthWithoutLineEnding(line)
        if contentLength == 0, state.context == .fencedCode, let codeBlock = state.fencedCodeBlock {
            // An empty span still tells the editor the blank line is part of the block's code.
            return [MarkdownStyleSpan(range: NSRange(location: lineLocation, length: 0), style: .codeBlock, fencedCodeBlock: codeBlock)]
        }
        guard contentLength > 0 else { return [] }
        let lineContent = NSRange(location: 0, length: contentLength)
        func span(_ range: NSRange, _ style: MarkdownStyle, inlineElementRange: NSRange? = nil) -> MarkdownStyleSpan {
            MarkdownStyleSpan(range: NSRange(location: lineLocation + range.location, length: range.length), style: style,
                              inlineElementRange: inlineElementRange.map { elementRange in NSRange(location: lineLocation + elementRange.location, length: elementRange.length) })
        }
        let trimmedLine = line.substring(with: lineContent).trimmingCharacters(in: .whitespaces)
        let content = contentWithoutQuoteMarkers(trimmedLine)
        switch state.context {
        case .frontmatter:
            return [span(lineContent, .frontmatter)]
        case .fencedCode:
            let fenceContent = quoteMarkersAndContent(of: trimmedLine, maximumDepth: state.fenceQuoteDepth).content
            let isClosingFence = state.openFence.map { fence in CodeFence.closes(fence, fenceContent) } ?? false
            if isClosingFence {
                return [MarkdownStyleSpan(range: NSRange(location: lineLocation, length: contentLength), style: .syntaxMarker, fencedCodeBlock: state.fencedCodeBlock)]
            }
            return [MarkdownStyleSpan(range: NSRange(location: lineLocation, length: contentLength), style: .codeBlock, fencedCodeBlock: state.fencedCodeBlock)]
        case .mathBlock:
            return [span(lineContent, .math)]
        case .normal:
            if let (fence, info) = fenceOpening(content, ofLine: line as String, startingAt: lineLocation, in: text) {
                let depth = quoteMarkersAndContent(of: trimmedLine, maximumDepth: .max).depth
                let codeBlock = FencedCodeBlock(language: NotePreviewDocument.codeBlockLanguage(ofFenceInfo: info), codeStart: lineLocation + line.length,
                                                quoteDepth: depth, fence: fence)
                return [MarkdownStyleSpan(range: NSRange(location: lineLocation, length: contentLength), style: .syntaxMarker, fencedCodeBlock: codeBlock)]
            }
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
        spans.append(contentsOf: inlineSpans(line: line, range: NSRange(location: cursor, length: contentLength - cursor)).map { inlineSpan in
            span(inlineSpan.range, inlineSpan.style, inlineElementRange: inlineSpan.inlineElementRange)
        })
        return spans
    }

    /// Stands in for a code span, formula, footnote or link while emphasis is looked for:
    /// neither a space, a word character nor a delimiter, like the punctuation those start
    /// and end with.
    private static let claimedTextPlaceholder = "\u{FFFC}"

    /// Inline constructs in priority order; code and math hide everything inside them.
    /// Each span carries the range of its whole element. A block's `^id` and a footnote
    /// definition's label belong to their line.
    private static func inlineSpans(line: NSString, range: NSRange) -> [MarkdownStyleSpan] {
        guard range.length > 0 else { return [] }
        var spans: [MarkdownStyleSpan] = []
        var claimedRanges: [NSRange] = []
        func isUnclaimed(_ candidate: NSRange) -> Bool {
            !claimedRanges.contains { claimedRange in NSIntersectionRange(claimedRange, candidate).length > 0 }
        }
        func add(_ spanRange: NSRange, _ style: MarkdownStyle, in elementRange: NSRange) {
            spans.append(MarkdownStyleSpan(range: spanRange, style: style, inlineElementRange: elementRange))
        }
        func addDelimited(_ whole: NSRange, style: MarkdownStyle, delimiterLength: Int) {
            add(NSRange(location: whole.location, length: delimiterLength), .concealableMarker, in: whole)
            add(NSRange(location: whole.location + delimiterLength, length: whole.length - 2 * delimiterLength), style, in: whole)
            add(NSRange(location: NSMaxRange(whole) - delimiterLength, length: delimiterLength), .concealableMarker, in: whole)
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
                add(match.range, .math, in: match.range)
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
                add(NSRange(location: match.range.location, length: content.location - match.range.location), .concealableMarker, in: match.range)
                add(content, .footnote, in: match.range)
                add(NSRange(location: NSMaxRange(content), length: NSMaxRange(match.range) - NSMaxRange(content)), .concealableMarker, in: match.range)
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
                add(NSRange(location: match.range.location, length: NSMaxRange(aliasSeparator) - match.range.location), .concealableMarker, in: match.range)
                add(NSRange(location: NSMaxRange(aliasSeparator), length: NSMaxRange(contentRange) - NSMaxRange(aliasSeparator)), .link, in: match.range)
            } else if !isEmbed && line.substring(with: contentRange).hasPrefix("#") {
                // `[[#Heading]]` reads as "Heading", as in Obsidian.
                add(NSRange(location: match.range.location, length: openingLength + 1), .concealableMarker, in: match.range)
                add(NSRange(location: contentRange.location + 1, length: contentRange.length - 1), .link, in: match.range)
            } else if !isEmbed && subpathSeparator.location != NSNotFound {
                add(NSRange(location: match.range.location, length: openingLength), .concealableMarker, in: match.range)
                add(NSRange(location: contentRange.location, length: subpathSeparator.location - contentRange.location), .link, in: match.range)
                add(subpathSeparator, .subpathSeparator, in: match.range)
                add(NSRange(location: NSMaxRange(subpathSeparator), length: NSMaxRange(contentRange) - NSMaxRange(subpathSeparator)), .link, in: match.range)
            } else {
                add(NSRange(location: match.range.location, length: openingLength), .concealableMarker, in: match.range)
                add(contentRange, isEmbed ? .embed : .link, in: match.range)
            }
            add(NSRange(location: NSMaxRange(match.range) - 2, length: 2), .concealableMarker, in: match.range)
            claimedRanges.append(match.range)
        }
        for match in Patterns.markdownLink.matches(in: lineString, range: range) where isUnclaimed(match.range) {
            let isEmbed = match.range(at: 1).length > 0
            let labelRange = match.range(at: 2)
            add(NSRange(location: match.range.location, length: labelRange.location - match.range.location), .concealableMarker, in: match.range)
            add(labelRange, isEmbed ? .embed : .link, in: match.range)
            add(NSRange(location: NSMaxRange(labelRange), length: NSMaxRange(match.range) - NSMaxRange(labelRange)), .concealableMarker, in: match.range)
            claimedRanges.append(match.range)
        }
        // Emphasis can hold any of the elements above (`**bold with a [[link]]**`), and a
        // delimiter inside one is that element's text. With each element replaced by
        // placeholders of the same length, a match can only contain elements whole.
        var emphasisLine = lineString
        if !claimedRanges.isEmpty {
            let placeholderLine = NSMutableString(string: lineString)
            for claimedRange in claimedRanges {
                placeholderLine.replaceCharacters(in: claimedRange, with: String(repeating: claimedTextPlaceholder, count: claimedRange.length))
            }
            emphasisLine = placeholderLine as String
        }
        for match in Patterns.strong.matches(in: emphasisLine, range: range) {
            addDelimited(match.range, style: .strong, delimiterLength: 2)
        }
        for match in Patterns.emphasis.matches(in: emphasisLine, range: range) {
            addDelimited(match.range, style: .emphasis, delimiterLength: 1)
        }
        for match in Patterns.strikethrough.matches(in: emphasisLine, range: range) {
            addDelimited(match.range, style: .strikethrough, delimiterLength: 2)
        }
        for match in Patterns.highlight.matches(in: emphasisLine, range: range) {
            addDelimited(match.range, style: .highlight, delimiterLength: 2)
        }
        for match in TagSyntax.pattern.matches(in: lineString, range: range) where isUnclaimed(match.range) {
            add(match.range, .tag, in: match.range)
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
        /// Up to three spaces before it: indented four, the line is code, as in CommonMark.
        static let horizontalRule = compile("^ {0,3}(?:(?:-[ \\t]*){3,}|(?:\\*[ \\t]*){3,}|(?:_[ \\t]*){3,})$")
        static let heading = compile("^\\s{0,3}(#{1,6}\\s+)")
        /// Any one-character status, as Obsidian and the Tasks plugin write them (`[>]`,
        /// `[!]`, `[?]`), not only `[ ]`, `[x]`, `[/]` and `[-]`. Ordered markers have one to
        /// nine ASCII digits, as in CommonMark and `MarkdownEditing`.
        static let task = compile("^\\s*([-*+]|[0-9]{1,9}[.)])\\s+(\\[[^\\]\\n]\\])\\s")
        static let listMarker = compile("^\\s*([-*+]|[0-9]{1,9}[.)])\\s")
        /// A list marker alone on its line, which `listMarker` (needing a space) misses.
        static let emptyListItem = compile("^\\s*(?:[-*+]|[0-9]{1,9}[.)])$")
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
        /// Opened and closed by the same character: `*note_` is not emphasis.
        static let emphasis = compile("(?<![*\\w])([*_])(?![\\s*_])[^*_\\n]+?(?<![\\s])\\1(?![*\\w])")
        static let strikethrough = compile("~~(?!\\s)[^~\\n]+?(?<!\\s)~~")
        static let highlight = compile("==(?!\\s)[^=\\n]+?(?<!\\s)==")

        private static func compile(_ pattern: String) -> NSRegularExpression {
            // Patterns are compile-time constants covered by tests.
            try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }
    }
}
