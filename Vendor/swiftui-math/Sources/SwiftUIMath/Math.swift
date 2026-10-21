import SwiftUI

/// Renders a LaTeX math expression using SwiftUI.
///
/// You can create a view with a LaTeX string; this is a good default for short expressions:
///
/// ```swift
/// Math("x^2 + y^2 = z^2")
/// ```
///
/// If you need inline vs display behavior, set the typesetting style:
///
/// ```swift
/// Math("\\int_0^1 x^2\\,dx = \\frac{1}{3}")
///   .mathTypesettingStyle(.text)
///
/// Math("\\frac{1}{2}+\\sqrt{2}")
///   .mathTypesettingStyle(.display)
/// ```
///
/// To customize the appearance, choose a bundled math font and size:
///
/// ```swift
/// Math("\\sum_{i=1}^{n}x_i")
///   .mathFont(Math.Font(name: .latinModern, size: 24))
/// ```
///
/// For multicolor expressions, enable multicolor mode and use hex colors:
///
/// ```swift
/// Math("\\color{#cc0000}{a}+\\color{#00aa00}{b}+\\color{#0000cc}{c}")
///   .mathRenderingMode(.multicolor)
/// ```
public struct Math: View {
  @Environment(\.mathFont) private var font
  @Environment(\.mathTypesettingStyle) private var typesettingStyle
  @Environment(\.mathRenderingMode) private var renderingMode

  private let latex: String

  /// Creates a math view that renders the given LaTeX string.
  /// - Parameter latex: A LaTeX math expression.
  public init(_ latex: String) {
    self.latex = latex
  }

  public var body: some View {
    Layout(latex: latex, font: font, style: typesettingStyle) {
      // Graphite patch: the formula's outlines as shapes, not a `Canvas` (see `MathOutlines`).
      GeometryReader { geometry in
        if let displayNode = DisplayProvider.shared.display(
          for: latex,
          font: font,
          style: typesettingStyle,
          proposedWidth: geometry.size.width
        ) {
          switch renderingMode {
          case .monochrome:
            // One shape, filled with the foreground style, which may be a gradient.
            let outlines = MathOutlines(displayNode, size: geometry.size, usesFormulaColors: false)
            ForEach(outlines.parts.indices, id: \.self) { index in
              OutlineShape(path: outlines.parts[index].path, style: .foreground, thickening: font.size * Self.glyphThickening)
            }
          case .multicolor(let base):
            // The formula's own colors, and the base color where it sets none.
            let outlines = MathOutlines(displayNode, size: geometry.size, usesFormulaColors: true)
            ForEach(outlines.parts.indices, id: \.self) { index in
              OutlineShape(
                path: outlines.parts[index].path,
                style: outlines.parts[index].color.map { color in SwiftUI.Color(cgColor: color) } ?? base,
                thickening: font.size * Self.glyphThickening
              )
            }
          }
        }
      }
    }
  }
}

extension Math {
  /// Graphite patch: on the Mac, Core Text thickens glyphs slightly as it draws them (font
  /// smoothing), which a filled outline does not get; the outline is stroked by this share of
  /// the font size so a formula looks as it did when its glyphs were drawn (measured against
  /// Core Text's drawing on a dark background, 2026-10-21). iOS draws glyphs without it.
  #if os(macOS)
    static let glyphThickening: CGFloat = 0.014
  #else
    static let glyphThickening: CGFloat = 0
  #endif

  /// One color's outlines: filled, and stroked by `thickening` around their edge.
  private struct OutlineShape<Style: ShapeStyle>: View {
    let path: CGPath
    let style: Style
    let thickening: CGFloat

    var body: some View {
      Path(path).fill(style)
        .overlay {
          if thickening > 0 { Path(path).stroke(style, lineWidth: thickening) }
        }
    }
  }
}

extension Math {
  @_spi(Textual)
  public struct TypographicBounds: Sendable {
    @_spi(Textual)
    public var origin: CGPoint

    @_spi(Textual)
    public var width: CGFloat

