import CoreGraphics

/// Draws a laid-out Sankey diagram into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down (a flipped bitmap, a PDF page), from its `SankeyDrawingParts`, back to front. Nothing is parsed or measured
/// here, so drawing again in other colors is cheap.
public enum SankeyRenderer {
    public static func draw(_ layout: SankeyLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = SankeyDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        for band in parts.bands {
            fill(band, from: palette.seriesColor(at: band.sourceSeriesIndex), to: palette.seriesColor(at: band.targetSeriesIndex), in: context)
        }
        for (index, nodeFill) in parts.nodeFills.enumerated() where !nodeFill.isEmpty {
            context.setFillColor(palette.seriesColor(at: index))
            context.addPath(nodeFill)
            context.fillPath()
        }
        for name in parts.names { text.draw(name, color: palette.foreground, in: context) }
        for value in parts.values { text.draw(value, color: palette.muted, in: context) }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
    }

    /// The band filled with its gradient at `SankeyDrawingParts.bandOpacity`, the colors carried on past its ends.
    private static func fill(_ band: SankeyBandDrawing, from sourceColor: CGColor, to targetColor: CGColor, in context: CGContext) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space, colors: [sourceColor, targetColor] as CFArray, locations: [0, 1]) else { return }
        context.saveGState()
        context.addPath(band.outline)
        context.clip()
        context.setAlpha(SankeyDrawingParts.bandOpacity)
        context.drawLinearGradient(gradient, start: CGPoint(x: band.startX, y: 0), end: CGPoint(x: band.endX, y: 0),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }
}
