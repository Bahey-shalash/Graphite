import CoreGraphics

/// Draws a laid-out pie chart into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down (a flipped bitmap, a PDF page), from its `PieChartDrawingParts`, back to front. Nothing is parsed or measured
/// here, so drawing again in other colors is cheap.
public enum PieChartRenderer {
    public static func draw(_ layout: PieChartLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = PieChartDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        context.saveGState()
        context.setLineJoin(.round)
        for (index, seriesFill) in parts.seriesFills.enumerated() { fill(seriesFill, color: palette.seriesColor(at: index), in: context) }
        stroke(parts.sliceEdges, color: palette.background, in: context)
        stroke(parts.emptyPieOutline, color: palette.border, in: context)
        for percentage in parts.insidePercentages { text.draw(percentage, color: palette.background, in: context) }
        for block in parts.outsidePercentages + parts.legendTexts { text.draw(block, color: palette.foreground, in: context) }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
        context.restoreGState()
    }

    private static func stroke(_ path: CGPath, color: CGColor, in context: CGContext) {
        guard !path.isEmpty else { return }
        context.setStrokeColor(color)
        context.setLineWidth(PieChartDrawingParts.lineWidth)
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
