import Foundation

/// Whether a callout starts folded (`[!note]-`), unfolded (`[!note]+`), or cannot fold.
public enum CalloutFolding: Equatable, Sendable {
    case notFoldable, expanded, collapsed
}

/// One unit of a note's reading view. Headings are their own blocks so a link to a
/// heading can scroll to it; widgets (embeds, bases) sit between Markdown runs.
public indirect enum NotePreviewBlock: Equatable, Sendable {
    case markdown(String)
    case heading(level: Int, text: String, anchor: String)
    case callout(type: String, title: String, folding: CalloutFolding, body: [NotePreviewBlock])
    /// A line that is only an embed, such as `![[Lecture.pdf#page=3]]` or `![[video.mp4]]`.
    case embed(EmbedReference)
    /// The YAML of a ```` ```base ```` code block.
    case baseDefinition(String)
    /// A `$$…$$` block on lines of its own, source included; centered like Obsidian's.
    case displayMath(String)
}

public enum NotePreviewDocument {
    /// An ATX heading. As in CommonMark, trailing `#`s are a closing sequence only after a
    /// space, so `## Learning C#` keeps its `#`.
    private static let headingPattern = try? NSRegularExpression(pattern: "^ {0,3}(#{1,6})[ \\t]+(.+?)(?:[ \\t]+#+)?[ \\t]*$")
    private static let calloutHeaderPattern = try? NSRegularExpression(pattern: "^>[ \\t]?\\[!([A-Za-z0-9_-]+)\\]([+-]?)[ \\t]*(.*)$")
    private static let standaloneEmbedPattern = try? NSRegularExpression(pattern: "^[ \\t]*(!\\[\\[[^\\]\\n]+\\]\\]|!\\[[^\\]\\n]*\\]\\([^)\\n]+\\))[ \\t]*$")

    /// Callouts nested deeper than this stay quoted Markdown. Each level is split by a
    /// recursive call that walks the rest of the callout again, so without a limit a
    /// crafted note of thousands of levels would exhaust the stack of the thread building
    /// the reading view and take time that grows with the square of its size.
    static let maximumCalloutNestingDepth = 16

    /// Splits a note body (frontmatter already removed) into reading-view blocks.
    /// Obsidian `%%` comments are removed first, so a comment around a heading, embed or
    /// formula hides all of it, as in Obsidian.
    public static func blocks(from body: String) -> [NotePreviewBlock] {
        blocks(from: ObsidianInlineMarkup.removingComments(from: body), calloutDepth: 0)
    }