    @_spi(Textual)
    public var ascent: CGFloat

    @_spi(Textual)
    public var descent: CGFloat

    @_spi(Textual)
    public var size: CGSize {
      .init(width: self.width, height: self.ascent + self.descent)
    }

    static let zero = TypographicBounds(origin: .zero, width: 0, ascent: 0, descent: 0)
  }

  @_spi(Textual)
  public static nonisolated func typographicBounds(
    for latex: String,
    fitting proposal: ProposedViewSize,
    font: Font,
    style: TypesettingStyle
  ) -> TypographicBounds {
    if let width = proposal.width, width <= 0 {
      return .zero
    }

    return DisplayProvider.shared
      .display(
        for: latex,
        font: font,
        style: style,
        proposedWidth: proposal.width ?? 0
      )
      .map {
        TypographicBounds(
          origin: $0.position,
          width: $0.width,
          ascent: $0.ascent,
          descent: $0.descent
        )
      } ?? .zero
  }
}

extension Math {
  private struct Layout: SwiftUI.Layout {
    let latex: String
    let font: Font
    let style: TypesettingStyle

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
      if let width = proposal.width, width <= 0 {
        return .zero
      }

      return DisplayProvider.shared.sizeThatFits(
        proposedWidth: proposal.width ?? 0,
        latex: latex,
        font: font,
        style: style
      )
    }

    func placeSubviews(
      in bounds: CGRect,
      proposal: ProposedViewSize,
      subviews: Subviews,
      cache: inout ()
    ) {
      if let view = subviews.first {
        view.place(at: bounds.origin, proposal: .init(bounds.size))
      }
    }
  }
}

#Preview("Display Style") {
  Math("\\frac{1}{2}+\\sqrt{2}+\\sum_{i=1}^{n}x_i")
    .mathFont(Math.Font(name: .latinModern, size: 24))
    .foregroundStyle(
      .linearGradient(
        colors: [.red, .blue],
        startPoint: .top,
        endPoint: .bottom
      )
    )
    .padding()
}

#Preview("Text Style") {
  Math("\\int_0^1 x^2\\,dx = \\frac{1}{3}")
    .mathTypesettingStyle(.text)
    .mathFont(Math.Font(name: .libertinus, size: 20))
    .padding()
}

#Preview("Large Operators") {
  Math("\\lim_{n\\to\\infty}\\sum_{k=1}^{n}\\frac{1}{k^2}=\\frac{\\pi^2}{6}")
    .mathTypesettingStyle(.display)
    .mathFont(Math.Font(name: .xits, size: 22))
    .padding()
}

#Preview("Matrix") {
  Math("A=\\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}")
    .mathTypesettingStyle(.display)
    .mathFont(Math.Font(name: .asana, size: 22))
    .padding()
}

#Preview("Cases") {
  Math("\\begin{cases} x + y = 5 \\\\ 2x - y = 1 \\end{cases}")
    .mathTypesettingStyle(.display)
    .mathFont(Math.Font(name: .termes, size: 22))
    .padding()
}

#Preview("Accents And Scripts") {
  Math("\\hat{x}+\\bar{y}+\\vec{z}+a_{i}^{2}")
    .mathTypesettingStyle(.text)
    .mathFont(Math.Font(name: .euler, size: 22))
    .padding()
}

#Preview("Multicolor") {
  Math("\\color{#cc0000}{a}+\\color{#00aa00}{b}+\\color{#0000cc}{c}")
    .mathTypesettingStyle(.text)
    .mathRenderingMode(.multicolor)
    .mathFont(Math.Font(name: .latinModern, size: 22))
    .padding()
}

#Preview("Multicolor 2") {
  Math("\\textcolor{#ff8800}{\\int_0^1 x^2\\,dx}=\\textcolor{#0088ff}{\\frac{1}{3}}")
    .mathRenderingMode(.multicolor)
    .mathFont(Math.Font(name: .libertinus, size: 20))
    .padding()
}
