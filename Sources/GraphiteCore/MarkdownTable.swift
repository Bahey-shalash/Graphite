import Foundation

/// A Markdown table read from its source: the cells of every row with where each cell's
/// text is, and the column alignments. It is a read-only view for an editor; edits go
/// through `MarkdownTableEditing`, which changes the source text and nothing else.
///
/// Cells are split as GFM splits them: at every `|` that is not preceded by a backslash,
/// so a pipe inside a code span still splits unless it is escaped. One pipe at each end
/// of a line is optional. A row may have fewer or more cells than the header.
public struct MarkdownTable: Equatable, Sendable {
    public enum ColumnAlignment: Equatable, Sendable { case none, left, center, right }

    /// One cell as written: its text between the pipes with surrounding spaces trimmed,
    /// escapes kept as written (`a \| b` stays `a \| b`).
    public struct Cell: Equatable, Sendable {
        public let source: String
        /// Where the trimmed text is in the table's source, UTF-16 (NSString) offsets.
        /// For an empty cell, a zero-length range where text typed into it would go.
        public let sourceRange: NSRange

        public init(source: String, sourceRange: NSRange) {
            self.source = source
            self.sourceRange = sourceRange
        }
    }

    /// Rows in display order: index 0 is the header, then the body rows. The delimiter row is not a row here.
    public let rows: [[Cell]]
    public let alignments: [ColumnAlignment]
    public var columnCount: Int { rows.first?.count ?? 0 }
    public var bodyRowCount: Int { max(rows.count - 1, 0) }

    /// Nil when `source` does not start with a header row over a delimiter row.
    ///
    /// Every non-blank line after the delimiter row is a body row; the table ends at the
    /// first blank line, and whatever follows is not part of it.
    public static func parse(_ source: String) -> MarkdownTable? {
        MarkdownTableLayout(source: source)?.table
    }
}

/// Edits of a table's source. Each takes the table's current source and returns the whole
/// edited source, or nil when the source is not a table or the index is out of range.
///
/// Every edit changes only the characters it has to: spacing, alignment padding, outer
/// pipes, indentation and line endings elsewhere stay as written. Where a pipe or a space
/// is needed to keep a cell that is empty at a line's edge readable by a GFM parser, the
/// edit adds it to that line only.
///
/// Rows shorter than the header: a cell a row does not have is treated as empty. Inserting
/// or removing a column leaves a row alone that does not reach the column, and moving
/// a column writes cells into a short row only when they have text.
public enum MarkdownTableEditing {
    /// `row` 0 is the header. A column past a short row's last cell adds the missing empty cells.
    /// The text is made safe for one cell: an unescaped `|` becomes `\|`, a line break becomes `<br>`.
    ///
    /// Replacing a cell with its own `editableText` leaves the source unchanged, so a `<br/>`
    /// that the editor showed as a line break is not rewritten as `<br>`. Clearing a cell that
    /// is the first or last of a line without outer pipes adds the pipe that keeps the empty
    /// cell a cell (`a | b` cleared at `a` becomes `|  | b`). Clearing a cell that does not
    /// exist changes nothing.
    public static func replacingCell(row: Int, column: Int, with text: String, in source: String) -> String? {
        guard let layout = MarkdownTableLayout(source: source), row >= 0, row <= layout.bodyRowCount, column >= 0 else { return nil }
        let line = layout.rowLine(row)
        guard column < max(layout.columnCount, line.cells.count) else { return nil }
        if column < line.cells.count, text == editableText(ofCellSource: layout.text(in: line.cells[column].textRange)) {
            return source
        }
        return layout.applying(layout.replacements(settingCellTexts: [column: cellSafeText(text)], in: line))
    }

