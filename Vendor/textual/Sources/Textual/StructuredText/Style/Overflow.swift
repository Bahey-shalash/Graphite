import SwiftUI

/// Controls how content behaves when it overflows horizontally.
public enum OverflowMode: Hashable {
  /// Wraps content to fit the available width.
  case wrap
  /// Allows horizontal scrolling.
  case scroll
}

/// Describes the current overflow behavior and available layout metrics.
public enum OverflowState: Hashable {
  /// Wraps content to fit the available width.
  case wrap
  /// Scrolls horizontally. The container width is provided when available.
  case scroll(containerWidth: CGFloat?)

  /// The scroll container width when available; otherwise `nil`.
  public var containerWidth: CGFloat? {
    guard case .scroll(let containerWidth) = self else {
      return nil
    }
    return containerWidth
  }
}

/// A container that adapts to the current ``OverflowMode``.
///
/// `Overflow` handles content that overflows horizontally. It can switch
/// between wrapping and horizontal scrolling based on an environment value.
///
/// You can set the mode using the ``TextualNamespace/overflowMode(_:)`` modifier. The default is
/// ``OverflowMode/scroll``.
///
/// - Note: You should always use `Overflow` if your custom style needs horizontal scrolling.
///   Using a horizontal `ScrollView` directly will interfere with text selection gestures.
public struct Overflow<Content: View>: View {
  @Environment(\.overflowMode) private var mode
  @State private var containerWidth: CGFloat?
  @State private var contentHeight: CGFloat?
  /// Graphite: with `scrollsOnlyWhenWider`, whether the content was last measured wider
  /// than the space it is shown in, so it needs the scroll view.
  @State private var isWiderThanContainer = false
  @State private var measuredContentWidth: CGFloat?
  @State private var availableWidth: CGFloat?
  /// The width the content was found wider than. It leaves the scroll view only once the
  /// space grows past it: measured in the scroll view, the content passes through other
  /// widths as it is laid out again, and comparing those switched it in and out for good.
  @State private var widthWhenFoundWider: CGFloat?

  private let content: (OverflowState) -> Content
  private let scrollsOnlyWhenWider: Bool

  /// Creates an overflow container.
  public init(@ViewBuilder content: @escaping () -> Content) {
    self.init { _ in
      content()
    }
  }

  /// Creates an overflow container that exposes the current overflow state.
  ///
  /// - Parameter scrollsOnlyWhenWider: Graphite: in ``OverflowMode/scroll``, the content is
  ///   shown without a scroll view while it fits the width it is offered, and moves into one
  ///   only when it is wider. For content that can shrink to its width, such as a table; not
  ///   for content that would wrap instead of growing, such as code.
  public init(scrollsOnlyWhenWider: Bool = false, @ViewBuilder content: @escaping (_ state: OverflowState) -> Content) {
    self.content = content
    self.scrollsOnlyWhenWider = scrollsOnlyWhenWider
  }

  /// Half a point of slack, so a width rounded to pixels does not count as wider.
  private static var widthTolerance: CGFloat { 0.5 }

  private func updateWhetherWider() {
    if isWiderThanContainer {
      guard let containerWidth, let widthWhenFoundWider, containerWidth > widthWhenFoundWider + Self.widthTolerance else { return }
      measuredContentWidth = nil
      availableWidth = nil
      isWiderThanContainer = false
      return
    }
    guard let measuredContentWidth, let availableWidth, availableWidth > 0,
          measuredContentWidth > availableWidth + Self.widthTolerance else { return }
    widthWhenFoundWider = availableWidth
    isWiderThanContainer = true
  }

  public var body: some View {
    switch mode {
    case .wrap:
      content(.wrap)
        .frame(maxWidth: .infinity, alignment: .leading)

    case .scroll where scrollsOnlyWhenWider && !isWiderThanContainer:
      // Laid out in place, at the width offered; content that cannot shrink to it reports
      // a larger width, and then moves into the scroll view. The frame around it keeps the
      // width offered: a flexible frame grows to wider content, which then never measured
      // wider and was centered over the column's edges.
      OfferedWidthFrame {
        content(.wrap)
          .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
            measuredContentWidth = width
            updateWhetherWider()
          }
      }
      .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
        availableWidth = width
        updateWhetherWider()
      }

    case .scroll:
      ScrollView(.horizontal) {
        ZStack {
          // Update the scroll view height when the content height changes
          Color.clear
            .frame(minHeight: contentHeight)
          content(.scroll(containerWidth: containerWidth))
            .onGeometryChange(for: CGFloat.self, of: \.size.height) {
              contentHeight = $0
            }
            // Make text selection local in scrollable regions
            .modifier(TextSelectionInteraction())
            .transformPreference(Text.LayoutKey.self) { value in
              value = []
            }
        }
      }
      // Graphite: a horizontal scroll view takes no vertical drag. Its content's height is
      // rounded to pixels, and the fraction over the frame let a swipe move the content
      // up and down a little.
      .scrollBounceBehavior(.basedOnSize, axes: .vertical)
      .onScrollGeometryChange(for: CGFloat.self, of: \.containerSize.width) {
        containerWidth = $1
        // Graphite: more space (the window grew) lets content that may fit now leave the
        // scroll view, to be measured in place again.
        if scrollsOnlyWhenWider { updateWhetherWider() }
      }
      // Propagate gesture exclusion area
      .background(
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
}

extension EnvironmentValues {
  @usableFromInline
  @Entry var overflowMode = OverflowMode.scroll
}

/// Graphite: takes the width it is offered whatever its content's width, with the content at
/// its leading edge, so a parent can compare the two.
private struct OfferedWidthFrame: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let contentSize = subviews.first?.sizeThatFits(proposal) ?? .zero
    return CGSize(width: proposal.width ?? contentSize.width, height: contentSize.height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: proposal.height))
  }
}
