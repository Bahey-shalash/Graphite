import CoreGraphics
import CoreText
import Foundation

/// Graphite patch: a formula as filled outlines, one path per color, in a view's coordinates
/// (y down). It walks the display tree as `CGContext.draw(_:foregroundColor:)` does, turning
/// each glyph into its outline and each rule or stroke into the area it covers, so `Math`
/// can show the formula as SwiftUI shapes instead of drawing it into a `Canvas`: a canvas
/// draws through RenderBox, which starts a Metal device that holds about 200 MB while a note
/// scrolls. The outlines are vector, so a formula stays sharp in a PDF.
struct MathOutlines {
  /// A part of the formula drawn in one color; nil is the view's foreground.
  struct Part {
    let color: CGColor?
    let path: CGMutablePath
  }

  private(set) var parts: [Part] = []

  /// The outlines of `displayNode` drawn in a view of `size`, colored by the formula's own
  /// colors when `usesFormulaColors` is true and all in the foreground otherwise.
  init(_ displayNode: Math.DisplayNode, size: CGSize, usesFormulaColors: Bool) {
    // As `GraphicsContext.draw(_:size:foregroundColor:)`: the formula's baseline sits its
    // descent above the bottom, with y up.
    let viewTransform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height - displayNode.descent)
    add(displayNode, transform: viewTransform, color: nil, usesFormulaColors: usesFormulaColors)
  }

  private mutating func add(_ node: Math.DisplayNode, transform: CGAffineTransform, color: CGColor?, usesFormulaColors: Bool) {
    let color = usesFormulaColors ? (node.localTextColor ?? node.textColor ?? color) : nil

    switch node {
    case let list as Math.DisplayList:
      let listTransform = CGAffineTransform(translationX: list.position.x, y: list.position.y).concatenating(transform)
      for child in list.children { add(child, transform: listTransform, color: color, usesFormulaColors: usesFormulaColors) }
    case let textRun as Math.DisplayTextRun:
      addText(textRun, transform: transform, color: color)
    case let glyph as Math.DisplayGlyph:
      guard let platformFont = Math.PlatformFont(font: glyph.font) else { return }
      let glyphTransform = CGAffineTransform(translationX: glyph.position.x, y: glyph.position.y - glyph.shiftDown).concatenating(transform)
      addGlyph(CGGlyph(glyph.glyph), of: platformFont.ctFont, at: .zero, transform: glyphTransform, color: color)
    case let glyphRun as Math.DisplayGlyphRun:
      guard let platformFont = Math.PlatformFont(font: glyphRun.font) else { return }
      let runTransform = CGAffineTransform(translationX: glyphRun.position.x, y: glyphRun.position.y - glyphRun.shiftDown).concatenating(transform)
      for (glyph, offset) in zip(glyphRun.glyphs, glyphRun.offsets) {
        addGlyph(CGGlyph(glyph), of: platformFont.ctFont, at: CGPoint(x: 0, y: offset), transform: runTransform, color: color)
      }
    case let fraction as Math.DisplayFraction:
      if let numerator = fraction.numerator { add(numerator, transform: transform, color: color, usesFormulaColors: usesFormulaColors) }
      if let denominator = fraction.denominator { add(denominator, transform: transform, color: color, usesFormulaColors: usesFormulaColors) }
      guard fraction.lineThickness > 0 else { return }
      let lineY = fraction.position.y + fraction.linePosition
      addRule(from: CGPoint(x: fraction.position.x, y: lineY), to: CGPoint(x: fraction.position.x + fraction.width, y: lineY),
              thickness: fraction.lineThickness, cap: .butt, transform: transform, color: color)
    case let radical as Math.DisplayRadical:
      if let radicand = radical.radicand { add(radicand, transform: transform, color: color, usesFormulaColors: usesFormulaColors) }
      if let degree = radical.degree { add(degree, transform: transform, color: color, usesFormulaColors: usesFormulaColors) }
      let radicalTransform = CGAffineTransform(translationX: radical.position.x + radical.radicalShift, y: radical.position.y).concatenating(transform)
      if let radicalGlyph = radical.radicalGlyph { add(radicalGlyph, transform: radicalTransform, color: color, usesFormulaColors: usesFormulaColors) }
      let lineStart = CGPoint(x: radical.radicalGlyph?.width ?? 0, y: radical.ascent - radical.topKern - radical.lineThickness / 2)
      addRule(from: lineStart, to: CGPoint(x: lineStart.x + (radical.radicand?.width ?? 0), y: lineStart.y),
              thickness: radical.lineThickness, cap: .round, transform: radicalTransform, color: color)
    case let line as Math.DisplayLine:
      if let inner = line.inner { add(inner, transform: transform, color: color, usesFormulaColors: usesFormulaColors) }
      let lineStart = CGPoint(x: line.position.x, y: line.position.y + line.lineShiftUp)
      addRule(from: lineStart, to: CGPoint(x: lineStart.x + (line.inner?.width ?? 0), y: lineStart.y),
              thickness: line.lineThickness, cap: .butt, transform: transform, color: color)
    case let brace as Math.DisplayHorizontalBrace:
      let braceTransform = CGAffineTransform(translationX: brace.position.x, y: brace.position.y).concatenating(transform)
      let outline = brace.centerLine.copy(strokingWithWidth: brace.thickness, lineCap: .round, lineJoin: .round, miterLimit: 10)
      path(for: color).addPath(outline, transform: braceTransform)
    case let largeOperator as Math.DisplayLargeOperator:
      if let upperLimit = largeOperator.upperLimit { add(upperLimit, transform: transform, color: color, usesFormulaColors: usesFormulaColors) }
      if let lowerLimit = largeOperator.lowerLimit { add(lowerLimit, transform: transform, color: color, usesFormulaColors: usesFormulaColors) }
      if let nucleus = largeOperator.nucleus { add(nucleus, transform: transform, color: color, usesFormulaColors: usesFormulaColors) }
    case let accent as Math.DisplayAccent:
      if let accentee = accent.accentee { add(accentee, transform: transform, color: color, usesFormulaColors: usesFormulaColors) }
      guard let accentGlyph = accent.accent else { return }
      let accentTransform = CGAffineTransform(translationX: accent.position.x, y: accent.position.y).concatenating(transform)
      add(accentGlyph, transform: accentTransform, color: color, usesFormulaColors: usesFormulaColors)
    default:
      break
    }
  }

  /// A text run's glyphs, laid out by Core Text as `CTLineDraw` draws them.
  private mutating func addText(_ textRun: Math.DisplayTextRun, transform: CGAffineTransform, color: CGColor?) {
    let line = CTLineCreateWithAttributedString(textRun.attributedString)
    let lineTransform = CGAffineTransform(translationX: textRun.position.x, y: textRun.position.y).concatenating(transform)
    for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
      let attributes = CTRunGetAttributes(run) as NSDictionary
      guard let fontValue = attributes[kCTFontAttributeName], CFGetTypeID(fontValue as CFTypeRef) == CTFontGetTypeID() else { continue }
      let font = fontValue as! CTFont
      let glyphCount = CTRunGetGlyphCount(run)
      var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
      var positions = [CGPoint](repeating: .zero, count: glyphCount)
      CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
      CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
      for (glyph, position) in zip(glyphs, positions) {
        addGlyph(glyph, of: font, at: position, transform: lineTransform, color: color)
      }
    }
  }

  private mutating func addGlyph(_ glyph: CGGlyph, of font: CTFont, at position: CGPoint, transform: CGAffineTransform, color: CGColor?) {
    guard let outline = CTFontCreatePathForGlyph(font, glyph, nil) else { return }
    path(for: color).addPath(outline, transform: CGAffineTransform(translationX: position.x, y: position.y).concatenating(transform))
  }

  /// The area a stroked line covers, as the drawing strokes it.
  private mutating func addRule(from start: CGPoint, to end: CGPoint, thickness: CGFloat, cap: CGLineCap, transform: CGAffineTransform, color: CGColor?) {
    let line = CGMutablePath()
    line.move(to: start)
    line.addLine(to: end)
    path(for: color).addPath(line.copy(strokingWithWidth: thickness, lineCap: cap, lineJoin: .miter, miterLimit: 10), transform: transform)
  }

  private mutating func path(for color: CGColor?) -> CGMutablePath {
    if let index = parts.firstIndex(where: { part in
      switch (part.color, color) {
      case (nil, nil): true
      case let (partColor?, color?): partColor == color
      default: false
      }
    }) {
      return parts[index].path
    }
    let part = Part(color: color, path: CGMutablePath())
    parts.append(part)
    return part.path
  }
}