    /// Inserts an empty body row so that it becomes body row `bodyRowIndex` (0 = first body row;
    /// `bodyRowCount` appends). Header cannot be inserted before.
    ///
    /// The row has as many empty cells as the header, written `|  |` when the header has outer
    /// pipes and ` | ` between cells when it has none, with the header's indentation and the
    /// table's line ending. Appended to a table whose last line has no line break, the break
    /// goes before the new row, so the source still ends without one.
    public static func insertingRow(atBodyIndex bodyRowIndex: Int, in source: String) -> String? {
        guard let layout = MarkdownTableLayout(source: source), bodyRowIndex >= 0, bodyRowIndex <= layout.bodyRowCount else { return nil }
        let header = layout.header
        let hasOuterPipes = header.hasLeadingPipe || header.hasTrailingPipe
        let rowText: String
        if hasOuterPipes {
            rowText = "|" + String(repeating: "  |", count: layout.columnCount)
        } else {
            rowText = Array(repeating: "", count: layout.columnCount).joined(separator: " | ")
        }
        let indentation = Array(layout.units[header.contentRange.lowerBound..<header.trimmedRange.lowerBound])
        let rowUnits = indentation + Array(rowText.utf16)
        let replacement: MarkdownTableReplacement
        if bodyRowIndex < layout.bodyRowCount {
            let lineStart = layout.lines[bodyRowIndex + 2].contentRange.lowerBound
            replacement = MarkdownTableReplacement(range: lineStart..<lineStart, units: rowUnits + layout.lineEnding)
        } else if let lastLine = layout.lines.last, lastLine.endingRange.isEmpty {
            let sourceEnd = lastLine.contentRange.upperBound
            replacement = MarkdownTableReplacement(range: sourceEnd..<sourceEnd, units: layout.lineEnding + rowUnits)
        } else if let lastLine = layout.lines.last {
            let lineEnd = lastLine.endingRange.upperBound
            replacement = MarkdownTableReplacement(range: lineEnd..<lineEnd, units: rowUnits + layout.lineEnding)
        } else {
            return nil
        }
        return layout.applying([replacement])
    }

    /// Removes the body row with its line break. When it is the last line and has no line
    /// break, the break before it goes instead, so the source still ends without one.
    public static func removingRow(atBodyIndex bodyRowIndex: Int, in source: String) -> String? {
        guard let layout = MarkdownTableLayout(source: source), bodyRowIndex >= 0, bodyRowIndex < layout.bodyRowCount else { return nil }
        let line = layout.lines[bodyRowIndex + 2]
        if !line.endingRange.isEmpty {
            return layout.applying([MarkdownTableReplacement(range: line.contentRange.lowerBound..<line.endingRange.upperBound, units: [])])
        }
        let previousLine = layout.lines[bodyRowIndex + 1]
        return layout.applying([MarkdownTableReplacement(range: previousLine.contentRange.upperBound..<line.contentRange.upperBound, units: [])])
    }

    /// Swaps body row `bodyRowIndex` with its neighbour (offset -1 up, +1 down).
    ///
    /// A larger offset moves the row that far and shifts the rows between. Nil when the
    /// target is not a body row; an offset of 0 returns the source unchanged. The rows'
    /// text moves with their own indentation and trailing spaces, while each line break
    /// stays where it is, so the table's last line still ends as it did.
    public static func movingRow(atBodyIndex bodyRowIndex: Int, by offset: Int, in source: String) -> String? {
        guard let layout = MarkdownTableLayout(source: source), bodyRowIndex >= 0, bodyRowIndex < layout.bodyRowCount else { return nil }
        let targetIndex = bodyRowIndex + offset
        guard targetIndex >= 0, targetIndex < layout.bodyRowCount else { return nil }
        guard offset != 0 else { return source }
        let firstIndex = min(bodyRowIndex, targetIndex)
        let lastIndex = max(bodyRowIndex, targetIndex)
        var newOrder = Array(firstIndex...lastIndex)
        let movedRow = newOrder.remove(at: bodyRowIndex - firstIndex)
        newOrder.insert(movedRow, at: targetIndex - firstIndex)
        var replacements: [MarkdownTableReplacement] = []
        for (position, sourceRowIndex) in newOrder.enumerated() {
            let destinationLine = layout.lines[firstIndex + position + 2]
            let sourceLine = layout.lines[sourceRowIndex + 2]
            replacements.append(MarkdownTableReplacement(range: destinationLine.contentRange, units: Array(layout.units[sourceLine.contentRange])))
        }
        return layout.applying(replacements)
    }

