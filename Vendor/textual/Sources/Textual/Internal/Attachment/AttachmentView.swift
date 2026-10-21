import SwiftUI

// MARK: - Overview
//
// `AttachmentView` draws attachment bodies at the positions reported by SwiftUI's `Text.Layout`.
//
// The `Text` pipeline reserves space for attachments using placeholders; the overlay places the
// real SwiftUI views on top of those placeholders, each framed to its run's `typographicBounds`.
//
// Selection integration:
// On macOS, when text selection is enabled, object-style attachments are dimmed when they fall
// inside the selected range. Inline-style attachments (for example, emoji) are not dimmed.

struct AttachmentView: View {
  #if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit)
    @Environment(TextSelectionModel.self) private var textSelectionModel: TextSelectionModel?
  #endif
  private let attachments: Set<AnyAttachment>
  private let origin: CGPoint
  private let layout: Text.Layout

  init(
    attachments: Set<AnyAttachment>,
    origin: CGPoint,
    layout: Text.Layout
  ) {
    self.attachments = attachments
    self.origin = origin
    self.layout = layout
  }

  // Each attachment is placed as a view on its run's bounds, not drawn into a `Canvas`: a
  // canvas draws through RenderBox, which starts a Metal device that holds about 200 MB while
  // a note scrolls (Graphite patch 19).
  var body: some View {
    ZStack(alignment: .topLeading) {
      ForEach(placements) { placement in
        placement.attachment.body
          .frame(width: placement.frame.width, height: placement.frame.height)
          .opacity(placement.opacity)
          .offset(x: origin.x + placement.frame.minX, y: origin.y + placement.frame.minY)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private struct Placement: Identifiable {
    let attachment: AnyAttachment
    let frame: CGRect
    let opacity: CGFloat
    let lineIndex: Int
    let runIndex: Int

    var id: [Int] { [lineIndex, runIndex] }
  }

  /// Every run that holds one of the attachments, with where and how opaque it is drawn.
  private var placements: [Placement] {
    var placements: [Placement] = []
    for (lineIndex, line) in zip(layout.indices, layout) {
      for (runIndex, run) in zip(line.indices, line) {
        guard let attachment = run.attachment, attachments.contains(attachment) else { continue }
        placements.append(
          Placement(
            attachment: attachment,
            frame: run.typographicBounds.rect,
            opacity: opacity(for: attachment, lineIndex: lineIndex, runIndex: runIndex),
            lineIndex: lineIndex,
            runIndex: runIndex
          )
        )
      }
    }
    return placements
  }

  private func opacity(
    for attachment: AnyAttachment,
    lineIndex: Int,
    runIndex: Int
  ) -> CGFloat {
    #if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit)
      guard
        attachment.selectionStyle == .object,
        let textSelectionModel,
        let selectedRange = textSelectionModel.selectedRange,
        let layoutIndex = textSelectionModel.layoutIndex(of: layout)
      else {
        return 1
      }

      let position = TextPosition(
        indexPath: .init(run: runIndex, line: lineIndex, layout: layoutIndex),
        affinity: .downstream
      )

      return selectedRange.contains(position) ? 0.5 : 1
    #else
      1
    #endif
  }
}
