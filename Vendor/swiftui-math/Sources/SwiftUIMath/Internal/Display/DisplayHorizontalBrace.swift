import CoreGraphics
import Foundation

extension Math {
  /// Graphite patch: a horizontal curly brace drawn as a path, as wide as what it spans.
  /// The math fonts' brace glyphs come in a few fixed widths and no assembly, so a brace
  /// under a long expression could not be built from them. Its ink lies between its
  /// baseline (the node's bottom) and `ascent`; its ends point toward what it spans.
  final class DisplayHorizontalBrace: DisplayNode {
    let isOver: Bool
    let thickness: CGFloat

    init(width: CGFloat, height: CGFloat, thickness: CGFloat, isOver: Bool, range: NSRange) {
      self.isOver = isOver
      self.thickness = thickness
      super.init()
      self.width = width
      self.ascent = height
      self.descent = 0
      self.range = range
    }

    /// The brace's center line in the node's coordinates (y up, origin at its bottom
    /// left), to be stroked `thickness` wide: each end curls from the side of what it
    /// spans into a straight run at half height, and the two halves meet in a point at
    /// the middle, on the far side.
    var centerLine: CGPath {
      let inset = thickness / 2
      let height = ascent
      let middleHeight = height / 2
      let endHeight = isOver ? inset : height - inset
      let tipHeight = isOver ? height - inset : inset
      let middle = width / 2
      let curlWidth = max(0, min(middleHeight, (middle - inset) / 2))

      let path = CGMutablePath()
      path.move(to: CGPoint(x: inset, y: endHeight))
      path.addQuadCurve(to: CGPoint(x: inset + curlWidth, y: middleHeight), control: CGPoint(x: inset, y: middleHeight))
      path.addLine(to: CGPoint(x: middle - curlWidth, y: middleHeight))
      path.addQuadCurve(to: CGPoint(x: middle, y: tipHeight), control: CGPoint(x: middle, y: middleHeight))
      path.addQuadCurve(to: CGPoint(x: middle + curlWidth, y: middleHeight), control: CGPoint(x: middle, y: middleHeight))
      path.addLine(to: CGPoint(x: width - inset - curlWidth, y: middleHeight))
      path.addQuadCurve(to: CGPoint(x: width - inset, y: endHeight), control: CGPoint(x: width - inset, y: middleHeight))
      return path
    }
  }
}