    private static func blocks(from body: String, calloutDepth: Int) -> [NotePreviewBlock] {
        let lines = body.components(separatedBy: "\n").map { line in line.hasSuffix("\r") ? String(line.dropLast()) : line }
        let mathLines = DisplayMathLines(lines)
        var blocks: [NotePreviewBlock] = []
        var pendingMarkdown: [String] = []
        func flushMarkdown() {
            let markdown = pendingMarkdown.joined(separator: "\n")
            if !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { blocks.append(.markdown(markdown)) }
            pendingMarkdown.removeAll()
        }
        var lineIndex = 0
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            // Fenced code passes through untouched; a base fence becomes a base view.
            if let (fence, info) = CodeFence.opening(trimmedLine) {
                let language = info.lowercased()
                var closingIndex = lineIndex + 1
                while closingIndex < lines.count && !CodeFence.closes(fence, lines[closingIndex].trimmingCharacters(in: .whitespaces)) { closingIndex += 1 }
                let fenceLines = Array(lines[lineIndex...min(closingIndex, lines.count - 1)])
                if language == "base" {
                    flushMarkdown()
                    blocks.append(.baseDefinition(fenceLines.dropFirst().dropLast(closingIndex < lines.count ? 1 : 0).joined(separator: "\n")))
                } else {
                    pendingMarkdown.append(contentsOf: fenceLines)
                }
                lineIndex = closingIndex + 1
                continue
            }
            // Display math is a block of its own, so `#` or `>` inside it means nothing.
            if trimmedLine.hasPrefix("$$") {
                let opening = mathLines.opening(at: lineIndex)
                if let opening, opening.isAtLineStart {
                    flushMarkdown()
                    let lastIndex = opening.closingLineIndex ?? lines.count - 1
                    blocks.append(.displayMath(lines[lineIndex...lastIndex].joined(separator: "\n")))
                    lineIndex = lastIndex + 1
                    continue
                }
                // A closed `$$…$$` alone on its line is display math too. With text after
                // it (`$$E=mc^2$$ is famous`) it is inline math in a paragraph.
                if opening == nil, trimmedLine.hasSuffix("$$") {
                    flushMarkdown()
                    blocks.append(.displayMath(line))
                    lineIndex += 1
                    continue
                }
            }
            if let heading = heading(in: line) {
                flushMarkdown()
                blocks.append(.heading(level: heading.level, text: heading.text, anchor: anchor(forHeading: heading.text)))
                lineIndex += 1
                continue
            }
            if calloutDepth < maximumCalloutNestingDepth, let callout = calloutHeader(in: line) {
                flushMarkdown()
                var bodyLines: [String] = []
                var bodyIndex = lineIndex + 1
                while bodyIndex < lines.count && lines[bodyIndex].hasPrefix(">") {
                    let quoted = lines[bodyIndex].dropFirst()
                    bodyLines.append(String(quoted.hasPrefix(" ") ? quoted.dropFirst() : quoted))
                    bodyIndex += 1
                }
                let body = Self.blocks(from: bodyLines.joined(separator: "\n"), calloutDepth: calloutDepth + 1)
                blocks.append(.callout(type: callout.type, title: callout.title, folding: callout.folding, body: body))
                lineIndex = bodyIndex
                continue
            }
            if let embed = standaloneEmbed(in: line) {
                flushMarkdown()
                blocks.append(.embed(embed))
                lineIndex += 1
                continue
            }
            // A formula opened after other text (`- $$` in a list item, `Energy is $$`)
            // stays in its paragraph, closing line included, so that line does not start
            // a formula of its own.
            if let opening = mathLines.opening(at: lineIndex), let closingLineIndex = opening.closingLineIndex {
                pendingMarkdown.append(contentsOf: lines[lineIndex...closingLineIndex])
                lineIndex = closingLineIndex + 1
                continue
            }
            pendingMarkdown.append(line)
            lineIndex += 1
        }
        flushMarkdown()
        return blocks
    }

    /// Obsidian matches heading links by heading text; the anchor normalizes spacing and
    /// case so `[[#Some  Heading]]` and `## some heading` meet.
    public static func anchor(forHeading text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Larger notes are shown as a link instead of being embedded in another note.
    public static let maximumEmbeddedNoteBytes = 1_048_576

    /// The part of a note from a heading up to the next heading of the same or higher
    /// level, as `![[Note#Heading]]` embeds it. The whole body when the heading is absent.
    public static func section(of body: String, headingAnchor: String) -> String {
        sectionIfPresent(of: body, headingAnchor: headingAnchor) ?? body
    }

    /// The section `headingAnchor` names, or nil when the note has no such heading. The
    /// anchor may be Obsidian's heading path, `parent#child`, which names the first
    /// `child` heading inside the `parent` section.
    public static func sectionIfPresent(of body: String, headingAnchor: String) -> String? {
        let lines = body.components(separatedBy: "\n")
        let headings = headingLines(in: lines, of: body)
        guard let targetPosition = headingPosition(matching: headingAnchor, in: headings) else { return nil }
        let target = headings[targetPosition]
        let endLineIndex = headings[(targetPosition + 1)...].first { heading in heading.level <= target.level }?.lineIndex ?? lines.count
        return lines[target.lineIndex..<endLineIndex].joined(separator: "\n")
    }

    /// Headings of a note body in order, for the outline. Headings in code or in `%%`
    /// comments are not headings.
    public static func outline(of body: String) -> [(level: Int, text: String, anchor: String)] {
        headingLines(in: body.components(separatedBy: "\n"), of: body).map { heading in (heading.level, heading.text, heading.anchor) }
    }

    private struct HeadingLine {
        let lineIndex: Int
        let level: Int
        let text: String
        let anchor: String
    }

    /// Every heading with its line, found in one pass that follows code fences and
    /// comments across lines, as the outline and sections both need.
    private static func headingLines(in lines: [String], of body: String) -> [HeadingLine] {
        let commentRanges = ObsidianInlineMarkup.commentRanges(in: body)
        var fenceTracker = CodeFenceTracker()
        var headings: [HeadingLine] = []
        var nextLineStart = 0
        var commentIndex = 0
        for (lineIndex, line) in lines.enumerated() {
            var visibleLine = line
            // Offsets matter only while a comment lies ahead; most notes have none.
            if commentIndex < commentRanges.count {
                let lineRange = NSRange(location: nextLineStart, length: line.utf16.count)
                nextLineStart = NSMaxRange(lineRange) + 1
                while commentIndex < commentRanges.count, NSMaxRange(commentRanges[commentIndex]) <= lineRange.location { commentIndex += 1 }
                if commentIndex < commentRanges.count, commentRanges[commentIndex].location <= lineRange.location { continue }
                // `## Title %%note%%` is the heading "Title", as reading view shows it.
                let commentsOnLine = commentRanges[commentIndex...].prefix { commentRange in commentRange.location < NSMaxRange(lineRange) }
                if !commentsOnLine.isEmpty {
                    let uncommentedLine = NSMutableString(string: line)
                    for commentRange in commentsOnLine.reversed() {
                        let rangeOnLine = NSIntersectionRange(commentRange, lineRange)
                        uncommentedLine.deleteCharacters(in: NSRange(location: rangeOnLine.location - lineRange.location, length: rangeOnLine.length))
                    }
                    visibleLine = uncommentedLine as String
                }
            }
            guard !fenceTracker.isCodeLine(untrimmedLine: line), let heading = heading(in: visibleLine) else { continue }
            headings.append(HeadingLine(lineIndex: lineIndex, level: heading.level, text: heading.text, anchor: anchor(forHeading: heading.text)))
        }
        return headings
    }

    private static func headingPosition(matching headingAnchor: String, in headings: [HeadingLine]) -> Int? {
        if let exactPosition = headings.firstIndex(where: { heading in heading.anchor == headingAnchor }) { return exactPosition }
        // A heading's own text may contain `#` (`C#`), so the path form is tried second.
        let pathAnchors = headingAnchor.components(separatedBy: "#").map(anchor(forHeading:)).filter { pathAnchor in !pathAnchor.isEmpty }
        guard pathAnchors.count > 1 else { return nil }
        var searchRange = headings.startIndex..<headings.endIndex
        var matchedPosition: Int?
        for pathAnchor in pathAnchors {
            guard let position = headings[searchRange].firstIndex(where: { heading in heading.anchor == pathAnchor }) else { return nil }
            matchedPosition = position
            let level = headings[position].level
            let sectionEnd = headings[(position + 1)..<searchRange.upperBound].firstIndex { heading in heading.level <= level } ?? searchRange.upperBound
            searchRange = (position + 1)..<sectionEnd
        }
        return matchedPosition
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        guard line.utf8.contains(UInt8(ascii: "#")) else { return nil }
        let cleanLine = line.hasSuffix("\r") ? String(line.dropLast()) : line
        guard let headingPattern, let match = headingPattern.firstMatch(in: cleanLine, range: NSRange(location: 0, length: (cleanLine as NSString).length)) else { return nil }
        let source = cleanLine as NSString
        return (source.substring(with: match.range(at: 1)).count, source.substring(with: match.range(at: 2)))
    }

    private static func calloutHeader(in line: String) -> (type: String, title: String, folding: CalloutFolding)? {
        guard let calloutHeaderPattern, let match = calloutHeaderPattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return nil }
        let source = line as NSString
        let type = source.substring(with: match.range(at: 1)).lowercased()
        let foldMarker = source.substring(with: match.range(at: 2))
        let writtenTitle = source.substring(with: match.range(at: 3))
        let title = writtenTitle.isEmpty ? type.prefix(1).uppercased() + type.dropFirst() : writtenTitle
        return (type, title, foldMarker == "-" ? .collapsed : foldMarker == "+" ? .expanded : .notFoldable)
    }

    private static func standaloneEmbed(in line: String) -> EmbedReference? {
        guard let standaloneEmbedPattern, standaloneEmbedPattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil else { return nil }
        let embedLocation = (line as NSString).range(of: "!").location
        guard let embed = EmbedLocator.embed(at: embedLocation + 1, in: line as NSString) else { return nil }
        // A web image (`![](https://…)`) is not a vault file. It stays Markdown, which the
        // renderer draws from the web as it does an inline one. Only the destination
        // counts, not a title written after it.
        let destination = embed.target.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? embed.target
        guard embed.isWiki || URL(string: destination)?.scheme == nil else { return nil }
        return embed
    }
}

