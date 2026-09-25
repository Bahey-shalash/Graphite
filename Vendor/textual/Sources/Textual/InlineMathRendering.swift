import SwiftUI
@_spi(Textual) private import SwiftUIMath

/// Graphite addition: measures and draws inline math for text views outside SwiftUI (an
/// editor that places formulas among its own glyphs). Uses the same font and typesetting
/// as inline math in ``StructuredText``.
public enum InlineMathRendering {
  /// The size of a typeset formula. The baseline is `ascent` below its top.
  public struct Metrics: Hashable, Sendable {
    public let width: CGFloat
    public let ascent: CGFloat
    public let descent: CGFloat
  }

  /// The formula's size, or nil when the LaTeX cannot be typeset.
  public static func metrics(for latex: String, fontSize: CGFloat) -> Metrics? {
    let bounds = Math.typographicBounds(for: latex, fitting: .unspecified, font: font(size: fontSize), style: .text)
    guard bounds.width > 0 else { return nil }
    return Metrics(width: bounds.width, ascent: bounds.ascent, descent: bounds.descent)
  }

  /// The formula drawn in `color`, `ascent + descent` points tall.
  @MainActor
  public static func image(for latex: String, fontSize: CGFloat, color: Color, scale: CGFloat) -> CGImage? {
    let renderer = ImageRenderer(
      content: Math(latex)
        .mathFont(font(size: fontSize))
        .mathTypesettingStyle(.text)
        .mathRenderingMode(.monochrome)
        .foregroundStyle(color)
        .fixedSize()
    )
    renderer.scale = scale
    return renderer.cgImage
  }

  private static func font(size: CGFloat) -> Math.Font {
    Math.Font(name: .latinModern, size: size)
  }
}
