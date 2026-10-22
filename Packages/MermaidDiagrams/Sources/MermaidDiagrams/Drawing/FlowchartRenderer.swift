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
        drawClusters(parts.clusters, text: &text, in: context, palette: palette)
        stroke(parts.solidEdges, width: FlowchartDrawingParts.lineWidth, color: palette.line, in: context)
        stroke(parts.thickEdges, width: FlowchartDrawingParts.thickLineWidth, color: palette.line, in: context)
        context.setLineDash(phase: 0, lengths: FlowchartDrawingParts.dottedDashLengths)
        stroke(parts.dottedEdges, width: FlowchartDrawingParts.lineWidth, color: palette.line, in: context)
        context.setLineDash(phase: 0, lengths: [])
        fill(parts.filledMarks, color: palette.line, in: context)
        stroke(parts.strokedMarks, width: FlowchartDrawingParts.lineWidth, color: palette.line, in: context)
        drawCrossedClusterTitles(parts.clusters, text: &text, in: context, palette: palette)
        fill(parts.edgeTextPatches, color: palette.background, in: context)
        for edgeText in parts.edgeTexts { text.draw(edgeText, color: palette.foreground, in: context) }
        fill(parts.nodeFills, color: palette.surface, in: context)
        stroke(parts.nodeOutlines, width: FlowchartDrawingParts.lineWidth, color: palette.border, in: context)
        for nodeText in parts.nodeTexts { text.draw(nodeText, color: palette.foreground, in: context) }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
        context.restoreGState()
    }

    /// The groups' boxes, behind everything: their fills depth by depth, their outlines and the titles no edge crosses.
    private static func drawClusters(_ clusters: FlowchartClusterDrawingParts, text: inout DiagramTextDrawing, in context: CGContext,
                                     palette: DiagramPalette) {
        let boxFill = clusterFill(palette)
        for depthFill in clusters.fillsByDepth { fill(depthFill, color: boxFill, in: context) }
        stroke(clusters.outlines, width: FlowchartDrawingParts.lineWidth, color: palette.border, in: context)
        for title in clusters.titles { text.draw(title, color: palette.mutedForeground, in: context) }
    }

    /// The titles edges run through, over the edges, each on a patch painted as its box is where it sits.
    private static func drawCrossedClusterTitles(_ clusters: FlowchartClusterDrawingParts, text: inout DiagramTextDrawing, in context: CGContext,
                                                 palette: DiagramPalette) {
        let boxFill = clusterFill(palette)
        for (depth, patches) in clusters.crossedTitlePatchesByDepth.enumerated() where !patches.isEmpty {
            fill(patches, color: palette.background, in: context)
            for _ in 0...depth { fill(patches, color: boxFill, in: context) }
        }
        for title in clusters.crossedTitles { text.draw(title, color: palette.mutedForeground, in: context) }
    }

    private static func clusterFill(_ palette: DiagramPalette) -> CGColor {
        palette.alternateSurface.copy(alpha: palette.alternateSurface.alpha * FlowchartClusterDrawingParts.fillOpacity) ?? palette.alternateSurface
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