/// Inline Obsidian syntax that Markdown renderers do not know, rewritten for the
/// reading view only. Private-use characters mark colored and highlighted runs so the
/// renderer's parser keeps them in place; the view turns them into attributes.
public enum ObsidianInlineMarkup {
    public static let colorStartMarker: Character = "\u{E000}"
    public static let colorHexEndMarker: Character = "\u{E001}"
    public static let colorEndMarker: Character = "\u{E002}"
    public static let highlightStartMarker: Character = "\u{E003}"
    public static let highlightEndMarker: Character = "\u{E004}"
    /// Stand for a task's `[ ]` and `[x]`, which the reading view draws as checkboxes.
    public static let uncheckedTaskMarker: Character = "\u{E005}"
    public static let checkedTaskMarker: Character = "\u{E006}"
    /// Around a footnote's number, which the reading view raises and shrinks.
    public static let footnoteStartMarker: Character = "\u{E007}"
    public static let footnoteEndMarker: Character = "\u{E008}"
    /// The markers from the color start marker to the checked task marker. The footnote
    /// markers are left out: the reading view inserts them before this rewrite runs.
    private static let markerScalarValues: ClosedRange<UInt32> = 0xE000...0xE006
    /// Any single status character makes a task, as in Obsidian: a space is open, and
    /// anything else (`x`, `/`, `-`, `>`) is shown checked.
    private static let taskPattern = try? NSRegularExpression(pattern: "^(\\s*(?:>\\s*)*(?:[-*+]|\\d+[.)])\\s+)\\[([^\\]\\n])\\](?=\\s|$)")
    private static let highlightPattern = try? NSRegularExpression(pattern: "(?<![=~])==(?![\\s=~])([^=\\n]+?)(?<!\\s)==(?!=)")
    /// A single-backtick code span, whose `==` is not a highlight.
    private static let highlightCodeSpanPattern = try? NSRegularExpression(pattern: "`[^`]+`")
    private static let tableDisplayMathPattern = try? NSRegularExpression(pattern: "\\$\\$([^$\\n]+)\\$\\$")
    /// `$$…$$` on one line, or Obsidian's inline `$…$`: no space just inside either `$`, and
    /// no digit after the closing one, so "$5 and $10" is not math.
    private static let mathSpanPattern = try? NSRegularExpression(pattern: "\\$\\$(?!\\$)([^\\n]+?)\\$\\$|(?<![\\\\$])\\$(?![\\s$])([^$\\n]*?[^\\s\\\\])?\\$(?![\\d$])")
    private static let codeSpanPattern = try? NSRegularExpression(pattern: "(?<!`)(`+)(?!`)[^\\n]*?(?<!`)\\1(?!`)")
    private static let quotePrefixPattern = try? NSRegularExpression(pattern: "^\\s*(?:>\\s?)*")