    /// Inserts an empty column so that it becomes column `columnIndex` (`columnCount` appends).
    ///
    /// The header gets an empty cell and the delimiter row ` --- `; a body row gets an empty
    /// cell written with single spaces. A body row that ends before the column is left alone,
    /// since its missing cells already read as empty; one that ends right at it gets the cell
    /// only when it has a trailing pipe. Inserting before the first cell of a line
    /// without a leading pipe gives that line one. Appending to a header or delimiter row
    /// that has no trailing pipe adds a trailing pipe only to the header, where the empty
    /// cell needs it.
    public static func insertingColumn(at columnIndex: Int, in source: String) -> String? {
        guard let layout = MarkdownTableLayout(source: source), columnIndex >= 0, columnIndex <= layout.columnCount else { return nil }
        var replacements: [MarkdownTableReplacement] = []
        for (lineIndex, line) in layout.lines.enumerated() {
            let isDelimiterRow = lineIndex == 1
            let isRequired = lineIndex <= 1
            let cellText = isDelimiterRow ? "---" : ""
            if let replacement = insertionReplacement(cellText: cellText, atColumn: columnIndex, in: line, isRequired: isRequired) {
                replacements.append(replacement)
            }
        }
        return layout.applying(replacements)
    }

    /// Nil when it is the only column. A row without a cell at that column is left alone.
    public static func removingColumn(at columnIndex: Int, in source: String) -> String? {
        guard let layout = MarkdownTableLayout(source: source), columnIndex >= 0, columnIndex < layout.columnCount, layout.columnCount > 1 else { return nil }
        var replacements: [MarkdownTableReplacement] = []
        for line in layout.lines {
            if let replacement = removalReplacement(ofColumn: columnIndex, in: line) {
                replacements.append(replacement)
            }
        }
        return layout.applying(replacements)
    }

    /// Moves the column by `offset` places, shifting the columns between; nil when the target
    /// is outside the table, and an offset of 0 returns the source unchanged.
    ///
    /// Only the text of the cells moves. Each cell's padding and every pipe stay where they
    /// are, so an aligned table keeps its shape. A short row's missing cells move as empty
    /// cells.
    public static func movingColumn(at columnIndex: Int, by offset: Int, in source: String) -> String? {
        guard let layout = MarkdownTableLayout(source: source), columnIndex >= 0, columnIndex < layout.columnCount else { return nil }
        let targetIndex = columnIndex + offset
        guard targetIndex >= 0, targetIndex < layout.columnCount else { return nil }
        guard offset != 0 else { return source }
        let firstIndex = min(columnIndex, targetIndex)
        let lastIndex = max(columnIndex, targetIndex)
        var replacements: [MarkdownTableReplacement] = []
        for line in layout.lines {
            let oldTexts = (firstIndex...lastIndex).map { index in
                index < line.cells.count ? layout.text(in: line.cells[index].textRange) : ""
            }
            var newTexts = oldTexts
            let movedText = newTexts.remove(at: columnIndex - firstIndex)
            newTexts.insert(movedText, at: targetIndex - firstIndex)
            var changedTexts: [Int: String] = [:]
            for (position, newText) in newTexts.enumerated() where newText != oldTexts[position] {
                changedTexts[firstIndex + position] = newText
            }
            replacements += layout.replacements(settingCellTexts: changedTexts, in: line)
        }
        return layout.applying(replacements)
    }

