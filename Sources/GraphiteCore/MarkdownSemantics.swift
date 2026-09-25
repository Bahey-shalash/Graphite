import Foundation
import Markdown
import Yams

public struct NoteLink: Codable, Hashable, Sendable {
    public let target: String
    public let label: String?
    public let isEmbed: Bool
    public let isWiki: Bool
    public let location: Int
    /// 0 for a Markdown link whose source text could not be located exactly (see
    /// MarkdownSemantics.parse); such a link is indexed but never rewritten.
    public let length: Int
    public var range: NSRange { NSRange(location: location, length: length) }
}

public struct NoteSemantics: Sendable {
    public let links: [NoteLink]
    public let headings: [String]
    public let tags: [String]
    public let aliases: [String]
    public let body: String
    public let frontmatter: String?
}

public enum MarkdownSemantics {
    /// Captures the YAML between the delimiters; works for LF and CRLF files and for
    /// empty frontmatter.
    private static let frontmatterPattern = try? NSRegularExpression(pattern: "\\A---\\r?\\n(?:([\\s\\S]*?)\\r?\\n)?(?:---|\\.\\.\\.)[ \\t]*(?:\\r?\\n|$)")
    /// Group 1 is the embed's `!`, group 2 the link's content.
    private static let wikilinkPattern = try? NSRegularExpression(pattern: "(!?)\\[\\[([^\\]\\n]+)\\]\\]")

    private enum PatternError: Error {
        /// The fixed patterns above failed to compile, which only a regular expression
        /// engine change could cause.
        case unavailable
    }

    public static func parse(_ source: String) throws -> NoteSemantics {
        guard let frontmatterPattern, let wikilinkPattern else { throw PatternError.unavailable }
        var body = source
        var frontmatter: String?
        var prefixCount = 0
        var aliases: [String] = []
        var tags: [String] = []
        // Frontmatter stays byte-for-byte in source. Yams reads properties only.
        let sourceString = source as NSString
        if let match = frontmatterPattern.firstMatch(in: source, range: NSRange(location: 0, length: sourceString.length)) {
            let yamlRange = match.range(at: 1)
            let yaml = yamlRange.location == NSNotFound ? "" : sourceString.substring(with: yamlRange)
            frontmatter = yaml; prefixCount = match.range.length
            body = sourceString.substring(from: prefixCount)
            // Invalid properties do not make the note body unsearchable. The
            // original YAML remains untouched for correction in the source editor.
            if let values = BoundedYAML.load(yaml) as? [String: Any] {
                aliases = stringList(values["aliases"] ?? values["alias"])
                // Obsidian also reads `tags: fiction, classic` (text) as separate tags.
                tags = stringList(values["tags"] ?? values["tag"])
                    .flatMap { tag in tag.split(whereSeparator: { character in character == "," || character.isWhitespace }).map(String.init) }
                    .map { tag in tag.hasPrefix("#") ? String(tag.dropFirst()) : tag }
                    .filter { tag in !tag.isEmpty }
            }
        }
        // A note nested too deeply for swift-markdown keeps its wikilinks and tags; it only
        // loses Markdown-syntax links, headings and code exclusions (see MarkdownNesting).
        let document = MarkdownNesting.exceedsSafeDepth(body) ? nil : Document(parsing: body)
        var links: [NoteLink] = []
        var headings: [String] = []
        var excluded: [NSRange] = []
        let bodyString = body as NSString
        // Ranges are converted after the walk: a link can end on a line whose columns
        // only a node the walk reaches later calibrates.
        var locationConverter = MarkdownSourceLocationConverter(body)
        var pendingRanges: [(role: SourceRangeRole, range: SourceRange, containerIndex: Int?)] = []
        var currentContainerIndex: Int?
        var stack: [(node: any Markup, followsLineBreak: Bool)] = document.map { document in [(document, false)] } ?? []
        while let (node, followsLineBreak) = stack.popLast() {
            if node is Paragraph || node is Heading {
                currentContainerIndex = locationConverter.addInlineContainer(node)
            } else if !(node is InlineMarkup) {
                currentContainerIndex = nil
            }
            let role: SourceRangeRole? = switch node {
            case is CodeBlock, is HTMLBlock: .codeBlock
            case is InlineCode: .inlineCode
            case is InlineHTML: .inlineHTML
            case let link as Link: link.destination.map { destination in .link(target: destination, label: link.plainText, isEmbed: false) }
            case let image as Markdown.Image: image.source.map { destination in .link(target: destination, label: image.plainText, isEmbed: true) }
            default: nil
            }
            if let range = node.range {
                if let currentContainerIndex, node is InlineMarkup {
                    locationConverter.recordInlineRange(range, of: role, startsLineText: followsLineBreak, inContainer: currentContainerIndex)
                }
                if let role { pendingRanges.append((role, range, currentContainerIndex)) }
            }
            if node is CodeBlock || node is InlineCode || node is HTMLBlock || node is InlineHTML { continue }
            if let heading = node as? Heading { headings.append(heading.plainText) }
            let children = Array(node.children)
            func isLineBreak(at childIndex: Int) -> Bool { childIndex >= 0 && (children[childIndex] is SoftBreak || children[childIndex] is LineBreak) }
            for (childIndex, child) in children.enumerated().reversed() {
                // A break right after another is a line holding only a backslash hard
                // break, so the node after it does not start the first break's line.
                stack.append((child, isLineBreak(at: childIndex - 1) && !isLineBreak(at: childIndex - 2)))
            }
        }
        locationConverter.resolveInlineLines()
        // A range that does not hold the syntax of its node was misplaced (see
        // MarkdownSourceLocationConverter). A rename rewrites Markdown links at their
        // ranges, so such a link keeps an empty range and is never rewritten, and code
        // in its paragraph is then found from the text instead.
        var unreliableContainerIndexes = Set<Int>()
        var markdownLinkRanges = Set<NSRange>()
        for pending in pendingRanges {
            let range = locationConverter.utf16Range(of: pending.range, role: pending.role, containerIndex: pending.containerIndex)
            let sourceText = bodyString.substring(with: range)
            switch pending.role {
            case .codeBlock:
                excluded.append(range)
            case .inlineCode, .inlineHTML:
                let delimiters = pending.role == .inlineCode ? ("`", "`") : ("<", ">")
                if sourceText.hasPrefix(delimiters.0) && sourceText.hasSuffix(delimiters.1) {
                    excluded.append(range)
                } else if let containerIndex = pending.containerIndex {
                    unreliableContainerIndexes.insert(containerIndex)
                }
            case .link(let target, let label, let isEmbed):
                if MarkdownLinkSource.isWritten(sourceText, destination: target, plainText: label, isImage: isEmbed), markdownLinkRanges.insert(range).inserted {
                    links.append(NoteLink(target: target, label: label, isEmbed: isEmbed, isWiki: false, location: prefixCount + range.location, length: range.length))
                    excluded.append(range)
                } else {
                    links.append(NoteLink(target: target, label: label, isEmbed: isEmbed, isWiki: false, location: prefixCount + range.location, length: 0))
                    if let containerIndex = pending.containerIndex { unreliableContainerIndexes.insert(containerIndex) }
                }
            }
        }
        for containerIndex in unreliableContainerIndexes {
            let containerRange = locationConverter.utf16Range(ofContainer: containerIndex)
            excluded += MarkdownCodeRanges.codeSpans(in: bodyString, range: containerRange).map(\.range)
        }
        func escaped(_ location: Int) -> Bool {
            var characterIndex = location, backslashCount = 0
            while characterIndex > 0 && bodyString.character(at: characterIndex - 1) == 92 { backslashCount += 1; characterIndex -= 1 }
            return backslashCount % 2 == 1
        }
        let codeAndMarkdownLinks = SortedRangeSet(excluded)
        for match in wikilinkPattern.matches(in: body, range: NSRange(location: 0, length: bodyString.length)) {
            var linkRange = match.range
            var isEmbed = match.range(at: 1).length > 0
            if escaped(linkRange.location) {
                // `\![[E]]` is a literal `!` before an ordinary link; `\[[E]]` is no link.
                guard isEmbed else { continue }
                isEmbed = false
                linkRange = NSRange(location: linkRange.location + 1, length: linkRange.length - 1)
            }
            guard !codeAndMarkdownLinks.intersects(linkRange) else { continue }
            let wikilinkContent = bodyString.substring(with: match.range(at: 2))
            let (target, label) = WikiLinkResolver.targetAndLabel(of: wikilinkContent)
            guard !target.isEmpty else { continue }
            links.append(NoteLink(target: target, label: label, isEmbed: isEmbed, isWiki: true, location: prefixCount + linkRange.location, length: linkRange.length))
        }
        // `[[#Heading]]` names a heading, not a tag.
        excluded += links.filter(\.isWiki).map { link in NSRange(location: link.location - prefixCount, length: link.length) }
        let codeAndLinks = SortedRangeSet(excluded)
        for match in TagSyntax.pattern.matches(in: body, range: NSRange(location: 0, length: bodyString.length)) where !codeAndLinks.intersects(match.range) && !escaped(match.range.location) {
            tags.append(bodyString.substring(with: match.range(at: 1)))
        }
        return NoteSemantics(links: links.sorted { leftLink, rightLink in leftLink.location < rightLink.location }, headings: headings, tags: Array(Set(tags)).sorted(), aliases: aliases, body: body, frontmatter: frontmatter)
    }
    /// Text items of a property; numbers and other scalars in a list count as text, so
    /// `tags: [fiction, 2024]` keeps both instead of dropping the list.
    private static func stringList(_ value: Any?) -> [String] {
        if let list = value as? [Any] { return list.compactMap(scalarText) }
        return scalarText(value).map { text in [text] } ?? []
    }

