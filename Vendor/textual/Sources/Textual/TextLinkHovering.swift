import SwiftUI

/// Graphite addition: the pointer and a long press on the links of selectable
/// ``StructuredText``, which a host shows link previews for.
public enum TextLinkHover: Equatable, Sendable {
  /// The pointer (a mouse, a trackpad, or Apple Pencil hovering) came onto a link, whose
  /// text under the pointer is drawn in `frame`, in the window's own coordinates
  /// (`convert(_:to: nil)`).
  case entered(URL, frame: CGRect)
  /// The pointer left the link.
  case exited(URL)
  /// A link was held (a long press on a touch screen), drawn in `frame` as for `entered`.
  case pressed(URL, frame: CGRect)
}

/// Graphite addition: what a host does with ``TextLinkHover`` events.
public struct TextLinkHoverAction: Sendable {
  private let handler: @MainActor @Sendable (TextLinkHover) -> Void

  public init(_ handler: @escaping @MainActor @Sendable (TextLinkHover) -> Void) {
    self.handler = handler
  }

  @MainActor func callAsFunction(_ hover: TextLinkHover) {
    handler(hover)
  }
}

extension EnvironmentValues {
  /// Nil unless a host asks: then nothing watches the pointer for links.
  @Entry var textLinkHoverAction: TextLinkHoverAction? = nil
}

extension TextualNamespace where Base: View {
  /// Graphite addition: tells `action` when the pointer comes onto a link of selectable text
  /// and leaves it, and when a link is held. With no action nothing watches the pointer.
  public func linkHoverAction(_ action: TextLinkHoverAction?) -> some View {
    base.environment(\.textLinkHoverAction, action)
  }
}
