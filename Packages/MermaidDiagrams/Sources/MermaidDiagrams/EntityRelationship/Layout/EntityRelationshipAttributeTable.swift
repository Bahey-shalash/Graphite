import CoreGraphics

/// An entity's attribute rows as a table, as Pele lays it out: each column as wide as its widest cell, a column no
/// cell fills taking no room, 16 points between columns, and the box's spare width shared between the columns; each
/// row as tall as its tallest cell, at least one line, and 9 points more. A cell's lines start at its column's left
/// edge, and the first line of every cell of a row sits on one baseline.
struct EntityRelationshipAttributeTable {
    static let columnGap: CGFloat = 16
    static let rowPadding: CGFloat = 9

    /// For each row, its four cells: type, name, keys, comment.
    let cells: [[DiagramTextBlock]]
    let columnWidths: [CGFloat]
    let rowHeights: [CGFloat]
    /// The height of one line of the rows' text, which every cell's first line is centered on.
    let rowLineHeight: CGFloat

    init(cells: [[DiagramTextBlock]], rowLineHeight: CGFloat) {
        self.cells = cells
        self.rowLineHeight = rowLineHeight
        var columnWidths = [CGFloat](repeating: 0, count: EntityRelationshipColumn.allCases.count)
        for row in cells {
            for (column, cell) in row.enumerated() { columnWidths[column] = max(columnWidths[column], cell.size.width) }
        }
        self.columnWidths = columnWidths
        rowHeights = cells.map { row in max(rowLineHeight, row.map(\.size.height).max() ?? 0) + Self.rowPadding }
    }

    /// The width of the filled columns and the gaps between them.
    var filledWidth: CGFloat {
        let filled = columnWidths.filter { width in width > 0 }
        return filled.reduce(0, +) + CGFloat(max(filled.count - 1, 0)) * Self.columnGap
    }

    var height: CGFloat {
        rowHeights.reduce(0, +)
    }

    /// The rows placed in a box `width` wide from `top`, the columns starting `inset` from its left side.
    /// - Parameter rowFontSize: The size of the rows' text, whose baseline the smaller keys share.
    func rows(top: CGFloat, width: CGFloat, inset: CGFloat, rowFontSize: CGFloat) -> [EntityRelationshipLayoutRow] {
        let lefts = columnLefts(width: width, inset: inset)
        var rowTop = top
        return cells.enumerated().map { rowIndex, rowCells in
            var texts: [EntityRelationshipLayoutCellText] = []
            for (column, cell) in zip(EntityRelationshipColumn.allCases, rowCells) {
                let baselineShift = (rowFontSize - cell.fontSize) * DiagramTextDrawing.baselineShiftRatio
                let firstLineCenterY = rowTop + Self.rowPadding / 2 + rowLineHeight / 2 + baselineShift
                texts += cell.leftAlignedLines(left: lefts[columnIndex(column)], firstLineCenterY: firstLineCenterY).map { line in
                    EntityRelationshipLayoutCellText(column: column, text: line)
                }
            }
            let row = EntityRelationshipLayoutRow(frame: CGRect(x: 0, y: rowTop, width: width, height: rowHeights[rowIndex]), texts: texts)
            rowTop += rowHeights[rowIndex]
            return row
        }
    }

    /// Each column's left edge: the spare width beyond the filled columns is shared between them.
    private func columnLefts(width: CGFloat, inset: CGFloat) -> [CGFloat] {
        let filledCount = columnWidths.filter { columnWidth in columnWidth > 0 }.count
        let spare = filledCount > 0 ? (width - filledWidth - 2 * inset) / CGFloat(filledCount) : 0
        var left = inset
        return columnWidths.map { columnWidth in
            let columnLeft = left
            if columnWidth > 0 { left += columnWidth + spare + Self.columnGap }
            return columnLeft
        }
    }

    private func columnIndex(_ column: EntityRelationshipColumn) -> Int {
        switch column {
        case .type: 0
        case .name: 1
        case .keys: 2
        case .comment: 3
        }
    }
}

private extension DiagramTextBlock {
    /// Each line as a block of its own that starts at `left`, the first centered on `firstLineCenterY` and each next
    /// one a line lower.
    func leftAlignedLines(left: CGFloat, firstLineCenterY: CGFloat) -> [DiagramTextBlock] {
        lines.indices.map { index in
            DiagramTextBlock(line: lines[index], width: lineWidths[index], fontSize: fontSize, lineHeight: lineHeight,
                             center: CGPoint(x: left + lineWidths[index] / 2, y: firstLineCenterY + CGFloat(index) * lineHeight))
        }
    }

    init(line: String, width: CGFloat, fontSize: CGFloat, lineHeight: CGFloat, center: CGPoint) {
        lines = [line]
        lineWidths = [width]
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.center = center
    }
}
