import SwiftUI

// MARK: - Overview
//
// TextFragment renders attributed content as SwiftUI.Text with support for inline
// attachments, links, and selection. It uses a TextBuilder to construct and cache
// Text values, minimizing rebuilds during resize by keying on attachment sizes.
//
// Attachments are represented as placeholder images tagged with AttachmentAttribute. The
// actual attachment views are rendered in an overlay using the resolved Text.Layout
// geometry. Three modifiers are applied at the fragment level:
//
// - TextSelectionBackground renders selection highlights on macOS
// - AttachmentOverlay draws attachments at their run locations with selection-aware dimming
// - TextLinkInteraction handles tap gestures on links
//
// These overlays use backgroundPreferenceValue and overlayPreferenceValue to access
// Text.Layout and render in fragment-local coordinates. Fragment-level overlays enable
// coordinate space isolation and keep scrollable regions interactive.
//
// An ancestor view must define a named coordinate space (.textContainer) for the text
// container. TextFragment uses onGeometryChange to observe the container size and rebuild
// Text when attachment sizes need to change.
//
// TextFragment is used by InlineText and StructuredText (via BlockContent) to render
// attributed content with inline attachments, links, and selection.

struct TextFragment<Content: AttributedStringProtocol>: View {
  @Environment(\.textEnvironment) private var textEnvironment
  // Graphite patch: a table cell gives its own width, which its attachments fit instead of
  // the width of the whole text container.
  @Environment(\.attachmentContainerWidth) private var attachmentContainerWidth
  @State private var textBuilder: TextBuilder?

  private let content: Content

  init(_ content: Content) {
    self.content = content
  }

  var body: some View {
    text
      .customAttribute(TextFragmentAttribute())
      .onGeometryChange(for: CGSize?.self, of: \.textContainerSize) { size in
        guard let size, let textBuilder, attachmentContainerWidth == nil else { return }
        textBuilder.sizeChanged(size, environment: textEnvironment)
      }
      .onChange(of: content, initial: true) { _, newValue in
        self.textBuilder = TextBuilder(
          newValue,
          attachmentProposal: attachmentContainerWidth.map { width in
            ProposedViewSize(width: width, height: nil)
          } ?? .unspecified,
          environment: textEnvironment
        )
      }
      .onChange(of: attachmentContainerWidth) { _, newWidth in
        guard let newWidth, let textBuilder else { return }
        textBuilder.proposalChanged(
          ProposedViewSize(width: newWidth, height: nil),
          environment: textEnvironment
        )
      }
      .modifier(TextSelectionBackground())
      .modifier(AttachmentOverlay(attachments: content.attachments()))
      .modifier(TextLinkInteraction())
  }

  private var text: Text {
    textBuilder?.text ?? Text(verbatim: "")
  }
}

struct TextFragmentAttribute: TextAttribute {
}

extension Text.Layout {
  var isTextFragment: Bool {
    first?.first?[TextFragmentAttribute.self] != nil
  }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
  static var textContainer: NamedCoordinateSpace {
    .named("textContainer")
  }
}

extension GeometryProxy {
  fileprivate var textContainerSize: CGSize? {
    bounds(of: .textContainer)?.size
  }
}

extension EnvironmentValues {
  /// Graphite patch: the width a text fragment's attachments fit, in place of the text
  /// container's width; nil outside a table cell.
  @Entry var attachmentContainerWidth: CGFloat? = nil
}