    private static func scalarText(_ value: Any?) -> String? {
        switch value {
        case let text as String: text
        case let number as Int: String(number)
        // `Int(exactly:)` rather than `Int(_:)`: a vault file can hold `1e300` or `.inf`,
        // which do not fit in Int and would trap during indexing on every launch.
        case let number as Double: Int(exactly: number).map { whole in String(whole) } ?? String(number)
        case let flag as Bool: String(flag)
        default: nil
        }
    }
}

/// What a Markdown node's source range is used for.
private enum SourceRangeRole: Equatable {
    /// A code or HTML block, where wikilinks and tags are text.
    case codeBlock
    /// Inline code or HTML, where wikilinks and tags are text too.
    case inlineCode, inlineHTML
    /// A Markdown link or image; its text is not searched for wikilinks or tags either.
    case link(target: String, label: String, isEmbed: Bool)
}

/// How a misplaced range is recognized: a Markdown link's source text has the shape of
/// a link, `[text](destination)`, `[text][label]`, `[text]` or `<destination>`.
private enum MarkdownLinkSource {
    private static let escapedPunctuation = try? NSRegularExpression(pattern: "\\\\([!-/:-@\\[-`{-~])")
    /// A CommonMark entity or numeric character reference, such as `&amp;` or `&#38;`.
    private static let characterReference = try? NSRegularExpression(pattern: "&(?:#[0-9]{1,7}|#[xX][0-9A-Fa-f]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});")
    private static let backslash = UInt16(UInt8(ascii: "\\"))
    private static let backtick = UInt16(UInt8(ascii: "`"))
    private static let openingBracket = UInt16(UInt8(ascii: "["))
    private static let closingBracket = UInt16(UInt8(ascii: "]"))
    private static let openingParenthesis = UInt16(UInt8(ascii: "("))
    private static let closingParenthesis = UInt16(UInt8(ascii: ")"))

    /// Whether `sourceText` is written as a link (or image) to `destination`.
    static func isWritten(_ sourceText: String, destination: String, plainText: String, isImage: Bool) -> Bool {
        let units = Array(sourceText.utf16)
        let textStart = isImage ? 1 : 0
        guard !isImage || sourceText.hasPrefix("!") else { return false }
        guard textStart < units.count, units[textStart] == openingBracket else {
            // An autolink, `<https://…>`, or a bare web address.
            return !isImage && ((sourceText.hasPrefix("<") && sourceText.hasSuffix(">")) || sourceText == plainText)
        }
        guard let textEnd = closingBracketIndex(in: units, openingAt: textStart) else { return false }
        let restStart = textEnd + 1
        // A shortcut reference, `[text]`.
        guard restStart < units.count else { return true }
        switch units[restStart] {
        case openingBracket:
            // A full or collapsed reference; its label holds no unescaped bracket.
            return closingBracketIndex(in: units, openingAt: restStart) == units.count - 1
        case openingParenthesis:
            guard units.last == closingParenthesis else { return false }
            let fullRange = NSRange(location: 0, length: units.count)
            let unescapedText = escapedPunctuation?.stringByReplacingMatches(in: sourceText, range: fullRange, withTemplate: "$1") ?? sourceText
            // The parser decodes character references (`Fish&amp;Chips.md`) in the destination.
            // They are not decoded here, so a link written with one is accepted by its shape.
            let hasCharacterReference = characterReference?.firstMatch(in: sourceText, range: fullRange) != nil
            return sourceText.contains(destination) || unescapedText.contains(destination) || hasCharacterReference
        default:
            return false
        }
    }

