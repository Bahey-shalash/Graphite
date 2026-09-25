import Foundation

/// Where `$$` display math opens and closes in a run of lines. Reading view blocks, the
/// Markdown prepared for rendering, and Live Preview all ask this one type, so they agree
/// on which lines are math.
///
/// Delimiters pair up in order, as in Obsidian. A line outside math with an odd number of
/// unescaped `$$` opens a block, and inside a block the first line with an odd number
/// closes it. So in `- $$` (a list item) or `The energy is $$`, the `$$` opens a block,
/// and the `$$` line that closes it is never mistaken for a new opener.
public struct DisplayMathLines {
    /// A line outside math that opens a formula continuing on later lines.
    public struct Opening: Equatable, Sendable {
        /// UTF-16 offset in the line of the `$$` that opens the block.
        public let delimiterOffset: Int
        /// Whether only indentation and `>` quote markers come before that `$$`. A block
        /// that opens there runs to the end when nothing closes it, as in Obsidian.
        public let isAtLineStart: Bool
        /// The line holding the closing `$$`, or nil when the block runs to the end.
        public let closingLineIndex: Int?
    }

    public let lines: [String]
    /// The number of unescaped `$$` on each line, code spans included.
    private let delimiterCounts: [Int]
    /// For each line index, the first line at or after it that would close an open block.
    /// Filled from the end, so a note with many unmatched `$$` does not rescan the rest of
    /// the note for each one.
    private let closingLineIndexFromLine: [Int?]

    private static let codeSpanPattern = try? NSRegularExpression(pattern: "(?<!`)(`+)(?!`)[^\\n]*?(?<!`)\\1(?!`)")
    private static let dollarSignCodeUnit = UInt16(UInt8(ascii: "$"))
    private static let backslashCodeUnit = UInt16(UInt8(ascii: "\\"))

    public init(_ lines: [String]) {
        self.lines = lines
        var counts = [Int](repeating: 0, count: lines.count)
        var closingIndices = [Int?](repeating: nil, count: lines.count + 1)
        for lineIndex in lines.indices.reversed() {
            counts[lineIndex] = Self.delimiterOffsets(in: lines[lineIndex], skippingCodeSpans: false).count
            closingIndices[lineIndex] = counts[lineIndex] % 2 == 1 ? lineIndex : closingIndices[lineIndex + 1]
        }
        delimiterCounts = counts
        closingLineIndexFromLine = closingIndices
    }

    /// The display math block that the line at `lineIndex` opens, when that line is
    /// outside math. A `$$` after other text belongs to its paragraph, so it opens a block
    /// only when a later line of the same paragraph closes it; otherwise it is ordinary
    /// text, as Obsidian shows it.
    public func opening(at lineIndex: Int) -> Opening? {
        guard lines.indices.contains(lineIndex), delimiterCounts[lineIndex] > 0 else { return nil }
        let line = lines[lineIndex]
        let offsets = Self.delimiterOffsets(in: line, skippingCodeSpans: true)
        guard offsets.count % 2 == 1, let delimiterOffset = offsets.last else { return nil }
        let textBefore = (line as NSString).substring(to: delimiterOffset)
        let isAtLineStart = textBefore.allSatisfy { character in character == ">" || character == " " || character == "\t" }
        let closingLineIndex = closingLineIndexFromLine[lineIndex + 1]
        if isAtLineStart { return Opening(delimiterOffset: delimiterOffset, isAtLineStart: true, closingLineIndex: closingLineIndex) }
        // The lines checked here end at the next line with an odd count, so the ranges of
        // successive openers do not overlap and the checks stay linear in the note.
        guard let closingLineIndex, !lines[(lineIndex + 1)..<closingLineIndex].contains(where: Self.endsParagraph) else { return nil }
        return Opening(delimiterOffset: delimiterOffset, isAtLineStart: false, closingLineIndex: closingLineIndex)
    }

    /// An empty line or a code fence, which ends a paragraph.
    private static func endsParagraph(_ line: String) -> Bool {
        let unquotedLine = line.drop { character in character == ">" || character == " " || character == "\t" || character == "\r" }
        guard let firstCharacter = unquotedLine.first else { return true }
        guard firstCharacter == "`" || firstCharacter == "~" else { return false }
        return CodeFence.opening(unquotedLine.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    /// UTF-16 offset of the `$$` that closes an open block on `line`: the first one.
    public static func closingDelimiterOffset(in line: String) -> Int? {
        delimiterOffsets(in: line, skippingCodeSpans: false).first
    }

    /// UTF-16 offsets of the unescaped `$$` delimiters in `line`, left to right. `$$$`
    /// holds one delimiter, and `\$$` holds none (an escaped `$` then a lone `$`). With
    /// `skippingCodeSpans`, which applies to text outside math, a `$$` in a backtick code
    /// span is ignored.
    public static func delimiterOffsets(in line: String, skippingCodeSpans: Bool) -> [Int] {
        // Most lines have no `$`, and a byte search rules them out quickly.
        guard line.utf8.contains(UInt8(ascii: "$")) else { return [] }
        var offsets: [Int] = []
        var precedingBackslashCount = 0
        var unpairedDollarOffset: Int?
        for (offset, codeUnit) in line.utf16.enumerated() {
            if codeUnit == dollarSignCodeUnit {
                if let firstDollarOffset = unpairedDollarOffset {
                    offsets.append(firstDollarOffset)
                    unpairedDollarOffset = nil
                } else if precedingBackslashCount % 2 == 0 {
                    unpairedDollarOffset = offset
                }
                precedingBackslashCount = 0
            } else {
                unpairedDollarOffset = nil
                precedingBackslashCount = codeUnit == backslashCodeUnit ? precedingBackslashCount + 1 : 0
            }
        }
        guard skippingCodeSpans, !offsets.isEmpty, line.contains("`"), let codeSpanPattern else { return offsets }
        let codeRanges = codeSpanPattern.matches(in: line, range: NSRange(location: 0, length: (line as NSString).length)).map(\.range)
        return offsets.filter { offset in !codeRanges.contains { codeRange in NSLocationInRange(offset, codeRange) } }
    }
}
