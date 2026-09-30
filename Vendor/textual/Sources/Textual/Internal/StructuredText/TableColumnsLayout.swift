import SwiftUI

// MARK: - Overview
//
// Graphite patch: `TableColumnsLayout` arranges a table's cells in place of SwiftUI's `Grid`.
//
// `Grid` gives each column the width its widest cell asks for, and a `Text` asks for whatever
// it is offered, down to one letter per line. A table offered less width than its content
// therefore either kept its full width (when offered none, as inside a horizontal scroll view)
// or broke words apart. This layout sizes columns the way a web browser sizes a table:
//
// - A column is never wider than its widest cell on one line.
// - A column is never narrower than the widest word, formula, or smallest image in it.
// - A table offered a width between those two shares what is left among its columns, in
//   proportion to how much each can shrink.
//
// A table that cannot become as narrow as it is offered keeps the narrowest width it can take,
// and its container scrolls.
//
// The two limits of a cell are measured on hidden copies of it (`TableCellWidthProbe`) where
// the visible cell cannot report them: its text wraps to any width, and its images already
// have the size of the column they are in. A cell of one word or formula needs no copy.

extension StructuredText {
  /// What a subview of `TableColumnsLayout` is.
  enum TableColumnsLayoutRole: Hashable {
    /// The visible cell. Its width on one line is each limit that no probe measures.
    case cell(row: Int, column: Int)
    /// A hidden copy of the cell, as narrow as it can be without breaking a word. A cell that
    /// can wrap, or whose attachments fit the width they are offered, has one.
    case narrowestWidthProbe(row: Int, column: Int)
    /// A hidden copy of the cell on one line, with its images at their full size. A cell
    /// whose attachments fit the width they are offered has one.
    case widestWidthProbe(row: Int, column: Int)
  }

  struct TableColumnsLayoutRoleKey: LayoutValueKey {
    static let defaultValue: TableColumnsLayoutRole? = nil
  }

  struct TableColumnsLayout: Layout {
    /// The space between cells when the table style sets none.
    static let defaultCellSpacing: CGFloat = 8

    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(
      proposal: ProposedViewSize,
      subviews: Subviews,
      cache: inout ()
    ) -> CGSize {
      arrangement(proposedWidth: proposal.width, subviews: subviews).size
    }

    func placeSubviews(
      in bounds: CGRect,
      proposal: ProposedViewSize,
      subviews: Subviews,
      cache: inout ()
    ) {
      let arrangement = arrangement(proposedWidth: proposal.width, subviews: subviews)

      for (subviewIndex, subview) in zip(subviews.indices, subviews) {
        guard case .cell(let row, let column) = subview[TableColumnsLayoutRoleKey.self],
          let cellHeight = arrangement.cellHeights[subviewIndex]
        else {
          // A probe is only measured. It is hidden, so where it lies does not matter.
          subview.place(at: bounds.origin, proposal: .unspecified)
          continue
        }

        // Cells are centered in their row, as `Grid` centers them.
        let rowHeight = arrangement.rowHeights[row]
        subview.place(
          at: CGPoint(
            x: bounds.minX + arrangement.columnMinX[column],
            y: bounds.minY + arrangement.rowMinY[row] + (rowHeight - cellHeight) / 2
          ),
          proposal: ProposedViewSize(width: arrangement.columnWidths[column], height: cellHeight)
        )
      }
    }

    /// The width of each column of a table that is offered `availableWidth` for its columns.
    ///
    /// - Parameters:
    ///   - narrowestWidths: The least width each column can take.
    ///   - widestWidths: The width each column takes when nothing in it wraps or shrinks.
    ///   - availableWidth: The width offered to the columns together, without the space
    ///     between them; nil when the table may take any width.
    static func columnWidths(
      narrowestWidths: [CGFloat],
      widestWidths: [CGFloat],
      availableWidth: CGFloat?
    ) -> [CGFloat] {
      let widestTotal = widestWidths.reduce(0, +)
      guard let availableWidth, availableWidth < widestTotal else {
        return widestWidths
      }

      let narrowestTotal = narrowestWidths.reduce(0, +)
      guard availableWidth > narrowestTotal else {
        return narrowestWidths
      }

      // Each column gives up the same share of the width it could give up.
      let keptShare = (availableWidth - narrowestTotal) / (widestTotal - narrowestTotal)
      return zip(narrowestWidths, widestWidths).map { narrowestWidth, widestWidth in
        // Whole points, so that no column starts between two points, where rounding its
        // frame would leave its text less width than it was measured for.
        (narrowestWidth + (widestWidth - narrowestWidth) * keptShare).rounded(.down)
      }
    }