    /// The index of the `]` matching the `[` at `openingIndex`, skipping escaped
    /// characters and code spans.
    private static func closingBracketIndex(in units: [UInt16], openingAt openingIndex: Int) -> Int? {
        var depth = 0
        var index = openingIndex
        while index < units.count {
            let unit = units[index]
            if unit == backslash {
                index += 2
                continue
            }
            if unit == backtick {
                var runEnd = index
                while runEnd < units.count && units[runEnd] == backtick { runEnd += 1 }
                index = closingBacktickRunEnd(in: units, from: runEnd, length: runEnd - index) ?? runEnd
                continue
            }
            if unit == openingBracket { depth += 1 }
            if unit == closingBracket {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    private static func closingBacktickRunEnd(in units: [UInt16], from start: Int, length: Int) -> Int? {
        var index = start
        while index < units.count {
            guard units[index] == backtick else {
                index += 1
                continue
            }
            var runEnd = index
            while runEnd < units.count && units[runEnd] == backtick { runEnd += 1 }
            if runEnd - index == length { return runEnd }
            index = runEnd
        }
        return nil
    }
}

/// Converts swift-markdown source locations into UTF-16 offsets of the parsed text.
///
/// cmark reports a 1-based line, ending lines at "\n", "\r\n" and a lone "\r", and a
/// 1-based column in UTF-8 bytes. Splitting the text into Characters instead would keep
/// every line of a CRLF note on one line, because "\r\n" is a single Character.
///
/// Block nodes have columns counted from the start of their line. Inline nodes do not.
/// cmark joins a paragraph's lines into one text, keeping each continuation line from a
/// start that depends on its containers (after the indentation of a regular line, but
/// from the last matched container of a lazy one, indentation included). Only the line
/// breaks it parses as breaks, and those inside code spans and HTML, start a new line
/// number; there, columns restart at the kept start of the line, plus the paragraph's
/// first column. A backslash hard break and a break inside a link destination or title
/// leave the line number as it is, and the columns run on across the break.
///
/// So each paragraph's inline positions are replayed in source order: a new line number
/// belongs to the line after the one the positions so far reached, and the node right
/// after a line break, which starts where that line's text starts, calibrates its
/// columns. A column past the end of its line runs on into the following lines. A line
/// with no such node (one continuing a code span or HTML) is taken to be kept from its
/// text, as a regular continuation line is. Lines cmark drops from the start of a
/// paragraph, its link reference definitions, are not modeled; the ranges they misplace
/// are caught by checking the text at each range (see MarkdownSemantics.parse).
private struct MarkdownSourceLocationConverter {
    /// A paragraph or heading, and its inline nodes' positions.
    private struct InlineContainer {
        let range: SourceRange
        let quoteDepth: Int
        var positions: [InlinePosition] = []
        /// For each reported line number, the line it is and where its columns start.
        var originByReportedLine: [Int: LineOrigin] = [:]
        /// For each reported line number whose columns run past its line, the following
        /// lines they reach, found once and in order, so a long run of hard breaks stays linear.
        var spillStepsByReportedLine: [Int: [SpillStep]] = [:]

        var firstColumn: Int { range.lowerBound.column }
    }

    private struct InlinePosition {
        let location: SourceLocation
        let columnRule: ColumnRule
        /// The node follows a line break, so it starts where its line's text starts.
        let startsLineText: Bool
    }

    /// How a reported column counts bytes on its line.
    private enum ColumnRule {
        /// From the line's origin, where the paragraph's first column falls.
        case fromOrigin
        /// The end of a code span or HTML tag that spans lines: cmark counts it from the
        /// kept start of its last line, without the paragraph's first column (for code,
        /// swift-markdown then adds the closing backticks).
        case codeEndFromKeptStart, htmlEndFromKeptStart
    }

    private struct LineOrigin {
        let lineIndex: Int
        /// The byte where the paragraph's first column falls on this line.
        let byte: Int
    }

    /// A column whose byte on its origin line would be at least `minimumByte` lands on
    /// `lineIndex`, `shift` bytes further on.
    private struct SpillStep {
        let lineIndex: Int
        let minimumByte: Int
        let shift: Int
    }

    private static let lineFeed = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")

    private let bytes: [UInt8]
    /// UTF-8 offset where each line starts.
    private var lineStarts: [Int] = [0]
    /// UTF-8 offset where each line's text ends, before its line break.
    private var lineContentEnds: [Int] = []
    private var containers: [InlineContainer] = []
    /// The last converted UTF-8 offset and its UTF-16 offset. Ranges arrive in document
    /// order, so walking on from the previous answer keeps a whole parse linear instead of
    /// decoding every line's prefix again for each node on it.
    private var cursorByte = 0
    private var cursorUTF16 = 0

    init(_ text: String) {
        bytes = Array(text.utf8)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            guard byte == Self.lineFeed || byte == Self.carriageReturn else {
                index += 1
                continue
            }
            lineContentEnds.append(index)
            let isCRLF = byte == Self.carriageReturn && index + 1 < bytes.count && bytes[index + 1] == Self.lineFeed
            index += isCRLF ? 2 : 1
            lineStarts.append(index)
        }
        lineContentEnds.append(bytes.count)
    }

    /// Starts collecting the inline positions of a paragraph or heading; returns its index.
    mutating func addInlineContainer(_ block: any Markup) -> Int? {
        guard let range = block.range else { return nil }
        var quoteDepth = 0
        var ancestor = block.parent
        while let current = ancestor {
            if current is BlockQuote { quoteDepth += 1 }
            ancestor = current.parent
        }
        containers.append(InlineContainer(range: range, quoteDepth: quoteDepth))
        return containers.count - 1
    }

    mutating func recordInlineRange(_ range: SourceRange, of role: SourceRangeRole?, startsLineText: Bool, inContainer containerIndex: Int) {
        containers[containerIndex].positions.append(InlinePosition(location: range.lowerBound, columnRule: .fromOrigin, startsLineText: startsLineText))
        containers[containerIndex].positions.append(InlinePosition(location: range.upperBound, columnRule: Self.endColumnRule(of: range, role: role), startsLineText: false))
    }

    private static func endColumnRule(of range: SourceRange, role: SourceRangeRole?) -> ColumnRule {
        guard range.upperBound.line > range.lowerBound.line else { return .fromOrigin }
        switch role {
        case .inlineCode: return .codeEndFromKeptStart
        case .inlineHTML: return .htmlEndFromKeptStart
        default: return .fromOrigin
        }
    }

    /// Replays every paragraph's positions in source order to find its lines' origins.
    mutating func resolveInlineLines() {
        for containerIndex in containers.indices {
            let firstColumn = containers[containerIndex].firstColumn
            let quoteDepth = containers[containerIndex].quoteDepth
            var reportedLine = containers[containerIndex].range.lowerBound.line
            let firstLineIndex = clampedLineIndex(reportedLine)
            containers[containerIndex].originByReportedLine[reportedLine] = LineOrigin(lineIndex: firstLineIndex, byte: lineStarts[firstLineIndex] + firstColumn - 1)
            var lastLineIndex = firstLineIndex
            let orderedPositions = containers[containerIndex].positions.sorted { first, second in
                (first.location.line, first.location.column, first.startsLineText ? 0 : 1) < (second.location.line, second.location.column, second.startsLineText ? 0 : 1)
            }
            containers[containerIndex].positions = []
            for position in orderedPositions {
                if position.location.line > reportedLine {
                    let lineIndex = min(lastLineIndex + position.location.line - reportedLine, lineStarts.count - 1)
                    let textStart = textStart(lineIndex: lineIndex, quoteDepth: quoteDepth)
                    let originByte = position.startsLineText ? textStart - (position.location.column - firstColumn) : textStart
                    reportedLine = position.location.line
                    containers[containerIndex].originByReportedLine[reportedLine] = LineOrigin(lineIndex: lineIndex, byte: originByte)
                }
                lastLineIndex = max(lastLineIndex, byteAndLineIndex(of: position, inContainer: containerIndex).lineIndex)
            }
        }
    }

    /// `containerIndex` is the paragraph or heading holding an inline node, or nil for a
    /// block, or for inline nodes such as table cells whose columns count from the line start.
    mutating func utf16Range(of range: SourceRange, role: SourceRangeRole, containerIndex: Int?) -> NSRange {
        let startByte: Int, endByte: Int
        if let containerIndex {
            startByte = byteAndLineIndex(of: InlinePosition(location: range.lowerBound, columnRule: .fromOrigin, startsLineText: false), inContainer: containerIndex).byte
            endByte = byteAndLineIndex(of: InlinePosition(location: range.upperBound, columnRule: Self.endColumnRule(of: range, role: role), startsLineText: false), inContainer: containerIndex).byte
        } else {
            startByte = absoluteByte(of: range.lowerBound)
            endByte = absoluteByte(of: range.upperBound)
        }
        let start = utf16Offset(ofByte: startByte)
        let end = utf16Offset(ofByte: max(startByte, endByte))
        return NSRange(location: start, length: end - start)
    }

    /// The whole lines of a paragraph or heading.
    mutating func utf16Range(ofContainer containerIndex: Int) -> NSRange {
        let range = containers[containerIndex].range
        let startByte = lineStarts[clampedLineIndex(range.lowerBound.line)]
        let endByte = lineContentEnds[clampedLineIndex(range.upperBound.line)]
        let start = utf16Offset(ofByte: startByte)
        return NSRange(location: start, length: utf16Offset(ofByte: endByte) - start)
    }

    private func clampedLineIndex(_ line: Int) -> Int {
        min(max(line - 1, 0), lineStarts.count - 1)
    }

    private func absoluteByte(of location: SourceLocation) -> Int {
        let lineIndex = clampedLineIndex(location.line)
        return lineStarts[lineIndex] + min(max(location.column - 1, 0), lineContentEnds[lineIndex] - lineStarts[lineIndex])
    }

    private mutating func byteAndLineIndex(of position: InlinePosition, inContainer containerIndex: Int) -> (byte: Int, lineIndex: Int) {
        let firstColumn = containers[containerIndex].firstColumn
        let quoteDepth = containers[containerIndex].quoteDepth
        let reportedLine = position.location.line
        let origin = containers[containerIndex].originByReportedLine[reportedLine]
            ?? LineOrigin(lineIndex: clampedLineIndex(reportedLine), byte: textStart(lineIndex: clampedLineIndex(reportedLine), quoteDepth: quoteDepth))
        let byte = switch position.columnRule {
        case .fromOrigin: origin.byte + position.location.column - firstColumn
        case .codeEndFromKeptStart: origin.byte + position.location.column - 1
        case .htmlEndFromKeptStart: origin.byte + position.location.column
        }
        guard byte > lineContentEnds[origin.lineIndex], origin.lineIndex + 1 < lineStarts.count else {
            return (clampedByte(byte, lineIndex: origin.lineIndex), origin.lineIndex)
        }
        // Past its line's break, a column runs on into the next line's kept text. cmark
        // keeps every line break, "\r\n" included, as one byte.
        var steps = containers[containerIndex].spillStepsByReportedLine.removeValue(forKey: reportedLine) ?? [SpillStep(lineIndex: origin.lineIndex, minimumByte: .min, shift: 0)]
        while let lastStep = steps.last, lastStep.lineIndex + 1 < lineStarts.count, byte + lastStep.shift > lineContentEnds[lastStep.lineIndex] {
            let nextLineIndex = lastStep.lineIndex + 1
            let shift = lastStep.shift + textStart(lineIndex: nextLineIndex, quoteDepth: quoteDepth) - lineContentEnds[lastStep.lineIndex] - 1
            steps.append(SpillStep(lineIndex: nextLineIndex, minimumByte: lineContentEnds[lastStep.lineIndex] - lastStep.shift + 1, shift: shift))
        }
        // The last step whose minimum byte `byte` reaches.
        var lowerIndex = 0, upperIndex = steps.count
        while lowerIndex < upperIndex {
            let middleIndex = (lowerIndex + upperIndex) / 2
            if steps[middleIndex].minimumByte <= byte { lowerIndex = middleIndex + 1 } else { upperIndex = middleIndex }
        }
        let step = steps[max(lowerIndex - 1, 0)]
        containers[containerIndex].spillStepsByReportedLine[reportedLine] = steps
        return (clampedByte(byte + step.shift, lineIndex: step.lineIndex), step.lineIndex)
    }

    private func clampedByte(_ byte: Int, lineIndex: Int) -> Int {
        min(max(byte, lineStarts[lineIndex]), lineContentEnds[lineIndex])
    }

    /// Where a continuation line's text starts: after up to `quoteDepth` quote markers (a
    /// lazy continuation line may omit them) and the spaces and tabs around them.
    private func textStart(lineIndex: Int, quoteDepth: Int) -> Int {
        var position = lineStarts[lineIndex]
        var remainingQuoteMarkers = quoteDepth
        while position < lineContentEnds[lineIndex] {
            let byte = bytes[position]
            if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") {
                position += 1
            } else if byte == UInt8(ascii: ">") && remainingQuoteMarkers > 0 {
                remainingQuoteMarkers -= 1
                position += 1
            } else {
                break
            }
        }
        return position
    }

    /// Counts UTF-16 units by lead bytes: every scalar has one lead byte, and scalars of
    /// four UTF-8 bytes need a surrogate pair.
    private mutating func utf16Offset(ofByte targetByte: Int) -> Int {
        while cursorByte < targetByte {
            cursorUTF16 += Self.utf16Length(startingWith: bytes[cursorByte])
            cursorByte += 1
        }
        while cursorByte > targetByte {
            cursorByte -= 1
            cursorUTF16 -= Self.utf16Length(startingWith: bytes[cursorByte])
        }
        return cursorUTF16
    }

    private static func utf16Length(startingWith byte: UInt8) -> Int {
        if byte & 0b1100_0000 == 0b1000_0000 { return 0 }
        return byte >= 0b1111_0000 ? 2 : 1
    }
}

/// Ranges merged into sorted, disjoint intervals, so an overlap test is a binary search
/// instead of a scan of every range (which made parsing quadratic in link-dense notes).
private struct SortedRangeSet {
    /// Sorted by location; each interval ends before the next one starts.
    private var intervals: [NSRange] = []

