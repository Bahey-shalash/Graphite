import CoreGraphics

/// Draws a laid-out flowchart into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down (a flipped bitmap, a PDF page), from its `FlowchartDrawingParts`, back to front. Nothing is parsed or
/// measured here, so drawing again in other colors is cheap.
public enum FlowchartRenderer {
    public static func draw(_ layout: FlowchartLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = FlowchartDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        stroke(parts.solidEdges, width: FlowchartDrawingParts.lineWidth, color: palette.line, in: context)
        stroke(parts.thickEdges, width: FlowchartDrawingParts.thickLineWidth, color: palette.line, in: context)
        context.setLineDash(phase: 0, lengths: FlowchartDrawingParts.dottedDashLengths)
        stroke(parts.dottedEdges, width: FlowchartDrawingParts.lineWidth, color: palette.line, in: context)
        context.setLineDash(phase: 0, lengths: [])
        fill(parts.filledMarks, color: palette.line, in: context)
        stroke(parts.strokedMarks, width: FlowchartDrawingParts.lineWidth, color: palette.line, in: context)
        fill(parts.edgeTextPatches, color: palette.background, in: context)
        for edgeText in parts.edgeTexts { text.draw(edgeText, color: palette.foreground, in: context) }
        fill(parts.nodeFills, color: palette.surface, in: context)
        stroke(parts.nodeOutlines, width: FlowchartDrawingParts.lineWidth, color: palette.border, in: context)
        for nodeText in parts.nodeTexts { text.draw(nodeText, color: palette.foreground, in: context) }
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