    /// Rewrites color sections, highlights, tasks, and comments for display.
    public static func preparedForReading(_ markdown: String, colorsEnabled: Bool, paletteHexByName: [String: String]) -> String {
        var text = removingBlockIdentifiers(from: removingComments(from: replacingMarkerCharacters(in: markdown)))
        text = displayMathInTableCellsMadeInline(text)
        text = protectingMath(in: text)
        if colorsEnabled { text = markingColors(in: text, paletteHexByName: paletteHexByName) }
        return markingTasks(in: markingHighlights(in: text))
    }

    /// A marker character already in the note, such as an icon-font glyph, would be read
    /// as formatting: a checkbox, or a color that deletes the text after it. Each one is
    /// shown as U+FFFD, the standard sign for a character that cannot be displayed; these
    /// private-use code points have no standard appearance of their own.
    static func replacingMarkerCharacters(in markdown: String) -> String {
        guard markdown.unicodeScalars.contains(where: { scalar in markerScalarValues.contains(scalar.value) }) else { return markdown }
        var scalars = String.UnicodeScalarView()
        for scalar in markdown.unicodeScalars {
            scalars.append(markerScalarValues.contains(scalar.value) ? "\u{FFFD}" : scalar)
        }
        return String(scalars)
    }

    static func markingTasks(in markdown: String) -> String {
        guard let taskPattern else { return markdown }
        var fenceTracker = CodeFenceTracker()
        return markdown.components(separatedBy: "\n").map { line in
            if fenceTracker.isCodeLine(untrimmedLine: line) { return line }
            let source = line as NSString
            guard let match = taskPattern.firstMatch(in: line, range: NSRange(location: 0, length: source.length)) else { return line }
            let marker = source.substring(with: match.range(at: 2)) == " " ? uncheckedTaskMarker : checkedTaskMarker
            return source.substring(with: match.range(at: 1)) + String(marker) + source.substring(from: NSMaxRange(match.range))
        }.joined(separator: "\n")
    }