    init(_ ranges: [NSRange]) {
        for range in ranges.filter({ range in range.length > 0 }).sorted(by: { first, second in first.location < second.location }) {
            if let last = intervals.last, range.location <= NSMaxRange(last) {
                intervals[intervals.count - 1] = NSUnionRange(last, range)
            } else {
                intervals.append(range)
            }
        }
    }

    /// Whether `range` shares at least one position with a stored range.
    func intersects(_ range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        // The last interval starting before `range` ends is the only candidate: the
        // intervals are disjoint and sorted, so it also ends last among them.
        var lowerIndex = 0, upperIndex = intervals.count
        while lowerIndex < upperIndex {
            let middleIndex = (lowerIndex + upperIndex) / 2
            if intervals[middleIndex].location < NSMaxRange(range) { lowerIndex = middleIndex + 1 } else { upperIndex = middleIndex }
        }
        guard lowerIndex > 0 else { return false }
        return NSMaxRange(intervals[lowerIndex - 1]) > range.location
    }
}

/// Loads note frontmatter with bounded work. YAML aliases repeat a node wherever they
/// appear, so a few hundred bytes of nested aliases ("billion laughs") expand to millions
/// of values and hang indexing. Composing the node tree shares aliased nodes; counting the
/// expanded tree stops at the budget, and only a document within it becomes values.
enum BoundedYAML {
    /// Without aliases every node takes at least one byte of YAML, so the byte count
    /// bounds a plain document; the allowance leaves room for ordinary alias reuse.
    private static let aliasExpansionAllowance = 10_000

