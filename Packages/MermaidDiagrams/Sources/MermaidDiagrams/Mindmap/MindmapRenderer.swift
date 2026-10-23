import CoreGraphics

/// Draws a laid-out mindmap into a Core Graphics context whose origin is the layout's top left and whose y runs down
/// (a flipped bitmap, a PDF page), from its `MindmapDrawingParts`, back to front. Each branch takes its series color
/// from the palette; the root takes the surface and border. Nothing is parsed or measured here.
public enum MindmapRenderer {
    public static func draw(_ layout: MindmapLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = MindmapDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        context.saveGState()
        for branch in parts.branches {
            let color = palette.seriesColor(at: branch.branchIndex)
            stroke(branch.links, width: MindmapDrawingParts.linkLineWidth, color: color, in: context)
            fill(branch.nodeOutlines, color: color.copy(alpha: color.alpha * MindmapDrawingParts.nodeFillOpacity) ?? color, in: context)
            stroke(branch.nodeOutlines, width: MindmapDrawingParts.outlineLineWidth, color: color, in: context)
        }
        fill(parts.rootOutline, color: palette.surface, in: context)
        stroke(parts.rootOutline, width: MindmapDrawingParts.outlineLineWidth, color: palette.border, in: context)
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
