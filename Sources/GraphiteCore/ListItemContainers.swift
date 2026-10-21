import Foundation

/// The list items a line can belong to, as CommonMark nests blocks: a non-blank line
/// belongs to the innermost item whose content column it reaches. A fence opens only
/// within `MarkdownFenceSyntax.maximumIndentation` columns of that column (column 0 outside lists),
/// so "    ```" continuing a paragraph is text while the same line inside a list item
/// opens a fence. The index, the editor, reading view, Live Preview and every reader that
/// follows fences with `CodeFenceTracker` find fence openings through this type.
struct ListItemContainers {
    /// Content columns of the open items, innermost last; each is greater than the one before it.
    private var contentColumns: [Int] = []
    /// No item's content starts before this column: a one-character marker, then a space.
    private static let smallestContentColumn = 2

    init() {}

    /// What the start of one line tells a line-by-line walk, read from the line's UTF-8
    /// bytes: per-line readers ask it of every line of a note, so it builds no string
    /// unless the line holds characters beyond ASCII where they decide the answer.
    struct LineStart {
        /// Leading spaces and tabs in columns, with tabs advancing to the next multiple of four.
        let indentation: Int
        /// The line holds only whitespace and line breaks.
        let isBlank: Bool
        /// The first visible character when it is a backtick or tilde, the only lines that
        /// can open or close a fence.
        let fenceCharacter: UInt8?
        /// Where the content of the list item the line starts begins, or nil when it starts none.
        let listItemContentColumn: Int?

        private static let space = UInt8(ascii: " "), tab = UInt8(ascii: "\t")
        private static let backtick = UInt8(ascii: "`"), tilde = UInt8(ascii: "~")

        /// A line starting with a visible ASCII character that starts neither a fence nor a
        /// list marker, as most lines of prose do.
        static let plainText = LineStart(indentation: 0, isBlank: false, fenceCharacter: nil, listItemContentColumn: nil)

        private init(indentation: Int, isBlank: Bool, fenceCharacter: UInt8?, listItemContentColumn: Int?) {
            self.indentation = indentation
            self.isBlank = isBlank
            self.fenceCharacter = fenceCharacter
            self.listItemContentColumn = listItemContentColumn
        }

        /// The start of `line`, read in place when the string stores contiguous UTF-8 (native
        /// strings and ASCII bridged from `NSString`), and from a copy otherwise.
        init(of line: some StringProtocol) {
            if let firstByte = line.utf8.first, Self.startsPlainText(firstByte) {
                self = Self.plainText
            } else if let lineStart = line.utf8.withContiguousStorageIfAvailable({ bytes in LineStart(utf8: bytes) }) {
                self = lineStart
            } else {
                var copiedLine = String(line)
                self = copiedLine.withUTF8 { bytes in LineStart(utf8: bytes) }
            }
        }

        init(utf8 bytes: UnsafeBufferPointer<UInt8>) {
            var indentation = 0
            var contentStart = 0
            while contentStart < bytes.count, bytes[contentStart] == Self.space || bytes[contentStart] == Self.tab {
                indentation += bytes[contentStart] == Self.tab ? 4 - indentation % 4 : 1
                contentStart += 1
            }
            self.indentation = indentation
            var visibleStart = contentStart
            while visibleStart < bytes.count, Self.isASCIIWhitespace(bytes[visibleStart]) { visibleStart += 1 }
            if visibleStart == bytes.count {
                isBlank = true
                fenceCharacter = nil
            } else if bytes[visibleStart] >= 0x80 {
                // Rare: whitespace beyond ASCII, which trimming skips, may come first.
                let trimmedLine = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                isBlank = trimmedLine.isEmpty
                fenceCharacter = trimmedLine.utf8.first.flatMap { byte in byte == Self.backtick || byte == Self.tilde ? byte : nil }
            } else {
                isBlank = false
                let visibleByte = bytes[visibleStart]
                fenceCharacter = visibleByte == Self.backtick || visibleByte == Self.tilde ? visibleByte : nil
            }
            listItemContentColumn = Self.listItemContentColumn(of: bytes, contentStart: contentStart, indentation: indentation)
        }

        /// Whether a line starting with `byte` is `plainText`: a visible ASCII character other
        /// than a fence character, a bullet or a digit.
        static func startsPlainText(_ byte: UInt8) -> Bool {
            guard byte > space, byte < 0x7F, byte != backtick, byte != tilde else { return false }
            return byte != UInt8(ascii: "-") && byte != UInt8(ascii: "*") && byte != UInt8(ascii: "+")
                && (byte < UInt8(ascii: "0") || byte > UInt8(ascii: "9"))
        }

        private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
            byte == space || (byte >= UInt8(ascii: "\t") && byte <= UInt8(ascii: "\r"))
        }

