import Foundation

/// Obsidian's `%%` comments, which the reading view, the outline, sections and Read Aloud
/// leave out.
enum ObsidianComments {
    /// Removes Obsidian `%%` comments, markers included. `%%` in code is text.
    static func removingComments(from markdown: String) -> String {
        removing(commentRanges(in: markdown), from: markdown)
    }

    /// `markdown` without `ranges`, which are in order and do not overlap.
    static func removing(_ ranges: [NSRange], from markdown: String) -> String {
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
            let unquotedLine = MarkdownQuoteSyntax.markersRemoved(from: Substring(line)).content
            if commentStart == nil, fenceTracker.isCodeLine(untrimmedLine: unquotedLine) { continue }
            guard line.utf8.contains(UInt8(ascii: "%")) else { continue }
            let lineSource = line as NSString
            let codeRanges = MarkdownCodeRanges.codeSpans(in: lineSource, range: NSRange(location: 0, length: lineSource.length)).map(\.range)
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
}
