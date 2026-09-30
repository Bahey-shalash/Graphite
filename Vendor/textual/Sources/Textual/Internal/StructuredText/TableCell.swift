import SwiftUI

extension StructuredText {
  struct TableCell: View {
    @Environment(\.tableCellStyle) private var tableCellStyle

    // Graphite patch: the width the column leaves for the cell's content, which its images
    // fit. Only a cell with such attachments follows it.
    @State private var contentWidth: CGFloat?

    private let content: AttributedSubstring
    private let identifier: TableCell.Identifier
    private let alignment: HorizontalAlignment
    private let fitsAttachmentsToColumn: Bool

    init(
      _ content: AttributedSubstring,
      row: Int,
      column: Int,
      alignment: HorizontalAlignment,
      fitsAttachmentsToColumn: Bool
    ) {
      self.content = content
      self.identifier = .init(row: row, column: column)
      self.alignment = alignment
      self.fitsAttachmentsToColumn = fitsAttachmentsToColumn
    }

    var body: some View {
      let configuration = TableCellStyleConfiguration(
        label: .init(label),
        indentationLevel: indentationLevel,
        row: identifier.row,
        column: identifier.column
      )
      let resolvedStyle =
        tableCellStyle
        .resolve(configuration: configuration)
        .anchorPreference(key: BoundsKey.self, value: .bounds) { anchor in
          [identifier: anchor]
        }

      AnyView(resolvedStyle)
    }

    // Graphite patch: the content fills its column, where `Grid` aligned a cell of the
    // content's own width; the column's width is then the width attachments fit.
    private var label: some View {
      WithInlineStyle(AttributedString(content)) {
        TextFragment($0)
      }
      .environment(\.attachmentContainerWidth, fitsAttachmentsToColumn ? contentWidth : nil)
      .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
      .onGeometryChange(for: CGFloat?.self) { geometry in
        // Whole points: text as wide as an attachment is rounded up to whole pixels, which
        // would make it wider than a column that ends between two of them.
        fitsAttachmentsToColumn ? geometry.size.width.rounded(.down) : nil
      } action: { newWidth in
        contentWidth = newWidth
      }
    }

    private var indentationLevel: Int {
      content.presentationIntent?.indentationLevel ?? 0
    }
  }
}

extension StructuredText.TableCell {
  struct Identifier: Hashable {
    let row: Int
    let column: Int
  }

  struct BoundsKey: PreferenceKey {
    static let defaultValue: [Identifier: Anchor<CGRect>] = [:]

    static func reduce(
      value: inout [Identifier: Anchor<CGRect>],
      nextValue: () -> [Identifier: Anchor<CGRect>]
    ) {
      value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
  }
}

extension StructuredText.TableCell {
  struct Spacing: Sendable, Hashable {
    let horizontal: CGFloat?
    let vertical: CGFloat?

    init(horizontal: CGFloat? = nil, vertical: CGFloat? = nil) {
      self.horizontal = horizontal
      self.vertical = vertical
    }
  }

  struct SpacingKey: PreferenceKey {
    static let defaultValue = Spacing()

    static func reduce(value: inout Spacing, nextValue: () -> Spacing) {
      value = nextValue()
    }
  }
}