    static func load(_ yaml: String) -> Any? {
        guard !YAMLNesting.exceedsSafeDepth(yaml), !YAMLAliasExpansion.exceedsAnchorCount(yaml), let root = try? Yams.compose(yaml: yaml),
              !YAMLAliasExpansion.exceedsLimits(root, sourceByteCount: yaml.utf8.count),
              isWithinExpansionBudget(root, yamlByteCount: yaml.utf8.count) else { return nil }
        return root.any
    }

    /// Whether `root`, with every alias expanded, stays within the node budget for YAML of
    /// `yamlByteCount` bytes. Code that converts or serializes a composed node tree checks
    /// this first, because both expand aliases.
    static func isWithinExpansionBudget(_ root: Node, yamlByteCount: Int) -> Bool {
        let maximumNodeCount = yamlByteCount + aliasExpansionAllowance
        // Nodes are counted when found rather than when visited, so the pending list
        // never holds more than the budget either.
        var nodeCount = 1
        var pendingNodes = [root]
        while let node = pendingNodes.popLast() {
            switch node {
            case .mapping(let mapping):
                nodeCount += 2 * mapping.count
                guard nodeCount <= maximumNodeCount else { return false }
                for (key, value) in mapping { pendingNodes.append(key); pendingNodes.append(value) }
            case .sequence(let sequence):
                nodeCount += sequence.count
                guard nodeCount <= maximumNodeCount else { return false }
                pendingNodes.append(contentsOf: sequence)
            case .scalar, .alias:
                break
            }
        }
        return true
    }
}

public enum FrontmatterLocator {
    private static let pattern = try? NSRegularExpression(pattern: "\\A---\\r?\\n(?:[\\s\\S]*?\\r?\\n)?(?:---|\\.\\.\\.)[ \\t]*(?:\\r?\\n|$)")

    /// UTF-16 length of the leading YAML frontmatter block, or 0 when there is none.
    public static func length(in text: NSString) -> Int {
        pattern?.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length))?.range.length ?? 0
    }
}

/// Obsidian's tag rules: letters, numbers, `_`, `-`, `/` for nesting, and symbols such
/// as emoji, with at least one character that is not a number (`#2026-exam` is a tag,
/// `#1984` is not). A tag starts at a `#` that does not continue a word or a path.
public enum TagSyntax {
    /// Emoji need their joiners and variation selectors, the skin-tone modifiers
    /// (U+1F3FB to U+1F3FF, which are modifier symbols like `^`, so not the whole
    /// category) and the tag characters of subdivision flags (U+E0020 to U+E007F).
    private static let tagCharacter = "[\\p{L}\\p{N}\\p{M}\\p{So}_/\\-\\x{200D}\\x{FE0F}\\x{1F3FB}-\\x{1F3FF}\\x{E0020}-\\x{E007F}]"
    /// Capture group 1 is the tag without its `#`.
    public static let pattern: NSRegularExpression = {
        // A fixed pattern, covered by tests, so compilation cannot fail at run time.
        try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_/&#])#(?!\\p{N}+(?!\(tagCharacter)))(\(tagCharacter)+)")
    }()

    /// Whether `name` (without `#`) is a whole valid tag.
    public static func isValidTag(_ name: String) -> Bool {
        let text = "#" + name
        guard let match = pattern.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return false }
        return match.range.length == (text as NSString).length
    }

    /// Whether a tag search for `searchedTag` finds `tag`: the tag itself or any tag nested under it.
    public static func tag(_ tag: String, isWithin searchedTag: String) -> Bool {
        let tagKey = tag.lowercased(), searchedKey = searchedTag.lowercased()
        return tagKey == searchedKey || tagKey.hasPrefix(searchedKey + "/")
    }
}

