import CoreGraphics

/// Draws a laid-out entity relationship diagram into a Core Graphics context whose origin is the layout's top left and
/// whose y runs down (a flipped bitmap, a PDF page), from its `EntityRelationshipDrawingParts`, back to front. Nothing
/// is parsed or measured here, so drawing again in other colors is cheap. Types, keys and comments are drawn in the
/// text color at `EntityRelationshipDrawingParts.mutedTextOpacity`.
public enum EntityRelationshipRenderer {
    public static func draw(_ layout: EntityRelationshipLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = EntityRelationshipDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        let lineWidth = EntityRelationshipDrawingParts.lineWidth
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        stroke(parts.identifyingLines, width: lineWidth, color: palette.line, in: context)
        context.setLineDash(phase: 0, lengths: EntityRelationshipDrawingParts.nonIdentifyingDashLengths)
        stroke(parts.nonIdentifyingLines, width: lineWidth, color: palette.line, in: context)
        context.setLineDash(phase: 0, lengths: [])
        fill(parts.markFills, color: palette.background, in: context)
        stroke(parts.markOutlines, width: lineWidth, color: palette.line, in: context)
        fill(parts.labelPatches, color: palette.background, in: context)
        for label in parts.labels { text.draw(label, color: palette.foreground, in: context) }
        fill(parts.boxFills, color: palette.surface, in: context)
        fill(parts.rowStripes, color: palette.background, in: context)
        stroke(parts.boxOutlines, width: lineWidth, color: palette.border, in: context)
        for entityText in parts.entityTexts { text.draw(entityText, color: palette.foreground, in: context) }
        let muted = palette.foreground.copy(alpha: palette.foreground.alpha * EntityRelationshipDrawingParts.mutedTextOpacity) ?? palette.foreground
        for detail in parts.attributeDetails { text.draw(detail, color: muted, in: context) }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
        context.restoreGState()
    }

    private static func stroke(_ path: CGPath, width: CGFloat, color: CGColor, in context: CGContext) {
        guard !path.isEmpty else { return }
        context.setStrokeColor(color)
        context.setLineWidth(width)
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
