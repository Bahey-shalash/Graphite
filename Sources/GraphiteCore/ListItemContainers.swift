import Foundation

/// The list items a line can belong to, as CommonMark nests blocks: a non-blank line
/// belongs to the innermost item whose content column it reaches. A fence opens only
/// within `MarkdownFenceSyntax.maximumIndentation` columns of that column (column 0 outside lists),
/// so "    ```" continuing a paragraph is text while the same line inside a list item
/// opens a fence. The index, the editor, reading view and Live Preview find fence
/// openings through this type.
struct ListItemContainers {
    /// Content columns of the open items, innermost last; each is greater than the one before it.
    private var contentColumns: [Int] = []
    /// No item's content starts before this column: a one-character marker, then a space.
    private static let smallestContentColumn = 2

    init() {}

    /// The fence `line` opens, its info text and the content column of its container, or
    /// nil; a line that opens no fence and starts a list item opens that item. Call once
    /// per line outside fenced code, in order.
    mutating func fenceOpening(of line: String) -> (fence: String, info: String, containerColumn: Int)? {
        let indentation = Self.leadingColumns(of: line)
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLine.isEmpty {
            while let contentColumn = contentColumns.last, contentColumn > indentation { contentColumns.removeLast() }
        }
        let containerColumn = contentColumns.last ?? 0
        if indentation <= containerColumn + MarkdownFenceSyntax.maximumIndentation, let (fence, info) = MarkdownFenceSyntax.opening(trimmedLine) {
            return (fence, info, containerColumn)
        }
        if let contentColumn = Self.listItemContentColumn(of: line, indentation: indentation) { contentColumns.append(contentColumn) }
        return nil
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
            let line = text.substring(with: lineRange)
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let indentation = leadingColumns(of: line)
            if let contentColumn = listItemContentColumn(of: line, indentation: indentation), contentColumn <= reachedColumn { return contentColumn }
            reachedColumn = min(reachedColumn, indentation)
        }
        return 0
    }

    /// Leading indentation in columns, with tabs advancing to the next multiple of four.
    static func leadingColumns(of line: String) -> Int {
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