    private struct Arrangement {
      var columnWidths: [CGFloat] = []
      var columnMinX: [CGFloat] = []
      var rowHeights: [CGFloat] = []
      var rowMinY: [CGFloat] = []
      /// The height of each visible cell at its column's width, by subview index.
      var cellHeights: [Int: CGFloat] = [:]
      var size = CGSize.zero
    }

    private func arrangement(proposedWidth: CGFloat?, subviews: Subviews) -> Arrangement {
      var rowCount = 0
      var columnCount = 0
      var cellsWithNarrowestWidthProbe: Set<TableCell.Identifier> = []
      var cellsWithWidestWidthProbe: Set<TableCell.Identifier> = []

      for subview in subviews {
        switch subview[TableColumnsLayoutRoleKey.self] {
        case .cell(let row, let column):
          rowCount = max(rowCount, row + 1)
          columnCount = max(columnCount, column + 1)
        case .narrowestWidthProbe(let row, let column):
          cellsWithNarrowestWidthProbe.insert(.init(row: row, column: column))
        case .widestWidthProbe(let row, let column):
          cellsWithWidestWidthProbe.insert(.init(row: row, column: column))
        case nil:
          break
        }
      }

      guard rowCount > 0, columnCount > 0 else {
        return Arrangement()
      }

      var narrowestWidths = [CGFloat](repeating: 0, count: columnCount)
      var widestWidths = [CGFloat](repeating: 0, count: columnCount)

      // Widths are rounded up to whole points: a frame that starts between two points is
      // rounded to them, and a cell made a fraction narrower than its text wraps it.
      for subview in subviews {
        switch subview[TableColumnsLayoutRoleKey.self] {
        case .narrowestWidthProbe(_, let column):
          let width = subview.sizeThatFits(.unspecified).width.rounded(.up)
          narrowestWidths[column] = max(narrowestWidths[column], width)
        case .widestWidthProbe(_, let column):
          let width = subview.sizeThatFits(.unspecified).width.rounded(.up)
          widestWidths[column] = max(widestWidths[column], width)
        case .cell(let row, let column):
          let cell = TableCell.Identifier(row: row, column: column)
          let measuresNarrowestWidth = !cellsWithNarrowestWidthProbe.contains(cell)
          let measuresWidestWidth = !cellsWithWidestWidthProbe.contains(cell)
          guard measuresNarrowestWidth || measuresWidestWidth else { break }
          let width = subview.sizeThatFits(.unspecified).width.rounded(.up)
          if measuresNarrowestWidth {
            narrowestWidths[column] = max(narrowestWidths[column], width)
          }
          if measuresWidestWidth {
            widestWidths[column] = max(widestWidths[column], width)
          }
        case nil:
          break
        }
      }

      for column in 0..<columnCount {
        narrowestWidths[column] = min(narrowestWidths[column], widestWidths[column])
      }

      let spacingWidth = horizontalSpacing * CGFloat(columnCount - 1)
      let availableWidth = proposedWidth.flatMap { proposedWidth in
        proposedWidth.isFinite ? max(proposedWidth - spacingWidth, 0) : nil
      }

      var arrangement = Arrangement()
      arrangement.columnWidths = Self.columnWidths(
        narrowestWidths: narrowestWidths,
        widestWidths: widestWidths,
        availableWidth: availableWidth
      )

      arrangement.rowHeights = [CGFloat](repeating: 0, count: rowCount)
      for (subviewIndex, subview) in zip(subviews.indices, subviews) {
        guard case .cell(let row, let column) = subview[TableColumnsLayoutRoleKey.self] else {
          continue
        }
        let cellHeight = subview.sizeThatFits(
          ProposedViewSize(width: arrangement.columnWidths[column], height: nil)
        ).height
        arrangement.cellHeights[subviewIndex] = cellHeight
        arrangement.rowHeights[row] = max(arrangement.rowHeights[row], cellHeight)
      }

      var nextColumnMinX: CGFloat = 0
      for columnWidth in arrangement.columnWidths {
        arrangement.columnMinX.append(nextColumnMinX)
        nextColumnMinX += columnWidth + horizontalSpacing
      }

      var nextRowMinY: CGFloat = 0
      for rowHeight in arrangement.rowHeights {
        arrangement.rowMinY.append(nextRowMinY)
        nextRowMinY += rowHeight + verticalSpacing
      }

      arrangement.size = CGSize(
        width: nextColumnMinX - horizontalSpacing,
        height: nextRowMinY - verticalSpacing
      )
      return arrangement
    }
  }
}
