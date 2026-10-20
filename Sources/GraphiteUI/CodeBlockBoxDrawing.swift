#if canImport(UIKit)
import UIKit
private typealias DrawingPath = UIBezierPath
#else
import AppKit
private typealias DrawingPath = NSBezierPath
#endif

/// Draws one line's slice of a code block's box: the rounded gray, its thin border, the
/// indentation guides and, on the first line, the language at the right. Each line of a
/// block is its own paragraph, so every slice reaches half a point into the next and the
/// box shows no seam. Called by `ConcealedReplacementLayoutFragment` behind the text.
enum CodeBlockBoxDrawing {
    /// Draws the slice for a paragraph at `point`.
    /// - Parameters:
    ///   - columnWidth: The width of the text column the box reaches across.
    ///   - indentationFromColumn: How far the paragraph's text is indented from the column's
    ///     edge; the box starts that far left of `point`.
    ///   - height: The paragraph's height.
    ///   - firstLine: The paragraph's first line, whose characters the guides sit at.
    static func draw(_ decoration: CodeBlockLineDecoration, at point: CGPoint, columnWidth: CGFloat, indentationFromColumn: CGFloat,
                     height: CGFloat, firstLine: NSTextLineFragment?) {
        // Each slice reaches half a point into the next, so no seam shows between lines.
        let box = CGRect(x: point.x - indentationFromColumn, y: point.y, width: columnWidth + indentationFromColumn,
                         height: height + (decoration.isLastLine ? 0 : 0.5))
        decoration.background.setFill()
        path(box, cornerRadius: decoration.cornerRadius, roundsTop: decoration.isFirstLine, roundsBottom: decoration.isLastLine).fill()
        decoration.border.setStroke()
        let border = borderPath(box.insetBy(dx: 0.5, dy: 0), cornerRadius: decoration.cornerRadius,
                                isFirstLine: decoration.isFirstLine, isLastLine: decoration.isLastLine)
        border.lineWidth = 1
        border.stroke()
        if let firstLine { drawIndentationGuides(of: decoration, at: point, height: height, firstLine: firstLine) }
        if let label = decoration.languageLabel { drawLanguageLabel(label, of: decoration, at: point, columnWidth: columnWidth, height: height) }
    }

    private static func drawIndentationGuides(of decoration: CodeBlockLineDecoration, at point: CGPoint, height: CGFloat, firstLine: NSTextLineFragment) {
        guard !decoration.guideOffsets.isEmpty else { return }
        decoration.guideColor.setFill()
        let lineOriginX = point.x + firstLine.typographicBounds.minX
        for offset in decoration.guideOffsets where offset < firstLine.attributedString.length {
            let guideX = (lineOriginX + firstLine.locationForCharacter(at: offset).x + 1).rounded()
            DrawingPath(rect: CGRect(x: guideX, y: point.y, width: 1, height: height + 0.5)).fill()
        }
    }

    private static func drawLanguageLabel(_ label: String, of decoration: CodeBlockLineDecoration, at point: CGPoint, columnWidth: CGFloat, height: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: decoration.labelFont, .foregroundColor: decoration.labelColor]
        let size = (label as NSString).size(withAttributes: attributes)
        let origin = CGPoint(x: point.x + columnWidth - decoration.horizontalPadding - size.width, y: point.y + max(0, height - size.height) * 0.6)
        (label as NSString).draw(at: origin, withAttributes: attributes)
    }

    /// This slice's part of the box's border: its two sides, and the top with its rounded
    /// corners on the first line, the bottom with its corners on the last. The line is drawn
    /// half a point inside the box, so it stays crisp and within the slice.
    private static func borderPath(_ rect: CGRect, cornerRadius: CGFloat, isFirstLine: Bool, isLastLine: Bool) -> DrawingPath {
        let radius = min(cornerRadius, rect.height / 2, rect.width / 2)
        let top = isFirstLine ? rect.minY + 0.5 : rect.minY
        let bottom = isLastLine ? rect.maxY - 0.5 : rect.maxY
        let path = CGMutablePath()
        // Down the left side, along the bottom on the last line, and up the right side.
        if isFirstLine {
            path.move(to: CGPoint(x: rect.maxX, y: top + radius))
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: top), tangent2End: CGPoint(x: rect.maxX - radius, y: top), radius: radius)
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: top), tangent2End: CGPoint(x: rect.minX, y: top + radius), radius: radius)
        } else {
            path.move(to: CGPoint(x: rect.minX, y: top))
        }
        if isLastLine {
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: bottom), tangent2End: CGPoint(x: rect.minX + radius, y: bottom), radius: radius)
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: bottom), tangent2End: CGPoint(x: rect.maxX, y: bottom - radius), radius: radius)
            path.addLine(to: CGPoint(x: rect.maxX, y: isFirstLine ? top + radius : top))
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: bottom))
            path.move(to: CGPoint(x: rect.maxX, y: bottom))
            path.addLine(to: CGPoint(x: rect.maxX, y: isFirstLine ? top + radius : top))
        }
        return DrawingPath(cgPath: path)
    }

    /// `rect` with its top corners, its bottom corners, both or neither rounded.
    private static func path(_ rect: CGRect, cornerRadius: CGFloat, roundsTop: Bool, roundsBottom: Bool) -> DrawingPath {
        let topRadius = roundsTop ? min(cornerRadius, rect.height / 2, rect.width / 2) : 0
        let bottomRadius = roundsBottom ? min(cornerRadius, rect.height / 2, rect.width / 2) : 0
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + topRadius, y: rect.minY), radius: topRadius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRadius), radius: topRadius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY), radius: bottomRadius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius), radius: bottomRadius)
        path.closeSubpath()
        return DrawingPath(cgPath: path)
    }
}
