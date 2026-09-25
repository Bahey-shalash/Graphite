import SwiftUI
@_spi(Textual) private import SwiftUIMath

struct MathAttachment: Attachment {
  enum DisplayStyle: Sendable {
    case inline
    case block
  }

  var description: String {
    switch displayStyle {
    case .inline:
      return "$\(latex)$"
    case .block:
      return "$$\(latex)$$"
    }
  }

  var selectionStyle: AttachmentSelectionStyle {
    .text
  }

  let latex: String
  let displayStyle: DisplayStyle

  init(latex: String, style: DisplayStyle) {
    self.latex = latex
    self.displayStyle = style
  }

  /// Graphite patch: whether the typesetter can parse `latex`; it measures zero otherwise.
  static func canTypeset(_ latex: String) -> Bool {
    Math.typographicBounds(for: latex, fitting: .unspecified, font: .init(name: .latinModern, size: 12), style: .display).width > 0
  }

  var body: some View {
    MathView(latex: latex, style: displayStyle)
  }

  func baselineOffset(in environment: TextEnvironmentValues) -> CGFloat {
    -typographicBounds(in: environment).descent
  }

  func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
    // Graphite patch: math keeps its natural width. Fitting it to a narrow proposal (as
    // table cells make while measuring) broke `$k_n$` onto two lines. Display math is
    // fitted to the proposal only when it is wider than it by more than the tolerance
    // `MathView` draws with, so the reserved size is the size that is drawn.
    let naturalBounds = typographicBounds(in: environment)
    guard displayStyle == .block,
      let width = proposal.width,
      naturalBounds.width > width + Self.naturalWidthTolerance
    else { return naturalBounds.size }
    return typographicBounds(fitting: proposal, in: environment).size
  }

  /// Graphite patch: how far, in points, display math may overhang its column and still
  /// be measured and drawn on one line at its natural width. Rounded frames are a
  /// fraction of a point narrower than the formula they were measured for.
  static let naturalWidthTolerance: CGFloat = 1

  private func typographicBounds(
    fitting proposal: ProposedViewSize = .unspecified,
    in environment: TextEnvironmentValues
  ) -> Math.TypographicBounds {
    Math.typographicBounds(
      for: latex,
      fitting: proposal,
      font: .init(
        name: .init(environment.mathProperties.fontName),
        size: FontScaled(environment.mathProperties.fontScale).resolve(in: environment)
      ),
      style: .init(displayStyle)
    )
  }
}

private struct MathView: View {
  @Environment(\.textEnvironment) private var environment

  let latex: String
  let style: MathAttachment.DisplayStyle

  var body: some View {
    let math = Math(latex)
      .mathFont(
        .init(
          name: .init(environment.mathProperties.fontName),
          size: FontScaled(environment.mathProperties.fontScale).resolve(in: environment)
        )
      )
      .mathTypesettingStyle(.init(style))
      .mathRenderingMode(.monochrome)
    // Graphite patch: math is drawn at its natural size. A frame a fraction of a point
    // narrower than the formula (the attachment's measured width, rounded) made it
    // line-break mid-formula, e.g. `E = mc^2` with the exponent on a second line.
    // Display math still wraps when it is genuinely wider than the text column.
    switch style {
    case .inline:
      math.fixedSize(horizontal: true, vertical: false)
    case .block:
      NaturalWidthWhenItFits { math }
    }
  }
}

/// Graphite patch: proposes a subview its natural width when that fits the space it is
/// given (within `MathAttachment.naturalWidthTolerance`), and the given size otherwise.
private struct NaturalWidthWhenItFits: Layout {
  private static let tolerance = MathAttachment.naturalWidthTolerance

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let subview = subviews.first else { return .zero }
    let naturalSize = subview.sizeThatFits(.unspecified)
    if let width = proposal.width, naturalSize.width > width + Self.tolerance {
      return subview.sizeThatFits(proposal)
    }
    return naturalSize
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    guard let subview = subviews.first else { return }
    let naturalSize = subview.sizeThatFits(.unspecified)
    let fits = naturalSize.width <= bounds.width + Self.tolerance
    subview.place(at: bounds.origin, proposal: fits ? .unspecified : ProposedViewSize(bounds.size))
  }
}

extension Math.Font.Name {
  fileprivate init(_ fontName: MathProperties.FontName) {
    self.init(rawValue: fontName.rawValue)
  }
}

extension Math.TypesettingStyle {
  fileprivate init(_ style: MathAttachment.DisplayStyle) {
    switch style {
    case .inline:
      self = .text
    case .block:
      self = .display
    }
  }
}
