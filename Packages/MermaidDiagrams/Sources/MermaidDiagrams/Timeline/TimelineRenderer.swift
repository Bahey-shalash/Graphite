import CoreGraphics

/// Draws a laid-out timeline into a Core Graphics context whose origin is the layout's top left and whose y runs down
/// (a flipped bitmap, a PDF page), from its `TimelineDrawingParts`, back to front, as Pele does: the axis in the line
/// color, the lines to the events in the border color, the boxes and dots in their series or muted colors, the text
/// on the boxes in the background color, the events' text and the title in the foreground color.
public enum TimelineRenderer {
    public static func draw(_ layout: TimelineLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = TimelineDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        context.saveGState()
        stroke(parts.axis, width: TimelineDrawingParts.lineWidth, color: palette.line, in: context)
        fill(parts.axisArrow, color: palette.line, in: context)
        stroke(parts.connectors, width: TimelineDrawingParts.lineWidth, color: palette.border, in: context)
        for group in parts.colorGroups {
            let color = Self.color(group.color, in: palette)
            fill(group.boxes, color: color, in: context)
            fill(group.eventBoxes, color: color.copy(alpha: color.alpha * TimelineDrawingParts.eventFillOpacity) ?? color, in: context)
            fill(group.dots, color: color, in: context)
            stroke(group.dots, width: TimelineDrawingParts.dotOutlineWidth, color: palette.background, in: context)
        }
        for sectionText in parts.sectionTexts { text.draw(sectionText, color: palette.background, isBold: true, in: context) }
        for periodText in parts.periodTexts { text.draw(periodText, color: palette.background, in: context) }
        for eventText in parts.eventTexts { text.draw(eventText, color: palette.foreground, in: context) }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
        context.restoreGState()
    }

    static func color(_ color: TimelineColor, in palette: DiagramPalette) -> CGColor {
        switch color {
        case .series(let index): palette.seriesColor(at: index)
        case .muted: palette.muted
        }
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