    /// Rewrites only that delimiter cell, keeping its width where it can: `-----` becomes
    /// `:---:`, with at least three dashes besides the colons. A column that already has the
    /// alignment is left as written, whatever its dashes.
    public static func settingAlignment(_ alignment: MarkdownTable.ColumnAlignment, ofColumn columnIndex: Int, in source: String) -> String? {
        guard let layout = MarkdownTableLayout(source: source), columnIndex >= 0, columnIndex < layout.columnCount else { return nil }
        let delimiter = layout.delimiter
        var currentWidth = 0
        if columnIndex < delimiter.cells.count {
            let cellText = layout.text(in: delimiter.cells[columnIndex].textRange)
            guard delimiterAlignment(ofCellText: cellText) != alignment else { return source }
            currentWidth = delimiter.cells[columnIndex].textRange.count
        } else if alignment == .none {
            return source
        }
        let newText = delimiterCellText(for: alignment, width: currentWidth)
        return layout.applying(layout.replacements(settingCellTexts: [columnIndex: newText], in: delimiter))
    }

    /// The text to show in a cell's editor for `cell.source`: the source as written, except
    /// `<br>` (any case, `<br/>`, `<br />`) shown as a line break. `replacingCell` turns it back.
    public static func editableText(ofCellSource cellSource: String) -> String {
        guard let lineBreakTag = lineBreakTagPattern else { return cellSource }
        let fullRange = NSRange(location: 0, length: (cellSource as NSString).length)
        return lineBreakTag.stringByReplacingMatches(in: cellSource, range: fullRange, withTemplate: "\n")
    }

    // MARK: Cell text

    private static let lineBreakTagPattern = try? NSRegularExpression(pattern: "<br[ \\t]*/?>", options: .caseInsensitive)

    /// Escapes every pipe that is not already escaped (a pipe after a backslash, as the
    /// parser reads it) and writes each line break, `\r\n` included, as one `<br>`.
    private static func cellSafeText(_ text: String) -> String {
        var safeUnits: [UInt16] = []
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit == MarkdownTableUnit.carriageReturn || unit == MarkdownTableUnit.lineFeed {
                if unit == MarkdownTableUnit.carriageReturn, index + 1 < units.count, units[index + 1] == MarkdownTableUnit.lineFeed {
                    index += 1
                }
                safeUnits.append(contentsOf: Array("<br>".utf16))
            } else if unit == MarkdownTableUnit.pipe, safeUnits.last != MarkdownTableUnit.backslash {
                safeUnits.append(MarkdownTableUnit.backslash)
                safeUnits.append(unit)
            } else {
                safeUnits.append(unit)
            }
            index += 1
        }
        return String(decoding: safeUnits, as: UTF16.self)
    }

    // MARK: Delimiter cells

    fileprivate static func delimiterAlignment(ofCellText cellText: String) -> MarkdownTable.ColumnAlignment {
        let startsWithColon = cellText.hasPrefix(":")
        let endsWithColon = cellText.count > 1 && cellText.hasSuffix(":")
        switch (startsWithColon, endsWithColon) {
        case (true, true): return .center
        case (true, false): return .left
        case (false, true): return .right
        case (false, false): return .none
        }
    }

    private static func delimiterCellText(for alignment: MarkdownTable.ColumnAlignment, width: Int) -> String {
        let leadingColon = alignment == .left || alignment == .center
        let trailingColon = alignment == .right || alignment == .center
        let colonCount = (leadingColon ? 1 : 0) + (trailingColon ? 1 : 0)
        let dashCount = max(minimumDelimiterDashCount, width - colonCount)
        return (leadingColon ? ":" : "") + String(repeating: "-", count: dashCount) + (trailingColon ? ":" : "")
    }

    /// GFM needs at least one dash; three is what editors write and what Obsidian shows.
    private static let minimumDelimiterDashCount = 3

    // MARK: Column edits

    private static func insertionReplacement(cellText: String, atColumn columnIndex: Int, in line: MarkdownTableLineLayout, isRequired: Bool) -> MarkdownTableReplacement? {
        let cellUnits = Array(cellText.utf16)
        if columnIndex < line.cells.count {
            if columnIndex == 0, !line.hasLeadingPipe {
                // An empty first cell can only be written after a leading pipe.
                let location = line.trimmedRange.lowerBound
                return MarkdownTableReplacement(range: location..<location, units: Array("| ".utf16) + cellUnits + Array(" | ".utf16))
            }
            let location = line.cells[columnIndex].segmentRange.lowerBound
            return MarkdownTableReplacement(range: location..<location, units: [MarkdownTableUnit.space] + cellUnits + Array(" |".utf16))
        }
        guard columnIndex == line.cells.count || isRequired else { return nil }
        let location = line.trimmedRange.upperBound
        if line.hasTrailingPipe {
            return MarkdownTableReplacement(range: location..<location, units: [MarkdownTableUnit.space] + cellUnits + Array(" |".utf16))
        }
        guard isRequired else { return nil }
        // Trailing spaces are not part of a line, so an empty cell at the end needs its own closing pipe.
        let appended = cellUnits.isEmpty ? " |  |" : " | " + cellText
        return MarkdownTableReplacement(range: location..<location, units: Array(appended.utf16))
    }

    private static func removalReplacement(ofColumn columnIndex: Int, in line: MarkdownTableLineLayout) -> MarkdownTableReplacement? {
        guard columnIndex < line.cells.count else { return nil }
        let cell = line.cells[columnIndex]
        if cell.isFollowedByPipe {
            if columnIndex == 0, !line.hasLeadingPipe {
                guard line.cells.count > 1 else {
                    return MarkdownTableReplacement(range: cell.segmentRange, units: [])
                }
                let nextCell = line.cells[1]
                if nextCell.isEmpty {
                    // The pipe stays and becomes the leading pipe, which keeps the next cell empty.
                    return MarkdownTableReplacement(range: cell.segmentRange, units: [])
                }
                return MarkdownTableReplacement(range: line.trimmedRange.lowerBound..<nextCell.textRange.lowerBound, units: [])
            }
            return MarkdownTableReplacement(range: cell.segmentRange.lowerBound..<(cell.segmentRange.upperBound + 1), units: [])
        }
        guard columnIndex > 0 else {
            // The line's only cell: what is left is a lone pipe, a row with one empty cell.
            if line.hasLeadingPipe {
                return MarkdownTableReplacement(range: cell.segmentRange, units: [])
            }
            return MarkdownTableReplacement(range: cell.segmentRange, units: [MarkdownTableUnit.pipe])
        }
        let previousCell = line.cells[columnIndex - 1]
        if previousCell.isEmpty {
            // The pipe before stays as the closing pipe so the empty cell before is not lost.
            return MarkdownTableReplacement(range: cell.segmentRange, units: [])
        }
        return MarkdownTableReplacement(range: previousCell.textRange.upperBound..<cell.segmentRange.upperBound, units: [])
    }
}