/// CommonMark code fences: a run of three or more backticks or tildes opens one, and only
/// a line of the same character, at least as long, closes it.
public enum CodeFence {
    /// The fence that `trimmedLine` opens, and the info text after it, or nil.
    public static func opening(_ trimmedLine: String) -> (fence: String, info: String)? {
        guard let fenceCharacter = trimmedLine.first, fenceCharacter == "`" || fenceCharacter == "~" else { return nil }
        let fence = String(trimmedLine.prefix { character in character == fenceCharacter })
        guard fence.count >= 3 else { return nil }
        let info = trimmedLine.dropFirst(fence.count).trimmingCharacters(in: .whitespaces)
        // A backtick fence's info text cannot contain a backtick.
        guard fenceCharacter == "~" || !info.contains("`") else { return nil }
        return (fence, info)
    }

    public static func closes(_ fence: String, _ trimmedLine: String) -> Bool {
        guard let fenceCharacter = fence.first else { return false }
        return trimmedLine.count >= fence.count && trimmedLine.allSatisfy { character in character == fenceCharacter }
    }
}

/// Where code is in Markdown text: fenced blocks and inline code spans. Links and embeds
/// written there are text, not links.
public enum MarkdownCodeRanges {
    private static let backtick = UInt16(UInt8(ascii: "`"))
    private static let backslash = UInt16(UInt8(ascii: "\\"))
    private static let lineBreaks = CharacterSet(charactersIn: "\n\r")

    public static func ranges(in text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var fenceStart: Int?
        var tracker = CodeFenceTracker()
        // Content columns of the list items the current line may belong to. A fence opens
        // only within three columns of its container's content, so "    ```" continuing
        // a paragraph is text, while the same line inside a list item opens a fence.
        var listContentColumns: [Int] = []
        var openFenceIndentationLimit = 0
        var lineStart = 0
        while lineStart < text.length {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            let line = text.substring(with: lineRange)
            let indentation = leadingColumns(of: line)
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let isCode: Bool
            if tracker.isInsideFence {
                // Indented further, a fence line is content, not the closing fence.
                isCode = indentation > openFenceIndentationLimit || tracker.isCodeLine(trimmedLine)
            } else {
                if !trimmedLine.isEmpty {
                    while let contentColumn = listContentColumns.last, contentColumn > indentation { listContentColumns.removeLast() }
                }
                let indentationLimit = (listContentColumns.last ?? 0) + 3
                isCode = indentation <= indentationLimit && tracker.isCodeLine(trimmedLine)
                if isCode {
                    openFenceIndentationLimit = indentationLimit
                } else if let contentColumn = listItemContentColumn(of: line, indentation: indentation) {
                    listContentColumns.append(contentColumn)
                }
            }
            if isCode, fenceStart == nil { fenceStart = lineRange.location }
            if !isCode, let start = fenceStart {
                ranges.append(NSRange(location: start, length: lineRange.location - start))
                fenceStart = nil
            }
            lineStart = NSMaxRange(lineRange)
        }
        if let start = fenceStart { ranges.append(NSRange(location: start, length: text.length - start)) }
        ranges += codeSpans(in: text, range: NSRange(location: 0, length: text.length)).map(\.range)
        return ranges
    }

    /// Whether `range` overlaps code.
    public static func range(_ range: NSRange, isInside codeRanges: [NSRange]) -> Bool {
        codeRanges.contains { codeRange in NSIntersectionRange(codeRange, range).length > 0 }
    }

    /// CommonMark code spans within one line: a run of backticks not escaped by a
    /// backslash, closed by the next run of the same length on that line. Inside a span a
    /// backslash is literal, so it cannot escape the closing run.
    static func codeSpans(in text: NSString, range: NSRange) -> [(range: NSRange, delimiterLength: Int)] {
        var spans: [(range: NSRange, delimiterLength: Int)] = []
        let end = NSMaxRange(range)
        var searchStart = range.location
        while let openingStart = nextBacktick(in: text, from: searchStart, to: end) {
            if isEscaped(openingStart, in: text) {
                searchStart = openingStart + 1
                continue
            }
            let openingEnd = backtickRunEnd(in: text, from: openingStart, to: end)
            let delimiterLength = openingEnd - openingStart
            let lineEnd = text.rangeOfCharacter(from: lineBreaks, range: NSRange(location: openingEnd, length: end - openingEnd)).location
            let spanLimit = lineEnd == NSNotFound ? end : lineEnd
            var closingSearchStart = openingEnd
            var closingEnd: Int?
            while let closingStart = nextBacktick(in: text, from: closingSearchStart, to: spanLimit) {
                let runEnd = backtickRunEnd(in: text, from: closingStart, to: spanLimit)
                if runEnd - closingStart == delimiterLength {
                    closingEnd = runEnd
                    break
                }
                closingSearchStart = runEnd
            }
            guard let closingEnd else {
                // An unmatched run is literal text; a shorter run inside it may still open.
                searchStart = openingEnd
                continue
            }
            spans.append((NSRange(location: openingStart, length: closingEnd - openingStart), delimiterLength))
            searchStart = closingEnd
        }
        return spans
    }

    private static func nextBacktick(in text: NSString, from start: Int, to end: Int) -> Int? {
        guard start < end else { return nil }
        let location = text.range(of: "`", options: .literal, range: NSRange(location: start, length: end - start)).location
        return location == NSNotFound ? nil : location
    }

    private static func backtickRunEnd(in text: NSString, from start: Int, to end: Int) -> Int {
        var runEnd = start
        while runEnd < end && text.character(at: runEnd) == backtick { runEnd += 1 }
        return runEnd
    }

    /// Whether an odd number of backslashes precedes `location`.
    private static func isEscaped(_ location: Int, in text: NSString) -> Bool {
        var index = location
        while index > 0 && text.character(at: index - 1) == backslash { index -= 1 }
        return (location - index) % 2 == 1
    }

    /// Leading indentation in columns, with tabs advancing to the next multiple of four.
    private static func leadingColumns(of line: String) -> Int {
        var columns = 0
        for character in line {
            if character == " " { columns += 1 } else if character == "\t" { columns += 4 - columns % 4 } else { break }
        }
        return columns
    }

