import Foundation
import Markdown

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