// MARK: - Source layout

private enum MarkdownTableUnit {
    static let pipe = UInt16(UInt8(ascii: "|"))
    static let backslash = UInt16(UInt8(ascii: "\\"))
    static let space = UInt16(UInt8(ascii: " "))
    static let tab = UInt16(UInt8(ascii: "\t"))
    static let lineFeed = UInt16(UInt8(ascii: "\n"))
    static let carriageReturn = UInt16(UInt8(ascii: "\r"))

    static func isSpace(_ unit: UInt16) -> Bool { unit == space || unit == tab }
}

/// A change to the source, in UTF-16 offsets of the source as it was before any change.
private struct MarkdownTableReplacement {
    let range: Range<Int>
    let units: [UInt16]
}

private struct MarkdownTableCellLayout {
    /// Everything between the pipes around the cell, spaces included.
    let segmentRange: Range<Int>
    /// The trimmed text. For an empty cell, an empty range where text typed into it goes:
    /// after the first space when there is one, so `|   |` becomes `| text  |`.
    let textRange: Range<Int>
    /// Whether a pipe ends the cell, which the last cell of a line has only with a trailing pipe.
    let isFollowedByPipe: Bool

    var isEmpty: Bool { textRange.isEmpty }
}

private struct MarkdownTableLineLayout {
    /// The line without its line break: indentation, text and trailing spaces.
    let contentRange: Range<Int>
    let endingRange: Range<Int>
    /// The line without indentation and trailing spaces, outer pipes included.
    let trimmedRange: Range<Int>
    let hasLeadingPipe: Bool
    let hasTrailingPipe: Bool
    let cells: [MarkdownTableCellLayout]

