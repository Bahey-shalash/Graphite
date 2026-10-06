import SwiftUI

extension TextualNamespace where Base: View {
  /// Graphite addition: lets a control inside selectable ``StructuredText`` be used.
  ///
  /// The text selection overlay covers the whole text and takes every touch and click,
  /// so a control a style adds, such as a checkbox drawn in place of a list marker,
  /// would never be reached. This reports the view's frame to the overlay, which leaves
  /// it out of hit testing, as it does for the scrollable regions of ``Overflow``.
  @MainActor public func excludedFromTextInteraction() -> some View {
    base.background(
      GeometryReader { geometry in
        Color.clear
          .preference(
            key: OverflowFrameKey.self,
            value: [geometry.frame(in: .textContainer)]
          )
      }
    )
  }
}