    private static let blockIdentifierPattern = try? NSRegularExpression(pattern: "(?:[ \\t]+|^)\\^[A-Za-z0-9-]+[ \\t]*$")

    /// Block `^id`s mark blocks for links; Obsidian does not show them when reading. Code
    /// and display math are left alone, so `x ^2` at the end of a formula line stays.
    static func removingBlockIdentifiers(from markdown: String) -> String {
        guard let blockIdentifierPattern, markdown.contains("^") else { return markdown }
        let lines = markdown.components(separatedBy: "\n")
        let mathLines = DisplayMathLines(lines)
        var fenceTracker = CodeFenceTracker()
        var mathClosingLineIndex: Int?
        var outputLines: [String] = []
        outputLines.reserveCapacity(lines.count)
        for (lineIndex, line) in lines.enumerated() {
            let source = line as NSString
            var searchStart = 0
            if let closingLineIndex = mathClosingLineIndex {
                guard lineIndex == closingLineIndex, let closingOffset = DisplayMathLines.closingDelimiterOffset(in: line) else {
                    outputLines.append(line)
                    continue
                }
                // An identifier may follow the closing `$$` of a formula.
                mathClosingLineIndex = nil
                searchStart = closingOffset + 2
            } else if fenceTracker.isCodeLine(untrimmedLine: line) {
                outputLines.append(line)
                continue
            } else if let opening = mathLines.opening(at: lineIndex) {
                // The end of the line, where an identifier would be, is inside the formula.
                mathClosingLineIndex = opening.closingLineIndex ?? lines.count
                outputLines.append(line)
                continue
            }
            let searchRange = NSRange(location: searchStart, length: source.length - searchStart)
            outputLines.append(blockIdentifierPattern.stringByReplacingMatches(in: line, range: searchRange, withTemplate: ""))
        }
        return outputLines.joined(separator: "\n")
    }

