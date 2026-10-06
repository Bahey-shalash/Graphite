import SwiftUI
@_spi(Textual) private import SwiftUIMath

/// Graphite addition: measures display math for views that lay out a formula themselves
/// (an equation with its number at the edge of the column). Uses the same font and
/// typesetting as block math in ``StructuredText``.
public enum DisplayMathRendering {
  /// The size of a typeset formula. The baseline is `ascent` below its top.
  public typealias Metrics = InlineMathRendering.Metrics

  /// The formula's size on one line, or broken into lines no wider than `width` when
  /// one is given; nil when the LaTeX cannot be typeset.
  public static func metrics(for latex: String, fontSize: CGFloat, fittingWidth width: CGFloat? = nil) -> Metrics? {
    let bounds = Math.typographicBounds(
      for: latex,
      fitting: ProposedViewSize(width: width, height: nil),
      font: font(size: fontSize),
      style: .display
    )
    guard bounds.width > 0 else { return nil }
    return Metrics(width: bounds.width, ascent: bounds.ascent, descent: bounds.descent)
  }

  fileprivate static func font(size: CGFloat) -> Math.Font {
    Math.Font(name: .latinModern, size: size)
  }
}

/// Graphite addition: a formula drawn as block math in ``StructuredText`` is: on one line
/// at its natural width, or broken into lines when it is given less.
public struct DisplayMathView: View {
  private let latex: String
  private let fontSize: CGFloat

  public init(latex: String, fontSize: CGFloat) {
    self.latex = latex
    self.fontSize = fontSize
  }

  public var body: some View {
    // Drawn as a canvas symbol, as an attachment is. A symbol keeps the formula's exact
    // size. A view's frame is rounded to whole pixels, and in a frame a fraction of a
    // point narrower than the formula the typesetter breaks the formula into lines.
    DisplayMathSize(latex: latex, fontSize: fontSize) {
      Canvas { context, _ in
        guard let formula = context.resolveSymbol(id: latex) else { return }
        context.draw(formula, at: .zero, anchor: .topLeading)
      } symbols: {
        NaturalWidthWhenItFits {
          Math(latex)
            .mathFont(DisplayMathRendering.font(size: fontSize))
            .mathTypesettingStyle(.display)
            // Explicit LaTeX colors take precedence; ordinary formulas keep the surrounding style.
            .mathRenderingMode(latex.contains("\\color") || latex.contains("\\textcolor") ? .multicolor : .monochrome)
        }
        .tag(latex)
      }
    }
  }
}

/// Gives its subview the size of a display formula: its natural size, or the size it has
/// broken into lines when it is wider than the width offered, as ``MathAttachment`` is sized.
private struct DisplayMathSize: Layout {
  let latex: String
  let fontSize: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let naturalMetrics = DisplayMathRendering.metrics(for: latex, fontSize: fontSize) else { return .zero }
    guard let width = proposal.width, naturalMetrics.width > width + MathAttachment.naturalWidthTolerance,
      let fittedMetrics = DisplayMathRendering.metrics(for: latex, fontSize: fontSize, fittingWidth: width)
    else { return CGSize(width: naturalMetrics.width, height: naturalMetrics.ascent + naturalMetrics.descent) }
    return CGSize(width: fittedMetrics.width, height: fittedMetrics.ascent + fittedMetrics.descent)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
  }
}
