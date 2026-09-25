import Foundation

/// swift-markdown converts its parse tree recursively, so a note nested deeply enough
/// exhausts the thread's stack and the app dies. A synced vault can contain such a note,
/// and because the last document reopens and indexing runs at every launch, the crash
/// would repeat on every launch. Measured on the 512 KB stack of a Swift concurrency
/// thread (Sep 2026, release build): 55 nested lists or 64 nested quotes crash. Text
/// deeper than the limit here is not given to the Markdown parser.
public enum MarkdownNesting {
    public static let maximumContainerDepth = 32

    /// Whether some line may sit inside more than `maximumContainerDepth` quotes and
    /// lists. It overestimates on purpose: every two columns of indentation before a
    /// marker count as one level, because list items nest by indentation.
    public static func exceedsSafeDepth(_ text: String) -> Bool {
        var lineStart = text.utf8.startIndex
        let end = text.utf8.endIndex
        while lineStart < end {
            let lineEnd = text.utf8[lineStart...].firstIndex(where: { byte in byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") }) ?? end
            if estimatedDepth(of: text.utf8[lineStart..<lineEnd]) > maximumContainerDepth { return true }
            lineStart = lineEnd < end ? text.utf8.index(after: lineEnd) : end
        }
        return false
    }

    private static func estimatedDepth(of line: Substring.UTF8View) -> Int {
        var position = line.startIndex
        var indentationColumns = 0
        while position < line.endIndex, line[position] == UInt8(ascii: " ") || line[position] == UInt8(ascii: "\t") {
            indentationColumns += line[position] == UInt8(ascii: "\t") ? 4 - indentationColumns % 4 : 1
            position = line.index(after: position)
        }
        let contentStart = position
        var markerCount = 0
        while position < line.endIndex {
            while position < line.endIndex, line[position] == UInt8(ascii: " ") || line[position] == UInt8(ascii: "\t") { position = line.index(after: position) }
            guard position < line.endIndex else { break }
            let byte = line[position]
            let next = line.index(after: position)
            let isFollowedBySpace = next == line.endIndex || line[next] == UInt8(ascii: " ") || line[next] == UInt8(ascii: "\t")
            if byte == UInt8(ascii: ">") {
                markerCount += 1
                position = next
            } else if (byte == UInt8(ascii: "-") || byte == UInt8(ascii: "+") || byte == UInt8(ascii: "*")) && isFollowedBySpace {
                markerCount += 1
                position = next
            } else if let afterNumber = orderedMarkerEnd(in: line, from: position) {
                markerCount += 1
                position = afterNumber
            } else {
                break
            }
        }
        guard markerCount > 0, !isThematicBreak(line[contentStart...]) else { return 0 }
        return indentationColumns / 2 + markerCount
    }

    /// The position after `1.` or `1)` followed by a space, the ordered list marker.
    private static func orderedMarkerEnd(in line: Substring.UTF8View, from start: Substring.UTF8View.Index) -> Substring.UTF8View.Index? {
        var position = start
        var digitCount = 0
        while position < line.endIndex, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(line[position]), digitCount < 9 {
            digitCount += 1
            position = line.index(after: position)
        }
        guard digitCount > 0, position < line.endIndex, line[position] == UInt8(ascii: ".") || line[position] == UInt8(ascii: ")") else { return nil }
        let afterDelimiter = line.index(after: position)
        guard afterDelimiter == line.endIndex || line[afterDelimiter] == UInt8(ascii: " ") || line[afterDelimiter] == UInt8(ascii: "\t") else { return nil }
        return afterDelimiter
    }

    /// `- - - - -` alone on a line is a horizontal rule, not nested lists.
    private static func isThematicBreak(_ content: Substring.UTF8View) -> Bool {
        let markers = content.filter { byte in byte != UInt8(ascii: " ") && byte != UInt8(ascii: "\t") }
        guard markers.count >= 3, let first = markers.first, [UInt8(ascii: "-"), UInt8(ascii: "*"), UInt8(ascii: "_")].contains(first) else { return false }
        return markers.allSatisfy { byte in byte == first }
    }
}

/// Yams builds its node tree recursively, so deeply nested YAML in frontmatter or a
/// `.base` file exhausts the stack the same way. Measured on a 512 KB stack (Sep 2026,
/// debug build): 100 nested flow levels (`{and: [` … `]}`) or 176 nested block levels
/// crash. YAML deeper than the limit here is treated as invalid instead of parsed.
public enum YAMLNesting {
    public static let maximumFlowDepth = 32
    public static let maximumBlockIndentation = 64

    /// Whether the YAML may nest deeper than the limits. Flow brackets outside quotes are
    /// counted; for block style, every column of indentation may be a level, except in
    /// the content of block scalars (`|` and `>`), which is text.
    public static func exceedsSafeDepth(_ yaml: String) -> Bool {
        var flowDepth = 0
        var blockScalarParentIndentation: Int?
        for line in yaml.split(omittingEmptySubsequences: false, whereSeparator: { character in character == "\n" || character == "\r\n" || character == "\r" }) {
            let indentation = line.prefix { character in character == " " }.count
            let content = line.dropFirst(indentation)
            if let parentIndentation = blockScalarParentIndentation {
                if content.isEmpty || indentation > parentIndentation { continue }
                blockScalarParentIndentation = nil
            }
            if content.isEmpty || content.hasPrefix("#") { continue }
            if flowDepth == 0 && indentation + compactIndicatorColumns(content) > maximumBlockIndentation { return true }
            var quote: Character?
            var previous: Character = " "
            for character in content {
                if let openQuote = quote {
                    if character == openQuote { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "#" && (previous == " " || previous == "\t") {
                    break
                } else if character == "[" || character == "{" {
                    flowDepth += 1
                    if flowDepth > maximumFlowDepth { return true }
                } else if character == "]" || character == "}" {
                    flowDepth = max(0, flowDepth - 1)
                }
                previous = character
            }
            if flowDepth == 0, startsBlockScalar(content) { blockScalarParentIndentation = indentation }
        }
        return false
    }

    /// Columns taken by compact block indicators at the start of a line. Each `- `, `? `
    /// or `: ` opens a nested collection on the same line (`- - - x` is three sequences
    /// deep), so it counts as indentation.
    private static func compactIndicatorColumns(_ content: Substring) -> Int {
        var columns = 0
        var remaining = content
        while let indicator = remaining.first, indicator == "-" || indicator == "?" || indicator == ":" {
            let afterIndicator = remaining.dropFirst()
            guard let separator = afterIndicator.first else { return columns + 1 }
            guard separator == " " || separator == "\t" else { return columns }
            let spacing = afterIndicator.prefix { character in character == " " || character == "\t" }
            columns += 1 + spacing.count
            remaining = afterIndicator.dropFirst(spacing.count)
        }
        return columns
    }

    /// A line ending in `|` or `>`, with optional chomping and indentation indicators.
    private static func startsBlockScalar(_ content: Substring) -> Bool {
        let withoutComment = content.split(separator: " #", maxSplits: 1, omittingEmptySubsequences: false).first ?? content
        let trimmed = withoutComment.trimmingCharacters(in: .whitespaces)
        guard let indicatorStart = trimmed.lastIndex(where: { character in character == "|" || character == ">" }) else { return false }
        let beforeIndicator = trimmed[..<indicatorStart]
        guard beforeIndicator.isEmpty || beforeIndicator.hasSuffix(" ") || beforeIndicator.hasSuffix(":") || beforeIndicator.hasSuffix("-") else { return false }
        return trimmed[trimmed.index(after: indicatorStart)...].allSatisfy { character in character == "-" || character == "+" || character.isNumber }
    }
}