    /// The column where a list item's content starts, when `line` starts one: after the
    /// marker (`-`, `*`, `+`, `1.` or `1)`) and one to four spaces.
    private static func listItemContentColumn(of line: String, indentation: Int) -> Int? {
        let content = line.drop { character in character == " " || character == "\t" }
        let marker: Substring
        if let first = content.first, "-*+".contains(first) {
            marker = content.prefix(1)
        } else {
            let digits = content.prefix { character in character.isASCII && character.isNumber }
            guard (1...9).contains(digits.count), let delimiter = content.dropFirst(digits.count).first, delimiter == "." || delimiter == ")" else { return nil }
            marker = content.prefix(digits.count + 1)
        }
        let afterMarker = content.dropFirst(marker.count)
        let spaces = afterMarker.prefix { character in character == " " || character == "\t" }.count
        guard spaces > 0 || afterMarker.allSatisfy(\.isNewline) else { return nil }
        // Five or more spaces start indented code in the item, whose content then starts
        // one space after the marker.
        return indentation + marker.count + ((1...4).contains(spaces) ? spaces : 1)
    }
}

/// Follows fenced code line by line, so a longer fence is not closed by a shorter one.
public struct CodeFenceTracker {
    private var openFence: String?

    public init() {}

    /// Whether the lines so far left a fence open.
    public var isInsideFence: Bool { openFence != nil }

    /// Whether this line belongs to fenced code, fences included. Call once per line, in order.
    public mutating func isCodeLine(_ trimmedLine: String) -> Bool {
        if let fence = openFence {
            if CodeFence.closes(fence, trimmedLine) { openFence = nil }
            return true
        }
        guard let (fence, _) = CodeFence.opening(trimmedLine) else { return false }
        openFence = fence
        return true
    }
}

public enum WikiLinkResolver {
    /// Splits a Wikilink's content at its first `|`. Inside a table the pipe is written
    /// `\|`, and that backslash is not part of the target.
    public static func targetAndLabel(of content: String) -> (target: String, label: String?) {
        let parts = content.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        var target = String(parts.first ?? "")
        if parts.count > 1, target.hasSuffix("\\") { target.removeLast() }
        return (target, parts.count > 1 ? String(parts[1]) : nil)
    }

    public static func pathPart(_ target: String) -> String {
        String(target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }
    /// Text for comparing names: file systems may store "é" as one character or as "e"
    /// plus an accent (as macOS often does), while links are typed with the first.
    public static func comparisonKey(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
    }

    /// Text for matching names the way Obsidian does: ignoring case for every letter, not
    /// only ASCII, and whatever Unicode form the name is stored in. The index stores names
    /// and paths folded this way, so search compares them in SQL as the matcher does.
    public static func caseFoldedKey(_ text: String) -> String {
        // Lowercasing can leave a decomposed sequence, so normalization comes second.
        comparisonKey(text.lowercased())
    }

    /// The file names a link's path part may mean. A dot does not always start an
    /// extension (`[[Homework 2.1]]` is `Homework 2.1.md`), so both readings are tried,
    /// the file with the written extension first.
    public static func fileNameVariants(for part: String) -> [String] {
        (part as NSString).pathExtension.isEmpty ? [part + ".md", part] : [part, part + ".md"]
    }

    /// The files a link names by path, most likely first: beside the note, then from the
    /// vault root, for each file-name reading. Wikilinks and Markdown links look in the same
    /// places, as in Obsidian, whose "absolute path in vault" Markdown links (which Graphite's
    /// link completion writes too) start at the root. A path starting with `./` or `../`
    /// is relative to the note only. `isWiki` states the link's kind for the caller; both
    /// kinds give the same candidates.
    public static func directCandidates(target: String, source: VaultPath, isWiki: Bool = true) -> [VaultPath] {
        let part = pathPart(target).removingPercentEncoding ?? pathPart(target)
        if part.isEmpty { return [source] }
        guard URL(string: part)?.scheme == nil else { return [] }
        let isRelativeToNote = isExplicitlyRelative(part)
        var paths: [VaultPath] = []
        for fileNameVariant in fileNameVariants(for: part) {
            if let besideNote = try? source.parent.appending(fileNameVariant) { paths.append(besideNote) }
            if !isRelativeToNote, let fromVaultRoot = try? VaultPath(fileNameVariant) { paths.append(fromVaultRoot) }
        }
        return Array(NSOrderedSet(array: paths).array.compactMap { candidate in candidate as? VaultPath })
    }

    /// Whether a link's path starts with `./` or `../`, which only the note's own folder
    /// can resolve.
    public static func isExplicitlyRelative(_ linkPath: String) -> Bool {
        linkPath == "." || linkPath == ".." || linkPath.hasPrefix("./") || linkPath.hasPrefix("../")
    }
}

/// Obsidian's image size: `400` or `400x300` after the last `|` of an embed's label, as in
/// `![[image.png|400]]`, `![[image.png|Caption|400x300]]`, or `![Caption|400](image.png)`.
public struct EmbedDisplaySize: Hashable, Sendable {
    /// In points.
    public let width: Double
    /// In points; nil when only the width is given, so the image keeps its shape.
    public let height: Double?

    public init(width: Double, height: Double?) {
        self.width = width; self.height = height
    }

    private static let maximumPoints = 10_000.0

    public static func parse(label: String) -> EmbedDisplaySize? {
        let sizeText = (label.split(separator: "|", omittingEmptySubsequences: false).last.map(String.init) ?? label).trimmingCharacters(in: .whitespaces)
        let dimensions = sizeText.split(separator: "x", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let width = points(dimensions[0]) else { return nil }
        guard dimensions.count == 2 else { return EmbedDisplaySize(width: width, height: nil) }
        guard let height = points(dimensions[1]) else { return nil }
        return EmbedDisplaySize(width: width, height: height)
    }

    private static func points(_ text: String) -> Double? {
        // Digits only: "1e3" or "Infinity" would be read as numbers by `Double`.
        guard !text.isEmpty, text.allSatisfy(\.isASCII), text.allSatisfy({ character in character.isNumber || character == "." }),
              let value = Double(text), value > 0, value <= maximumPoints else { return nil }
        return value
    }

    /// The width to draw an image of `aspectRatio` (width over height) at, so that it fits
    /// both given dimensions without being stretched.
    public func fittedWidth(aspectRatio: Double) -> Double {
        guard let height, aspectRatio > 0 else { return width }
        return min(width, height * aspectRatio)
    }
}

/// An embed such as `![[Drawing.png|400]]` or `![](Drawing.png)` in note source.
public struct EmbedReference: Equatable, Sendable {
    public let target: String
    public let isWiki: Bool
    /// Obsidian's display size from `![[image.png|400]]` or `|400x300`.
    public let displaySize: EmbedDisplaySize?
    public let range: NSRange
    /// The width given for the image, in points, before fitting any height.
    public var displayWidth: Double? { displaySize?.width }
}

public enum EmbedLocator {
    private static let wikiEmbedPattern = try? NSRegularExpression(pattern: "!\\[\\[([^\\]\\n]+)\\]\\]")
    /// The parentheses hold a `<…>` destination and an optional title, or text with at
    /// most one balanced `(…)` in it, which is how a `(title)` is written.
    private static let markdownEmbedPattern = try? NSRegularExpression(pattern: "!\\[([^\\]\\n]*)\\]\\((<[^<>\\n]*>[^)\\n]*|[^()\\n]*(?:\\([^()\\n]*\\)[^()\\n]*)?)\\)")