    /// Nil for a blank line, which ends a table.
    static func make(units: [UInt16], contentRange: Range<Int>, endingRange: Range<Int>) -> MarkdownTableLineLayout? {
        var trimmedStart = contentRange.lowerBound
        var trimmedEnd = contentRange.upperBound
        while trimmedStart < trimmedEnd, MarkdownTableUnit.isSpace(units[trimmedStart]) { trimmedStart += 1 }
        guard trimmedStart < trimmedEnd else { return nil }
        while MarkdownTableUnit.isSpace(units[trimmedEnd - 1]) { trimmedEnd -= 1 }

        func isSeparatingPipe(at location: Int) -> Bool {
            units[location] == MarkdownTableUnit.pipe && !(location > trimmedStart && units[location - 1] == MarkdownTableUnit.backslash)
        }
        let hasLeadingPipe = units[trimmedStart] == MarkdownTableUnit.pipe
        let cellsStart = hasLeadingPipe ? trimmedStart + 1 : trimmedStart
        var cellsEnd = trimmedEnd
        var hasTrailingPipe = false
        if cellsEnd > cellsStart, isSeparatingPipe(at: cellsEnd - 1) {
            hasTrailingPipe = true
            cellsEnd -= 1
        }

        var cells: [MarkdownTableCellLayout] = []
        var segmentStart = cellsStart
        var location = cellsStart
        while location <= cellsEnd {
            if location == cellsEnd || isSeparatingPipe(at: location) {
                let isLastCell = location == cellsEnd
                cells.append(cellLayout(units: units, segmentRange: segmentStart..<location, isFollowedByPipe: !isLastCell || hasTrailingPipe))
                segmentStart = location + 1
            }
            location += 1
        }
        return MarkdownTableLineLayout(
            contentRange: contentRange, endingRange: endingRange, trimmedRange: trimmedStart..<trimmedEnd,
            hasLeadingPipe: hasLeadingPipe, hasTrailingPipe: hasTrailingPipe, cells: cells)
    }

    private static func cellLayout(units: [UInt16], segmentRange: Range<Int>, isFollowedByPipe: Bool) -> MarkdownTableCellLayout {
        var textStart = segmentRange.lowerBound
        var textEnd = segmentRange.upperBound
        while textStart < textEnd, MarkdownTableUnit.isSpace(units[textStart]) { textStart += 1 }
        guard textStart < textEnd else {
            let insertionPoint = segmentRange.isEmpty ? segmentRange.lowerBound : segmentRange.lowerBound + 1
            return MarkdownTableCellLayout(segmentRange: segmentRange, textRange: insertionPoint..<insertionPoint, isFollowedByPipe: isFollowedByPipe)
        }
        while MarkdownTableUnit.isSpace(units[textEnd - 1]) { textEnd -= 1 }
        return MarkdownTableCellLayout(segmentRange: segmentRange, textRange: textStart..<textEnd, isFollowedByPipe: isFollowedByPipe)
    }
}

/// A table's source split into lines and cells, as UTF-16 units so every position is exact.
private struct MarkdownTableLayout {
    let units: [UInt16]
    /// The header, the delimiter row, then the body rows.
    let lines: [MarkdownTableLineLayout]
    /// The header's line break, which new rows use.
    let lineEnding: [UInt16]

    var header: MarkdownTableLineLayout { lines[0] }
    var delimiter: MarkdownTableLineLayout { lines[1] }
    var columnCount: Int { lines[0].cells.count }
    var bodyRowCount: Int { lines.count - 2 }

    /// Row 0 is the header; the delimiter row is not a row.
    func rowLine(_ row: Int) -> MarkdownTableLineLayout {
        row == 0 ? lines[0] : lines[row + 1]
    }

    func text(in range: Range<Int>) -> String {
        String(decoding: units[range], as: UTF16.self)
    }

