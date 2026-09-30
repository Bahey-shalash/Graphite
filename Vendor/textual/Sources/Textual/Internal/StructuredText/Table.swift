import SwiftUI

// MARK: - Overview
//
// Table uses a two-pass layout system. The first pass renders cells which emit their bounds via
// preferences. The second pass collects all cell bounds, transforms them from anchor coordinates
// to geometry coordinates, and builds a `TableLayout` that the style uses to render overlays
// (such as grid lines) and backgrounds with precise cell positions.
//
// Graphite patch: `TableColumnsLayout` gives the columns their widths; see its overview.

extension StructuredText {
  struct Table: View {
    @Environment(\.tableStyle) private var tableStyle
    @Environment(\.textEnvironment) private var textEnvironment

    @State private var spacing = TableCell.Spacing()

    private let intent: PresentationIntent.IntentType?
    private let content: AttributedSubstring
    private let columns: [PresentationIntent.TableColumn]

    init(
      intent: PresentationIntent.IntentType?,
      content: AttributedSubstring,
      columns: [PresentationIntent.TableColumn]
    ) {
      self.intent = intent
      self.content = content
      self.columns = columns
    }

    var body: some View {
      let configuration = TableStyleConfiguration(
        label: .init(label),
        indentationLevel: indentationLevel
      )
      let resolvedStyle = tableStyle.resolve(configuration: configuration)
        .onPreferenceChange(TableCell.SpacingKey.self) { @MainActor in
          spacing = $0
        }

      AnyView(resolvedStyle)
    }

    @ViewBuilder
    private var label: some View {
      let cellContents = Self.cellContents(
        in: content, tableIntent: intent, columnCount: columns.count
      )

      // Graphite patch: `TableColumnsLayout` in place of `Grid`, so that a table offered less
      // width than its content wraps its text and shrinks its images to fit.
      TableColumnsLayout(
        horizontalSpacing: spacing.horizontal ?? TableColumnsLayout.defaultCellSpacing,
        verticalSpacing: spacing.vertical ?? TableColumnsLayout.defaultCellSpacing
      ) {
        ForEach(cellContents.indices, id: \.self) { rowIndex in
          ForEach(cellContents[rowIndex].indices, id: \.self) { columnIndex in
            let cellContent = cellContents[rowIndex][columnIndex]
            let fitsAttachmentsToColumn = cellContent.hasAttachmentsThatFitTheirWidth(
              in: textEnvironment
            )

            TableCell(
              cellContent,
              row: rowIndex,
              column: columnIndex,
              alignment: alignment(for: columnIndex),
              fitsAttachmentsToColumn: fitsAttachmentsToColumn
            )
            .layoutValue(
              key: TableColumnsLayoutRoleKey.self,
              value: .cell(row: rowIndex, column: columnIndex)
            )

            if fitsAttachmentsToColumn || cellContent.hasWordBreaks {
              TableCellWidthProbe(
                cellContent, row: rowIndex, column: columnIndex, width: .narrowest
              )
              .layoutValue(
                key: TableColumnsLayoutRoleKey.self,
                value: .narrowestWidthProbe(row: rowIndex, column: columnIndex)
              )
            }

            if fitsAttachmentsToColumn {
              TableCellWidthProbe(cellContent, row: rowIndex, column: columnIndex, width: .widest)
                .layoutValue(
                  key: TableColumnsLayoutRoleKey.self,
                  value: .widestWidthProbe(row: rowIndex, column: columnIndex)
                )
            }
          }
        }
      }
    }

    /// Graphite patch: the content of every cell of the table, by row and then column.
    ///
    /// A cell with nothing in it has no text, so the attributed string has no run for it, and
    /// a row of such cells has none either. Upstream laid out the cells that have runs one
    /// after another, so the header `| | A | B |` put "A" over the first column. Here a cell
    /// goes to the row and column its intent names, and a place without a run gets an empty
    /// cell, so every row has every column.
    static func cellContents(
      in content: AttributedSubstring,
      tableIntent: PresentationIntent.IntentType?,
      columnCount: Int
    ) -> [[AttributedSubstring]] {
      let emptyContent = content[content.startIndex..<content.startIndex]
      var rows: [[AttributedSubstring]] = []

      for rowRun in content.blockRuns(parent: tableIntent) {
        // A row or cell that names no place, or one already taken, follows the one before.
        let rowIndex = max(rowRun.intent?.tableRowIndex ?? rows.count, rows.count)
        rows.append(contentsOf: Array(repeating: [], count: rowIndex - rows.count))

        let rowContent = content[rowRun.range]
        var cells: [AttributedSubstring] = []
        for cellRun in rowContent.blockRuns(parent: rowRun.intent) {
          let columnIndex = max(cellRun.intent?.tableColumnIndex ?? cells.count, cells.count)
          cells.append(
            contentsOf: Array(repeating: emptyContent, count: columnIndex - cells.count)
          )
          cells.append(rowContent[cellRun.range])
        }
        rows.append(cells)
      }

      let widestRowCount = rows.map(\.count).max() ?? 0
      let filledColumnCount = max(columnCount, widestRowCount)
      return rows.map { cells in
        cells + Array(repeating: emptyContent, count: filledColumnCount - cells.count)
      }
    }

    private var indentationLevel: Int {
      content.runs.first?.presentationIntent?.indentationLevel ?? 0
    }

    private func alignment(for columnIndex: Int) -> HorizontalAlignment {
      guard columnIndex < columns.count else {
        return .leading
      }

      switch columns[columnIndex].alignment {
      case .left:
        return .leading
      case .center:
        return .center
      case .right:
        return .trailing
      @unknown default:
        return .leading
      }
    }
  }
}

extension PresentationIntent.IntentType {
  /// The row of a table this intent names, counting the header row as the first.
  fileprivate var tableRowIndex: Int? {
    switch kind {
    case .tableHeaderRow:
      return 0
    case .tableRow(let rowIndex):
      return rowIndex
    default:
      return nil
    }
  }

  /// The column of a table this intent names.
  fileprivate var tableColumnIndex: Int? {
    guard case .tableCell(let columnIndex) = kind else {
      return nil
    }
    return columnIndex
  }
}
