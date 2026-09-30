import SwiftUI

// MARK: - Overview
//
// Graphite patch: `TableCellWidthProbe` is a hidden copy of a table cell that
// `TableColumnsLayout` measures to learn the limits of the cell's width.
//
// It goes through the table cell style, as the visible cell does, so it has the cell's padding
// and font. Its text is a plain `Text`, not a `TextFragment`: it is never shown, so it takes no
// part in selection, links, or drawing attachments.

extension StructuredText {
  struct TableCellWidthProbe: View {
    enum Width {
      /// Each word on a line of its own, and each attachment as small as it can be.
      case narrowest
      /// Everything on one line, and each attachment at its full size.
      case widest
    }

    @Environment(\.tableCellStyle) private var tableCellStyle

    private let content: AttributedSubstring
    private let identifier: TableCell.Identifier
    private let width: Width

    init(_ content: AttributedSubstring, row: Int, column: Int, width: Width) {
      self.content = content
      self.identifier = .init(row: row, column: column)
      self.width = width
    }

    var body: some View {
      let configuration = TableCellStyleConfiguration(
        label: .init(label),
        indentationLevel: content.presentationIntent?.indentationLevel ?? 0,
        row: identifier.row,
        column: identifier.column
      )

      AnyView(tableCellStyle.resolve(configuration: configuration))
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transformPreference(Text.LayoutKey.self) { value in
          value = []
        }
    }

    private var label: some View {
      WithInlineStyle(AttributedString(content)) {
        ProbeText(content: $0, width: width)
      }
    }
  }

  fileprivate struct ProbeText: View {
    @Environment(\.textEnvironment) private var textEnvironment

    let content: AttributedString
    let width: TableCellWidthProbe.Width

    var body: some View {
      switch width {
      case .narrowest:
        Text(
          attributedString: content.breakingAfterEveryWord(),
          attachmentProposal: .narrowestWidth,
          in: textEnvironment
        )
      case .widest:
        Text(attributedString: content, attachmentProposal: .unspecified, in: textEnvironment)
      }
    }
  }
}

extension ProposedViewSize {
  /// The proposal an attachment answers with the smallest size it can take.
  static let narrowestWidth = ProposedViewSize(width: 0, height: nil)
}

extension AttributedStringProtocol {
  /// Whether an attachment takes less width when it is offered less, as an image does and
  /// an inline formula does not.
  func hasAttachmentsThatFitTheirWidth(in environment: TextEnvironmentValues) -> Bool {
    runs.contains { run in
      guard let attachment = run.textual.attachment else {
        return false
      }
      var environment = environment
      environment.font = run.font ?? environment.font
      let narrowestWidth = attachment.sizeThatFits(.narrowestWidth, in: environment).width
      return narrowestWidth < attachment.sizeThatFits(.unspecified, in: environment).width
    }
  }

  /// Whether the text has a space or tab to wrap at; it is as wide as it can be narrow
  /// otherwise, unless an attachment in it shrinks.
  var hasWordBreaks: Bool {
    characters.contains { character in character.isWordBreak }
  }

  /// A copy with a line break in place of each space or tab, so that each word is on a line
  /// of its own. On one line, the copy is as wide as its widest word: the least width the
  /// text can wrap to without breaking a word.
  ///
  /// A non-breaking space is kept, as are the attachments.
  func breakingAfterEveryWord() -> AttributedString {
    var output = AttributedString()

    for run in runs {
      guard run.textual.attachment == nil else {
        output.append(AttributedString(self[run.range]))
        continue
      }
      let characters = String(self[run.range].characters[...]).map { character in
        character.isWordBreak ? "\n" : character
      }
      output.append(AttributedString(String(characters), attributes: run.attributes))
    }

    return output
  }
}

extension Character {
  /// A space or a tab, where a line may break; a non-breaking space is neither.
  fileprivate var isWordBreak: Bool {
    self == " " || self == "\t"
  }
}
