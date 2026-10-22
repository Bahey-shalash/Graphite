import CoreGraphics
import CoreText
import Foundation

/// Draws a laid-out class diagram into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down (a flipped bitmap, a PDF page), from its `ClassDiagramDrawingParts`, back to front. Nothing is parsed or
/// measured here, so drawing again in other colors is cheap.
public enum ClassDiagramRenderer {
    public static func draw(_ layout: ClassDiagramLayout, in context: CGContext, palette: ClassDiagramPalette) {
        let parts = ClassDiagramDrawingParts(layout: layout)
        let colors = palette.diagram
        var text = DiagramTextDrawing(font: layout.font)
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        stroke(parts.solidLines, color: colors.line, in: context)
        stroke(parts.dashedLines, color: colors.line, dash: ClassDiagramDrawingParts.dashedDashLengths, in: context)
        stroke(parts.dottedLines, color: colors.line, dash: ClassDiagramDrawingParts.dottedDashLengths, in: context)
        fill(parts.filledMarks, color: colors.line, in: context)
        stroke(parts.strokedMarks, color: colors.line, in: context)
        fill(parts.edgeTextPatches, color: colors.background, in: context)
        for block in parts.edgeTexts { text.draw(block, color: colors.foreground, in: context) }
        for block in parts.cardinalities { text.draw(block, color: palette.muted, in: context) }
        fill(parts.classFills, color: colors.surface, in: context)
        fill(parts.noteFills, color: palette.noteSurface, in: context)
        stroke(parts.outlines, color: colors.border, in: context)
        for block in parts.annotations { text.draw(block, color: palette.muted, in: context) }
        for block in parts.names { text.draw(block, color: colors.foreground, isBold: true, in: context) }
        drawMembers(parts.members, font: layout.font, color: colors.foreground, text: &text, in: context)
        stroke(parts.memberUnderlines, color: colors.foreground, in: context)
        for block in parts.noteTexts { text.draw(block, color: colors.foreground, in: context) }
        if let title = parts.title { text.draw(title, color: colors.foreground, isBold: true, in: context) }
        context.restoreGState()
    }

    /// Each member's line, an abstract one in the italic of its font.
    private static func drawMembers(_ members: [ClassDiagramLayoutMember], font: DiagramFont, color: CGColor, text: inout DiagramTextDrawing,
                                    in context: CGContext) {
        var italicFonts: [CGFloat: CTFont] = [:]
        for member in members {
            switch member.classifier {
            case .plain, .static: text.draw(member.text, color: color, in: context)
            case .abstract:
                let size = member.text.fontSize
                let italic = italicFonts[size] ?? italicFont(font.resized(to: size))
                italicFonts[size] = italic
                drawLine(of: member.text, font: italic, color: color, in: context)
            }
        }
    }

    /// The italic of `font`, or the font itself when it has none.
    private static func italicFont(_ font: DiagramFont) -> CTFont {
        let regular = font.makeCoreTextFont()
        return CTFontCreateCopyWithSymbolicTraits(regular, font.size, nil, .traitItalic, .traitItalic) ?? regular
    }

    /// One line of text centered on its block, in `font`, as `DiagramTextDrawing` places it.
    private static func drawLine(of block: DiagramTextBlock, font: CTFont, color: CGColor, in context: CGContext) {
        guard let line = block.lines.first, let width = block.lineWidths.first else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: color,
        ]
        context.saveGState()
        // Core Text draws glyphs upright in a context whose y runs up; this one's runs down.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: block.center.x - width / 2, y: block.center.y + block.fontSize * DiagramTextDrawing.baselineShiftRatio)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes)), context)
        context.restoreGState()
    }

    private static func stroke(_ path: CGPath, color: CGColor, dash: [CGFloat] = [], in context: CGContext) {
        guard !path.isEmpty else { return }
        context.setStrokeColor(color)
        context.setLineWidth(ClassDiagramDrawingParts.lineWidth)
        context.setLineDash(phase: 0, lengths: dash)
        context.addPath(path)
        context.strokePath()
    }

    private static func fill(_ path: CGPath, color: CGColor, in context: CGContext) {
        guard !path.isEmpty else { return }
        context.setFillColor(color)
        context.addPath(path)
        context.fillPath()
    }
}
