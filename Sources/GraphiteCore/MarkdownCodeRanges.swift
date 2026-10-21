import Foundation

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
        var listItems = ListItemContainers()
        var openFenceIndentationLimit = 0
        var lineStart = 0
        while lineStart < text.length {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            let line = text.substring(with: lineRange)
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let isCode: Bool
            if tracker.isInsideFence {
                // Indented further, a fence line is content, not the closing fence.
                isCode = ListItemContainers.leadingColumns(of: line) > openFenceIndentationLimit || tracker.isCodeLine(trimmedLine)
            } else if let opening = listItems.fenceOpening(of: line) {
                isCode = tracker.isCodeLine(trimmedLine)
                openFenceIndentationLimit = opening.containerColumn + MarkdownFenceSyntax.maximumIndentation
            } else {
                isCode = false
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
}
