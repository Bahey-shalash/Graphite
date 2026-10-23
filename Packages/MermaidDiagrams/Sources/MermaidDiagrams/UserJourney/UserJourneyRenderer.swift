import CoreGraphics

/// Draws a laid-out user journey into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down (a flipped bitmap, a PDF page), from its `UserJourneyDrawingParts`, back to front, as Pele does: the scale in
/// the second surface with its numbers muted, the stems in the border color, the line and the faces in the line
/// color on the background, the bands in the second surface, the cards in the surface and border colors, the actors'
/// dots in their series colors, and the text in the foreground color. Nothing is parsed or measured here.
public enum UserJourneyRenderer {
    public static func draw(_ layout: UserJourneyLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = UserJourneyDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        context.saveGState()
        context.setLineWidth(UserJourneyDrawingParts.lineWidth)
        stroke(parts.scaleLines, color: palette.alternateSurface, in: context)
        for scaleText in parts.scaleTexts { text.draw(scaleText, color: palette.muted, in: context) }
        context.saveGState()
        context.setLineDash(phase: 0, lengths: UserJourneyDrawingParts.stemDashLengths)
        stroke(parts.stems, color: palette.border, in: context)
        context.restoreGState()
        context.setLineJoin(.round)
        stroke(parts.scoreLine, color: palette.line, in: context)
        fill(parts.faces, color: palette.background, in: context)
        stroke(parts.faces, color: palette.line, in: context)
        fill(parts.eyes, color: palette.line, in: context)
        context.setLineCap(.round)
        stroke(parts.mouths, color: palette.line, in: context)
        context.setLineCap(.butt)
        fill(parts.sectionBands, color: palette.alternateSurface, in: context)
        for sectionText in parts.sectionTexts { text.draw(sectionText, color: palette.foreground, isBold: true, in: context) }
        fill(parts.cards, color: palette.surface, in: context)
        stroke(parts.cards, color: palette.border, in: context)
        for taskText in parts.taskTexts { text.draw(taskText, color: palette.foreground, in: context) }
        for (index, dots) in parts.cardDotsBySeries.enumerated() {
            fill(dots, color: palette.seriesColor(at: index), in: context)
            stroke(dots, color: palette.surface, in: context)
        }
        for (index, dots) in parts.legendDotsBySeries.enumerated() { fill(dots, color: palette.seriesColor(at: index), in: context) }
        for legendText in parts.legendTexts { text.draw(legendText, color: palette.foreground, in: context) }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
        context.restoreGState()
    }

    private static func stroke(_ path: CGPath, color: CGColor, in context: CGContext) {
        guard !path.isEmpty else { return }
        context.setStrokeColor(color)
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