    init?(source: String) {
        let units = Array(source.utf16)
        var rawLines: [(content: Range<Int>, ending: Range<Int>)] = []
        var lineStart = 0
        while lineStart < units.count {
            var contentEnd = lineStart
            while contentEnd < units.count, units[contentEnd] != MarkdownTableUnit.lineFeed, units[contentEnd] != MarkdownTableUnit.carriageReturn {
                contentEnd += 1
            }
            var endingEnd = contentEnd
            if contentEnd < units.count {
                endingEnd += 1
                if units[contentEnd] == MarkdownTableUnit.carriageReturn, endingEnd < units.count, units[endingEnd] == MarkdownTableUnit.lineFeed {
                    endingEnd += 1
                }
            }
            rawLines.append((lineStart..<contentEnd, contentEnd..<endingEnd))
            lineStart = endingEnd
        }
        guard rawLines.count >= 2,
              let header = MarkdownTableLineLayout.make(units: units, contentRange: rawLines[0].content, endingRange: rawLines[0].ending),
              let delimiter = MarkdownTableLineLayout.make(units: units, contentRange: rawLines[1].content, endingRange: rawLines[1].ending),
              MarkdownTableLayout.isDelimiterRow(delimiter, in: units),
              MarkdownTableLayout.startsTable(header: header, delimiter: delimiter, in: units)
        else { return nil }
        var lines = [header, delimiter]
        for rawLine in rawLines.dropFirst(2) {
            guard let line = MarkdownTableLineLayout.make(units: units, contentRange: rawLine.content, endingRange: rawLine.ending) else { break }
            lines.append(line)
        }
        self.units = units
        self.lines = lines
        self.lineEnding = Array(units[header.endingRange])
    }

    /// The same rule Live Preview uses to find a table: a delimiter row has only pipes,
    /// dashes, colons and spaces, with a dash among them.
    private static func isDelimiterRow(_ line: MarkdownTableLineLayout, in units: [UInt16]) -> Bool {
        let allowed = Set("|-: \t".utf16)
        let trimmedUnits = units[line.trimmedRange]
        return trimmedUnits.contains(UInt16(UInt8(ascii: "-"))) && trimmedUnits.allSatisfy { allowed.contains($0) }
    }

    /// A header row with a pipe over a delimiter row. Without a leading pipe, the delimiter
    /// row needs a pipe too, so text over a `---` rule is no table.
    private static func startsTable(header: MarkdownTableLineLayout, delimiter: MarkdownTableLineLayout, in units: [UInt16]) -> Bool {
        if header.hasLeadingPipe { return true }
        return units[header.trimmedRange].contains(MarkdownTableUnit.pipe) && units[delimiter.trimmedRange].contains(MarkdownTableUnit.pipe)
    }

    var table: MarkdownTable {
        let rows = (0..<(bodyRowCount + 1)).map { row in
            rowLine(row).cells.map { cell in
                MarkdownTable.Cell(
                    source: text(in: cell.textRange),
                    sourceRange: NSRange(location: cell.textRange.lowerBound, length: cell.textRange.count))
            }
        }
        let alignments = (0..<columnCount).map { column -> MarkdownTable.ColumnAlignment in
            guard column < delimiter.cells.count else { return .none }
            return MarkdownTableEditing.delimiterAlignment(ofCellText: text(in: delimiter.cells[column].textRange))
        }
        return MarkdownTable(rows: rows, alignments: alignments)
    }

    /// The source with the replacements made. They must not overlap. Where two start at the
    /// same place, the one given first ends up first.
    func applying(_ replacements: [MarkdownTableReplacement]) -> String {
        var editedUnits = units
        let orderedReplacements = replacements.enumerated().sorted { first, second in
            if first.element.range.lowerBound != second.element.range.lowerBound {
                return first.element.range.lowerBound > second.element.range.lowerBound
            }
            return first.offset > second.offset
        }
        for (_, replacement) in orderedReplacements {
            editedUnits.replaceSubrange(replacement.range, with: replacement.units)
        }
        return String(decoding: editedUnits, as: UTF16.self)
    }

