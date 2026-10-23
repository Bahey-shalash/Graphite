import CoreGraphics

/// Draws a laid-out quadrant chart into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down (a flipped bitmap, a PDF page), from its `QuadrantChartDrawingParts`, back to front, as Pele does: the
/// quadrants in the surface and border colors with their texts, the axes' texts in the muted color (the y axis's turned
/// a quarter anticlockwise), the points in the palette's first series color or the colors the chart writes, their
/// texts, and the bold title. Nothing is parsed or measured here.
public enum QuadrantChartRenderer {
    public static func draw(_ layout: QuadrantChartLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = QuadrantChartDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        context.saveGState()
        context.setFillColor(palette.surface)
        context.addPath(parts.quadrants)
        context.fillPath()
        context.setStrokeColor(palette.border)
        context.setLineWidth(QuadrantChartDrawingParts.lineWidth)
        context.addPath(parts.quadrants)
        context.strokePath()
        for quadrantText in parts.quadrantTexts { text.draw(quadrantText, color: palette.foreground, in: context) }
        for axisText in parts.axisTexts { text.draw(axisText, color: palette.muted, in: context) }
        for turnedText in parts.turnedAxisTexts {
            context.saveGState()
            context.translateBy(x: turnedText.center.x, y: turnedText.center.y)
            context.rotate(by: -.pi / 2)
            var atOrigin = turnedText
            atOrigin.center = .zero
            text.draw(atOrigin, color: palette.muted, in: context)
            context.restoreGState()
        }
        for group in parts.pointGroups { paint(group, palette: palette, in: context) }
        for pointText in parts.pointTexts { text.draw(pointText, color: palette.foreground, in: context) }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
        context.restoreGState()
    }

    /// The color a point's paint stands for in `palette`.
    public static func color(_ paint: QuadrantChartPaint, in palette: DiagramPalette) -> CGColor {
        switch paint {
        case .firstSeries: palette.seriesColor(at: 0)
        case .written(let color):
            CGColor(srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255, alpha: 1)
        }
    }

    private static func paint(_ group: QuadrantChartDrawingParts.PointGroup, palette: DiagramPalette, in context: CGContext) {
        context.setFillColor(color(group.fill, in: palette))
        context.addPath(group.circles)
        context.fillPath()
        guard let stroke = group.stroke else { return }
        context.setStrokeColor(color(stroke.paint, in: palette))
        context.setLineWidth(stroke.width)
        context.addPath(group.circles)
        context.strokePath()
    }
}
