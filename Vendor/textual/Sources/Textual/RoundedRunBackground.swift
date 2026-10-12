import SwiftUI

/// A rounded background, and optionally a border, for a run of text: a tag's pill or a
/// highlight with rounded ends. A host attaches it to an `AttributedString` run; `TextBuilder`
/// carries it into the text's layout, and the fragment draws it behind the run's bounds,
/// one shape per line the run spans.
public struct RoundedRunBackground: Hashable, Sendable {
  public let color: Color
  public let cornerRadius: CGFloat
  public let horizontalPadding: CGFloat
  public let borderColor: Color?
  public let borderWidth: CGFloat

  public init(color: Color, cornerRadius: CGFloat, horizontalPadding: CGFloat = 2, borderColor: Color? = nil, borderWidth: CGFloat = 0) {
    self.color = color
    self.cornerRadius = cornerRadius
    self.horizontalPadding = horizontalPadding
    self.borderColor = borderColor
    self.borderWidth = borderWidth
  }
}

/// Attaches a `RoundedRunBackground` to a run.
public enum RoundedRunBackgroundAttribute: AttributedStringKey {
  public typealias Value = RoundedRunBackground
  public static let name = "Textual.RoundedRunBackground"
}

struct RoundedRunBackgroundText: TextAttribute {
  let background: RoundedRunBackground
}

/// Draws the rounded backgrounds of a fragment's marked runs, behind its text.
struct RoundedRunBackgrounds: ViewModifier {
  func body(content: Content) -> some View {
    content.backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
      if let anchoredLayout = layouts.first {
        GeometryReader { geometry in
          let origin = geometry[anchoredLayout.origin]
          let shapes = Self.shapes(in: anchoredLayout.layout, origin: origin)
          if !shapes.isEmpty {
            Canvas { context, _ in
              for shape in shapes {
                let path = Path(roundedRect: shape.frame, cornerRadius: min(shape.background.cornerRadius, shape.frame.height / 2, shape.frame.width / 2))
                context.fill(path, with: .color(shape.background.color))
                if let borderColor = shape.background.borderColor, shape.background.borderWidth > 0 {
                  context.stroke(path, with: .color(borderColor), lineWidth: shape.background.borderWidth)
                }
              }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
          }
        }
      }
    }
  }

  /// One frame per line and background: neighbouring runs with the same background (a tag
  /// split by a style change) are joined.
  private static func shapes(in layout: Text.Layout, origin: CGPoint) -> [(frame: CGRect, background: RoundedRunBackground)] {
    var shapes: [(frame: CGRect, background: RoundedRunBackground)] = []
    for line in layout {
      var current: (frame: CGRect, background: RoundedRunBackground)?
      for run in line {
        guard let background = run[RoundedRunBackgroundText.self]?.background else {
          if let finished = current { shapes.append(finished); current = nil }
          continue
        }
        let bounds = run.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y)
        if let existing = current, existing.background == background {
          current = (existing.frame.union(bounds), background)
        } else {
          if let finished = current { shapes.append(finished) }
          current = (bounds, background)
        }
      }
      if let finished = current { shapes.append(finished) }
    }
    return shapes.map { shape in (shape.frame.insetBy(dx: -shape.background.horizontalPadding, dy: 0), shape.background) }
  }
}