        /// The column where a list item's content starts, when the line starts one at
        /// `contentStart`, after its indentation: after the marker (`-`, `*`, `+`, `1.` or
        /// `1)`) and one to four spaces.
        private static func listItemContentColumn(of bytes: UnsafeBufferPointer<UInt8>, contentStart: Int, indentation: Int) -> Int? {
            guard contentStart < bytes.count else { return nil }
            let firstByte = bytes[contentStart]
            var markerEnd = contentStart + 1
            if firstByte != UInt8(ascii: "-") && firstByte != UInt8(ascii: "*") && firstByte != UInt8(ascii: "+") {
                var digitEnd = contentStart
                while digitEnd < bytes.count, bytes[digitEnd] >= UInt8(ascii: "0"), bytes[digitEnd] <= UInt8(ascii: "9") { digitEnd += 1 }
                guard (1...9).contains(digitEnd - contentStart), digitEnd < bytes.count,
                      bytes[digitEnd] == UInt8(ascii: ".") || bytes[digitEnd] == UInt8(ascii: ")") else { return nil }
                markerEnd = digitEnd + 1
            }
            var spacesEnd = markerEnd
            while spacesEnd < bytes.count, bytes[spacesEnd] == space || bytes[spacesEnd] == tab { spacesEnd += 1 }
            let spaces = spacesEnd - markerEnd
            guard spaces > 0 || endsLine(UnsafeBufferPointer(rebasing: bytes[markerEnd...])) else { return nil }
            // Five or more spaces start indented code in the item, whose content then starts
            // one space after the marker.
            return indentation + (markerEnd - contentStart) + ((1...4).contains(spaces) ? spaces : 1)
        }

        /// Whether `bytes` hold only line breaks, as a marker alone on its line is followed by.
        private static func endsLine(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
            guard bytes.contains(where: { byte in byte >= 0x80 }) else {
                return bytes.allSatisfy { byte in byte >= UInt8(ascii: "\n") && byte <= UInt8(ascii: "\r") }
            }
            // U+0085, U+2028 and U+2029 end lines too.
            return String(decoding: bytes, as: UTF8.self).allSatisfy(\.isNewline)
        }
    }

    /// The content column of the innermost open item that `line` reaches, which a fence on
    /// the line may be indented past by `MarkdownFenceSyntax.maximumIndentation` columns, or 0.
    /// A non-blank line closes the items it does not reach. Call once per line outside
    /// fenced code, in order, before `openListItem(of:)`.
    mutating func containerColumn(of line: LineStart) -> Int {
        if !line.isBlank {
            while let contentColumn = contentColumns.last, contentColumn > line.indentation { contentColumns.removeLast() }
        }
        return contentColumns.last ?? 0
    }

    /// Opens the list item `line` starts, if any, for the lines after it.
    mutating func openListItem(of line: LineStart) {
        if let contentColumn = line.listItemContentColumn { contentColumns.append(contentColumn) }
    }

    /// The fence `line` opens, its info text and the content column of its container, or
    /// nil; a line that opens no fence and starts a list item opens that item. Call once
    /// per line outside fenced code, in order.
    mutating func fenceOpening(of line: some StringProtocol) -> (fence: String, info: String, containerColumn: Int)? {
        let lineStart = LineStart(of: line)
        let containerColumn = containerColumn(of: lineStart)
        if lineStart.fenceCharacter != nil, lineStart.indentation <= containerColumn + MarkdownFenceSyntax.maximumIndentation,
           let (fence, info) = MarkdownFenceSyntax.opening(line.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return (fence, info, containerColumn)
        }
        openListItem(of: lineStart)
        return nil
    }

    /// Whether a fence line indented `indentation` columns, the line starting at `lineStart`
    /// in `text`, is within the indentation limit of its container, for a reader that looks
    /// at one line instead of walking from the top: indented past
    /// `MarkdownFenceSyntax.maximumIndentation` columns, it is a fence only that close to the
    /// content of the list item holding it, and only such a line looks its list item up.
    static func allowsFence(indentedBy indentation: Int, onLineAt lineStart: Int, in text: NSString) -> Bool {
        indentation <= MarkdownFenceSyntax.maximumIndentation
            || indentation <= containerColumn(ofLineAt: lineStart, in: text) + MarkdownFenceSyntax.maximumIndentation
    }

    /// The content column of the innermost list item holding the line that starts at
    /// `lineStart`, or 0, read backwards instead of following every line from the top:
    /// the nearest earlier item whose content column that line and every non-blank line
    /// between them reach. Unlike `fenceOpening(of:)` it does not skip fenced code, so a
    /// list marker written in code above the line counts as an item.
    static func containerColumn(ofLineAt lineStart: Int, in text: NSString) -> Int {
        var reachedColumn = leadingColumns(of: text.substring(with: text.lineRange(for: NSRange(location: lineStart, length: 0))))
        var earlierLineEnd = lineStart
        while earlierLineEnd > 0 && reachedColumn >= smallestContentColumn {
            let lineRange = text.lineRange(for: NSRange(location: earlierLineEnd - 1, length: 0))
            earlierLineEnd = lineRange.location
            let line = LineStart(of: text.substring(with: lineRange))
            guard !line.isBlank else { continue }
            if let contentColumn = line.listItemContentColumn, contentColumn <= reachedColumn { return contentColumn }
            reachedColumn = min(reachedColumn, line.indentation)
        }
        return 0
    }

    /// Leading indentation in columns, with tabs advancing to the next multiple of four.
    static func leadingColumns(of line: some StringProtocol) -> Int {
        var columns = 0
        for byte in line.utf8 {
            if byte == UInt8(ascii: " ") { columns += 1 } else if byte == UInt8(ascii: "\t") { columns += 4 - columns % 4 } else { break }
        }
        return columns
    }
}