    /// The embed whose source text contains `location` (or ends exactly there).
    public static func embed(at location: Int, in text: NSString) -> EmbedReference? {
        guard location >= 0, location <= text.length else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
        let line = text.substring(with: lineRange)
        let localLocation = location - lineRange.location
        func contains(_ range: NSRange) -> Bool { localLocation >= range.location && localLocation <= NSMaxRange(range) }
        let lineLength = (line as NSString).length
        if let match = wikiEmbedPattern?.matches(in: line, range: NSRange(location: 0, length: lineLength)).first(where: { match in contains(match.range) }) {
            let content = (line as NSString).substring(with: match.range(at: 1))
            let parts = content.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let target = parts[0].replacingOccurrences(of: "\\", with: "")
            return EmbedReference(target: target, isWiki: true, displaySize: parts.count > 1 ? EmbedDisplaySize.parse(label: parts[1]) : nil,
                                  range: NSRange(location: lineRange.location + match.range.location, length: match.range.length))
        }
        if let match = markdownEmbedPattern?.matches(in: line, range: NSRange(location: 0, length: lineLength)).first(where: { match in contains(match.range) }) {
            let label = (line as NSString).substring(with: match.range(at: 1))
            let destination = linkDestination(in: (line as NSString).substring(with: match.range(at: 2)))
            guard !destination.isEmpty else { return nil }
            return EmbedReference(target: destination, isWiki: false, displaySize: EmbedDisplaySize.parse(label: label),
                                  range: NSRange(location: lineRange.location + match.range.location, length: match.range.length))
        }
        return nil
    }

    /// The destination of a Markdown image, by CommonMark's rules: the text inside `<…>`,
    /// or else the text up to the first whitespace. A `"title"`, `'title'` or `(title)`
    /// after it is not part of the destination, so `![a](a.png "Title")` embeds `a.png`.
    static func linkDestination(in parenthesizedText: String) -> String {
        let trimmedText = parenthesizedText.trimmingCharacters(in: .whitespaces)
        if trimmedText.hasPrefix("<"), let closingIndex = trimmedText.firstIndex(of: ">") {
            return String(trimmedText[trimmedText.index(after: trimmedText.startIndex)..<closingIndex])
        }
        return trimmedText.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
    }
}

/// Line-break rules for putting a block (an embed, a table) into existing Markdown.
public enum MarkdownBlockInsertion {
    /// The exact text to insert at `range` so that `block` sits on its own line(s).
    /// Breaks follow the note's own line endings, so a Windows (CRLF) note stays CRLF.
    /// - Parameter separatedByBlankLines: Also keeps an empty line before and after the
    ///   block, for blocks such as quotes that the next line would otherwise continue.
    public static func text(inserting block: String, into source: NSString, replacing range: NSRange, separatedByBlankLines: Bool = false) -> String {
        let lineBreak = lineBreak(of: source)
        let block = lineBreak == "\n" ? block : block.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: lineBreak)
        var insertion = text(inserting: block, into: source, replacing: range, lineBreak: lineBreak)
        guard separatedByBlankLines else { return insertion }
        let blankLine = lineBreak + lineBreak
        // Before: the note's text up to the block, with the line breaks the insertion adds.
        let textBefore = source.substring(to: range.location) + String(insertion.prefix { character in character.isNewline })
        if !textBefore.isEmpty, !textBefore.hasSuffix(blankLine) { insertion = lineBreak + insertion }
        // After: an empty line unless the note ends there or one already follows.
        let textAfter = source.substring(from: NSMaxRange(range))
        let restStartsWithBlankLine = textAfter.hasPrefix(blankLine) || (insertion.hasSuffix(lineBreak) && textAfter.hasPrefix(lineBreak))
        let restIsEmpty = textAfter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !restIsEmpty, !restStartsWithBlankLine, !insertion.hasSuffix(blankLine) { insertion += lineBreak }
        return insertion
    }

    /// The note's line ending, taken from its first line break; "\n" when it has none.
    private static func lineBreak(of source: NSString) -> String {
        let firstLineFeed = source.range(of: "\n").location
        guard firstLineFeed != NSNotFound, firstLineFeed > 0, source.character(at: firstLineFeed - 1) == carriageReturn else { return "\n" }
        return "\r\n"
    }

    private static let lineFeed = UInt16(UInt8(ascii: "\n"))
    private static let carriageReturn = UInt16(UInt8(ascii: "\r"))

    private static func text(inserting block: String, into source: NSString, replacing range: NSRange, lineBreak: String) -> String {
        let isAtLineStart = range.location == 0 || [lineFeed, carriageReturn].contains(source.character(at: range.location - 1))
        let endLocation = NSMaxRange(range)
        let followingBreakLength = lineBreakLength(in: source, at: endLocation)
        let isFollowedByLineBreak = followingBreakLength > 0
        var insertion: String
        let followingLine: String
        if isAtLineStart {
            // The rest of the current line (possibly empty) moves below the block.
            insertion = block + lineBreak
            followingLine = restOfLine(in: source, from: endLocation)
        } else {
            insertion = lineBreak + block + (isFollowedByLineBreak ? "" : lineBreak)
            followingLine = restOfLine(in: source, from: endLocation + followingBreakLength)
        }
        // "Text\n---" is a setext heading: keep a blank line between the block and a rule.
        if isSetextUnderline(followingLine) { insertion += lineBreak }
        return insertion
    }

    /// 2 for "\r\n", 1 for another line break, 0 when `location` does not start one.
    private static func lineBreakLength(in source: NSString, at location: Int) -> Int {
        guard location < source.length else { return 0 }
        switch source.character(at: location) {
        case carriageReturn: return location + 1 < source.length && source.character(at: location + 1) == lineFeed ? 2 : 1
        case lineFeed: return 1
        default: return 0
        }
    }

    private static func restOfLine(in source: NSString, from location: Int) -> String {
        guard location < source.length else { return "" }
        let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
        return source.substring(with: NSRange(location: location, length: NSMaxRange(lineRange) - location))
    }

    private static func isSetextUnderline(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty, line.prefix(while: { character in character == " " }).count < 4 else { return false }
        return Set(trimmedLine) == ["-"] || Set(trimmedLine) == ["="]
    }
}