    /// Removes Obsidian `%%` comments, markers included. `%%` in code is text.
    static func removingComments(from markdown: String) -> String {
        let ranges = commentRanges(in: markdown)
        guard !ranges.isEmpty else { return markdown }
        let output = NSMutableString(string: markdown)
        for range in ranges.reversed() { output.deleteCharacters(in: range) }
        return output as String
    }

    /// UTF-16 ranges of the `%%` comments in `text`, markers included. A comment may span
    /// lines and hide fences, headings and embeds. Outside a comment, `%%` in fenced code
    /// or a code span is text, such as a printf format or a Jupyter `# %%` cell marker. A
    /// comment that is never closed is left as written.
    static func commentRanges(in markdown: String) -> [NSRange] {
        guard containsCommentMarker(markdown) else { return [] }
        var ranges: [NSRange] = []
        var fenceTracker = CodeFenceTracker()
        var commentStart: Int?
        var lineStart = 0
        for line in markdown.components(separatedBy: "\n") {
            defer { lineStart += line.utf16.count + 1 }
            // Inside a comment a fence is hidden text, so it neither opens nor closes code.
            // A fence in a quote or callout (`> ```) is code too.
            let unquotedLine = line.drop { character in character == ">" || character == " " || character == "\t" }
            if commentStart == nil, fenceTracker.isCodeLine(untrimmedLine: unquotedLine) { continue }
            guard line.utf8.contains(UInt8(ascii: "%")) else { continue }
            let lineSource = line as NSString
            let codeRanges = codeSpanPattern?.matches(in: line, range: NSRange(location: 0, length: lineSource.length)).map(\.range) ?? []
            var searchStart = 0
            while searchStart < lineSource.length {
                let marker = lineSource.range(of: "%%", range: NSRange(location: searchStart, length: lineSource.length - searchStart))
                guard marker.location != NSNotFound else { break }
                searchStart = NSMaxRange(marker)
                if let start = commentStart {
                    ranges.append(NSRange(location: start, length: lineStart + NSMaxRange(marker) - start))
                    commentStart = nil
                } else if !codeRanges.contains(where: { codeRange in NSLocationInRange(marker.location, codeRange) }) {
                    commentStart = lineStart + marker.location
                }
            }
        }
        return ranges
    }

    /// Whether `markdown` holds `%%` anywhere. Every note is checked on every render, and
    /// most have no comment, so this compares bytes instead of characters.
    private static func containsCommentMarker(_ markdown: String) -> Bool {
        let percentSign = UInt8(ascii: "%")
        var previousByteIsPercentSign = false
        for byte in markdown.utf8 {
            if byte == percentSign, previousByteIsPercentSign { return true }
            previousByteIsPercentSign = byte == percentSign
        }
        return false
    }

