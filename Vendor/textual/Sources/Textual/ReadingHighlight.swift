import SwiftUI

/// A source location supplied by the host after validating its rendered text.
/// Add one attribute per word; several runs of that word can share its range.
public enum ReadingSourceRangeAttribute: AttributedStringKey {
  public typealias Value = NSRange
  public static let name = "Textual.ReadingSourceRange"
}

public struct ReadingHighlightGeometry: Equatable, Sendable {
  public let sourceRange: NSRange
  public let frame: CGRect
  public init(sourceRange: NSRange, frame: CGRect) {
    self.sourceRange = sourceRange
    self.frame = frame
  }
}

public struct ReadingHighlightGeometryKey: PreferenceKey {
  public static let defaultValue: [ReadingHighlightGeometry] = []
  public static func reduce(value: inout [ReadingHighlightGeometry], nextValue: () -> [ReadingHighlightGeometry]) {
    value.append(contentsOf: nextValue())
  }
}

extension TextualNamespace where Base: View {
  /// Draws temporary source-following highlights without replacing text selection
  /// or reparsing the attributed text on every spoken-word event.
  public func readingHighlight(_ sourceRange: NSRange?, color: Color = .yellow.opacity(0.35),
                               coordinateSpace: String? = nil) -> some View {
    base.environment(\.readingHighlightRange, sourceRange)
      .environment(\.readingHighlightColor, color)
      .environment(\.readingHighlightCoordinateSpace, coordinateSpace)
  }
}

extension AnyAttachment {
  /// Whether this is Textual's mathematical attachment, rather than an image.
  public var isMathematics: Bool { base is MathAttachment }

  /// Graphite patch: whether this draws a later piece of the formula drawn by the attachment
  /// before it; a formula a line may break inside is drawn in pieces.
  public var continuesFormula: Bool { (base as? MathAttachment)?.continuesFormula ?? false }
}

struct ReadingSourceRange: TextAttribute {
  let range: NSRange
}

extension EnvironmentValues {
  @Entry var readingHighlightRange: NSRange? = nil
  @Entry var readingHighlightColor: Color = .yellow.opacity(0.35)
  @Entry var readingHighlightCoordinateSpace: String? = nil
}

struct ReadingHighlight: ViewModifier {
  @Environment(\.readingHighlightRange) private var sourceRange
  @Environment(\.readingHighlightColor) private var color
  @Environment(\.readingHighlightCoordinateSpace) private var coordinateSpace

  func body(content: Content) -> some View {
    content.backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
      if let sourceRange, let anchoredLayout = layouts.first {
        GeometryReader { geometry in
          let origin = geometry[anchoredLayout.origin]
          let frames = anchoredLayout.layout.flatMap { line in
            line.compactMap { run -> CGRect? in
              guard let attribute = run[ReadingSourceRange.self],
                    NSIntersectionRange(sourceRange, attribute.range).length > 0 else { return nil }
              return run.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y)
            }
          }
          Canvas { context, _ in
            for frame in frames {
              context.fill(Path(roundedRect: frame, cornerRadius: 3), with: .color(color))
            }
          }
          .preference(key: ReadingHighlightGeometryKey.self, value: coordinateSpace.map { name in
            let container = geometry.frame(in: .named(name))
            return frames.map { frame in
              ReadingHighlightGeometry(sourceRange: sourceRange, frame: frame.offsetBy(dx: container.minX, dy: container.minY))
            }
          } ?? [])
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        }
      }
    }
  }
}