    /// The edits that make cell `column` of `line` read as each given text, for the columns
    /// in `newTexts`. The texts are written as given; a cell already reading as its text is
    /// not touched. Columns past the line's last cell are added, with empty cells between,
    /// unless every text beyond the line is empty.
    func replacements(settingCellTexts newTexts: [Int: String], in line: MarkdownTableLineLayout) -> [MarkdownTableReplacement] {
        var replacements: [MarkdownTableReplacement] = []
        let columns = newTexts.keys.sorted()
        for column in columns where column < line.cells.count {
            if let replacement = replacement(settingCellAt: column, toText: newTexts[column] ?? "", in: line) {
                replacements.append(replacement)
            }
        }
        let lastColumnWithText = columns.last { column in
            column >= line.cells.count && !MarkdownTableLayout.isBlank(newTexts[column] ?? "")
        }
        if let lastColumnWithText {
            let appendedTexts = (line.cells.count...lastColumnWithText).map { column in newTexts[column] ?? "" }
            let appended = appendedTexts.map { appendedText in
                line.hasTrailingPipe ? " " + appendedText + " |" : " | " + appendedText
            }.joined()
            let location = line.trimmedRange.upperBound
            replacements.append(MarkdownTableReplacement(range: location..<location, units: Array(appended.utf16)))
        }
        return replacements
    }

    private static func isBlank(_ text: String) -> Bool {
        text.utf16.allSatisfy { MarkdownTableUnit.isSpace($0) }
    }

    private func replacement(settingCellAt column: Int, toText newText: String, in line: MarkdownTableLineLayout) -> MarkdownTableReplacement? {
        let cell = line.cells[column]
        let text = MarkdownTableLayout.isBlank(newText) ? "" : newText
        guard text != self.text(in: cell.textRange) else { return nil }
        guard !text.isEmpty else {
            return clearingReplacement(ofCellAt: column, in: line)
        }
        let textUnits = Array(text.utf16)
        let isFollowedByPipeWithoutSpace = cell.textRange.upperBound < units.count && units[cell.textRange.upperBound] == MarkdownTableUnit.pipe
        if !cell.isEmpty {
            // A backslash right before a pipe would escape it.
            let needsClosingSpace = textUnits.last == MarkdownTableUnit.backslash && isFollowedByPipeWithoutSpace
            return MarkdownTableReplacement(range: cell.textRange, units: textUnits + (needsClosingSpace ? [MarkdownTableUnit.space] : []))
        }
        let closingSpace: [UInt16] = cell.isFollowedByPipe ? [MarkdownTableUnit.space] : []
        switch cell.segmentRange.count {
        case 0:
            // `||` gets a space on each side, so the text stays readable.
            return MarkdownTableReplacement(range: cell.textRange, units: [MarkdownTableUnit.space] + textUnits + closingSpace)
        case 1:
            return MarkdownTableReplacement(range: cell.textRange, units: textUnits + closingSpace)
        default:
            return MarkdownTableReplacement(range: cell.textRange, units: textUnits)
        }
    }

    /// Empties a cell with text. At a line's edge without an outer pipe, the pipe that
    /// the empty cell needs to stay a cell is written in its place.
    private func clearingReplacement(ofCellAt column: Int, in line: MarkdownTableLineLayout) -> MarkdownTableReplacement {
        let cell = line.cells[column]
        let needsLeadingPipe = column == 0 && !line.hasLeadingPipe
        let needsTrailingPipe = column == line.cells.count - 1 && !line.hasTrailingPipe
        var clearedUnits: [UInt16] = []
        if needsLeadingPipe {
            clearedUnits += [MarkdownTableUnit.pipe, MarkdownTableUnit.space]
        }
        if needsTrailingPipe {
            let hasSpaceBefore = needsLeadingPipe || cell.textRange.lowerBound > cell.segmentRange.lowerBound
            clearedUnits += hasSpaceBefore ? [MarkdownTableUnit.pipe] : [MarkdownTableUnit.space, MarkdownTableUnit.pipe]
        }
        return MarkdownTableReplacement(range: cell.textRange, units: clearedUnits)
    }
}