    /// A `$$…$$` inside a table row would render as a block and break the row, so it is
    /// shown as inline math there. A table written in a code block is left as written.
    static func displayMathInTableCellsMadeInline(_ markdown: String) -> String {
        guard let tableDisplayMathPattern, markdown.contains("$$") else { return markdown }
        var fenceTracker = CodeFenceTracker()
        return markdown.components(separatedBy: "\n").map { line in
            if fenceTracker.isCodeLine(untrimmedLine: line) { return line }
            guard line.trimmingCharacters(in: .whitespaces).hasPrefix("|") else { return line }
            let source = line as NSString
            return tableDisplayMathPattern.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: source.length), withTemplate: "\\$$1\\$")
        }.joined(separator: "\n")
    }

    /// Makes every formula reach the math renderer exactly as written. The renderer finds
    /// math in the text Markdown leaves behind, so a display block is put on one line (a
    /// line break would split it), and Markdown punctuation inside math is backslash-escaped
    /// so `\\{`, `\\\\`, `*` and `_` survive parsing as LaTeX. Code is left alone.
    static func protectingMath(in markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        let mathLines = DisplayMathLines(lines)
        var fenceTracker = CodeFenceTracker()
        var outputLines: [String] = []
        var lineIndex = 0
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let prefixLength = quotePrefixLength(of: line)
            let content = String(line.dropFirst(prefixLength))
            if fenceTracker.isCodeLine(untrimmedLine: content) {
                outputLines.append(line)
                lineIndex += 1
                continue
            }
            guard let opening = mathLines.opening(at: lineIndex) else {
                outputLines.append(protectingInlineMath(in: line))
                lineIndex += 1
                continue
            }
            // An unclosed display block runs to the end, as in Obsidian.
            let closingLineIndex = opening.closingLineIndex ?? lines.count - 1
            outputLines.append(joinedDisplayMath(opening: opening, openingLine: line, openingQuotePrefixLength: prefixLength,
                                                 followingLines: lines[(lineIndex + 1)..<(closingLineIndex + 1)],
                                                 isClosed: opening.closingLineIndex != nil))
            lineIndex = closingLineIndex + 1
        }
        return outputLines.joined(separator: "\n")
    }

    /// One line holding a display formula that was written over several: the text before
    /// the opening `$$` (only its quote markers when the formula starts the line), the
    /// LaTeX between the delimiters, and any text after the closing `$$`.
    private static func joinedDisplayMath(opening: DisplayMathLines.Opening, openingLine: String, openingQuotePrefixLength: Int,
                                          followingLines: ArraySlice<String>, isClosed: Bool) -> String {
        let openingSource = openingLine as NSString
        let leadingText = opening.isAtLineStart
            ? String(openingLine.prefix(openingQuotePrefixLength))
            : protectingInlineMath(in: openingSource.substring(to: opening.delimiterOffset))
        var latexLines = [openingSource.substring(from: opening.delimiterOffset + 2)]
        var trailingText = ""
        for (position, line) in zip(followingLines.indices, followingLines) {
            let lineSource = line as NSString
            let quotePrefixEnd = (String(line.prefix(quotePrefixLength(of: line))) as NSString).length
            guard isClosed, position == followingLines.indices.last, let closingOffset = DisplayMathLines.closingDelimiterOffset(in: line) else {
                latexLines.append(lineSource.substring(from: quotePrefixEnd))
                continue
            }
            let latexStart = min(quotePrefixEnd, closingOffset)
            latexLines.append(lineSource.substring(with: NSRange(location: latexStart, length: closingOffset - latexStart)))
            trailingText = protectingInlineMath(in: lineSource.substring(from: closingOffset + 2))
        }
        let latex = latexLines.map(withoutLaTeXComment).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return leadingText + "$$ " + escapedForMarkdown(LaTeXCompatibility.normalized(latex), isInTableRow: false) + " $$" + trailingText
    }

    private static func protectingInlineMath(in line: String) -> String {
        guard line.contains("$"), let mathSpanPattern else { return line }
        let source = line as NSString
        let wholeLine = NSRange(location: 0, length: source.length)
        let codeRanges = codeSpanPattern?.matches(in: line, range: wholeLine).map(\.range) ?? []
        let isInTableRow = line.trimmingCharacters(in: .whitespaces).hasPrefix("|")
        let output = NSMutableString(string: line)
        for match in mathSpanPattern.matches(in: line, range: wholeLine).reversed()
        where !codeRanges.contains(where: { codeRange in NSIntersectionRange(codeRange, match.range).length > 0 }) {
            let contentRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            guard contentRange.location != NSNotFound else { continue }
            output.replaceCharacters(in: contentRange, with: escapedForMarkdown(LaTeXCompatibility.normalized(source.substring(with: contentRange)), isInTableRow: isInTableRow))
        }
        return output as String
    }

    /// Backslash-escapes ASCII punctuation, which CommonMark then reads as the character
    /// itself. In a table row, `\\|` is how a pipe is written inside a cell, so it stays one.
    private static func escapedForMarkdown(_ latex: String, isInTableRow: Bool) -> String {
        let text = isInTableRow ? latex.replacingOccurrences(of: "\\|", with: "|") : latex
        var escaped = ""
        escaped.reserveCapacity(text.utf8.count * 2)
        for character in text {
            if character.isASCII, character.isPunctuation || character.isSymbol { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    /// LaTeX ignores everything after an unescaped `%`; joined lines must not inherit that.
    private static func withoutLaTeXComment(_ line: String) -> String {
        var isEscaped = false
        for (offset, character) in line.enumerated() {
            if character == "%" && !isEscaped { return String(line.prefix(offset)) }
            isEscaped = character == "\\" && !isEscaped
        }
        return line
    }

    private static func quotePrefixLength(of line: String) -> Int {
        guard let quotePrefixPattern, line.hasPrefix(">") || line.first?.isWhitespace == true else { return 0 }
        let prefixRange = quotePrefixPattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))?.range
        // Only a quote prefix counts; plain indentation stays part of the line.
        guard let prefixRange, (line as NSString).substring(with: prefixRange).contains(">") else { return 0 }
        return (line as NSString).substring(with: prefixRange).count
    }

    static func markingColors(in markdown: String, paletteHexByName: [String: String]) -> String {
        let source = markdown as NSString
        let sections = TextColorMarkup.sections(in: source, paletteHexByName: paletteHexByName)
        guard !sections.isEmpty else { return markdown }
        // Replacements are applied from the end so earlier ranges stay valid.
        var replacements: [(range: NSRange, text: String)] = []
        for section in sections {
            replacements.append((section.openingMarkerRange, String(colorStartMarker) + section.hexColor + String(colorHexEndMarker)))
            if let closingRange = section.closingMarkerRange {
                replacements.append((closingRange, String(colorEndMarker)))
            } else {
                replacements.append((NSRange(location: NSMaxRange(section.contentRange), length: 0), String(colorEndMarker)))
            }
        }
        let output = NSMutableString(string: markdown)
        for replacement in replacements.sorted(by: { firstReplacement, secondReplacement in
            firstReplacement.range.location > secondReplacement.range.location
                || (firstReplacement.range.location == secondReplacement.range.location && firstReplacement.range.length > secondReplacement.range.length)
        }) {
            output.replaceCharacters(in: replacement.range, with: replacement.text)
        }
        return output as String
    }

    static func markingHighlights(in markdown: String) -> String {
        guard let highlightPattern else { return markdown }
        var fenceTracker = CodeFenceTracker()
        return markdown.components(separatedBy: "\n").map { line in
            if fenceTracker.isCodeLine(untrimmedLine: line) { return line }
            guard line.contains("==") else { return line }
            let source = line as NSString
            let codeRanges = highlightCodeSpanPattern?.matches(in: line, range: NSRange(location: 0, length: source.length)).map(\.range) ?? []
            let output = NSMutableString(string: line)
            for match in highlightPattern.matches(in: line, range: NSRange(location: 0, length: source.length)).reversed()
            where !codeRanges.contains(where: { codeRange in NSIntersectionRange(codeRange, match.range).length > 0 }) {
                output.replaceCharacters(in: match.range, with: String(highlightStartMarker) + source.substring(with: match.range(at: 1)) + String(highlightEndMarker))
            }
            return output as String
        }.joined(separator: "\n")
    }
}

extension CodeFenceTracker {
    /// `isCodeLine` for a line as written. Only a line whose first character after
    /// indentation is a backtick or tilde can open or close a fence, so other lines are
    /// answered without trimming them: long notes are scanned this way on every render.
    mutating func isCodeLine(untrimmedLine line: some StringProtocol) -> Bool {
        guard let firstCharacter = line.first(where: { character in !character.isWhitespace }),
              firstCharacter == "`" || firstCharacter == "~" else { return isInsideFence }
        return isCodeLine(line.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
