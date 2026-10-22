import CoreGraphics

/// Draws a laid-out sequence diagram into a Core Graphics context whose origin is the layout's top left and whose y
/// runs down (a flipped bitmap, a PDF page), from its `SequenceDrawingParts`, back to front. Nothing is parsed or
/// measured here, so drawing again in other colors is cheap.
public enum SequenceRenderer {
    public static func draw(_ layout: SequenceLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = SequenceDrawingParts(layout: layout)
        let muted = mixed(palette.background, palette.foreground, share: SequenceDrawingParts.mutedShare)
        let surfaceAlternate = mixed(palette.background, palette.foreground, share: SequenceDrawingParts.surfaceAlternateShare)
        var text = DiagramTextDrawing(font: layout.font)
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for highlight in parts.highlights {
            let color = highlight.color.map { color in CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha) }
                ?? surfaceAlternate.copy(alpha: SequenceDrawingParts.defaultHighlightOpacity) ?? surfaceAlternate
            fill(highlight.path, color: color, in: context)
        }
        stroke(parts.lifelines, color: palette.border, in: context)
        for activation in parts.activations {
            fill(activation, color: palette.surface, in: context)
            stroke(activation, color: palette.border, in: context)
        }
        drawBlocks(parts, palette: palette, muted: muted, text: &text, in: context)
        stroke(parts.solidMessageLines, color: palette.line, in: context)
        context.setLineDash(phase: 0, lengths: SequenceDrawingParts.dashLengths)
        stroke(parts.dottedMessageLines, color: palette.line, in: context)
        context.setLineDash(phase: 0, lengths: [])
        fill(parts.filledHeads, color: palette.line, in: context)
        stroke(parts.strokedHeads, color: palette.line, in: context)
        fill(parts.numberBadges, color: palette.line, in: context)
        for number in parts.numberTexts { text.draw(number, color: palette.background, in: context) }
        fill(parts.messageTextPatches, color: palette.background, in: context)
        for messageText in parts.messageTexts { text.draw(messageText, color: palette.foreground, in: context) }
        fill(parts.notes, color: surfaceAlternate, in: context)
        stroke(parts.notes, color: palette.border, in: context)
        for noteText in parts.noteTexts { text.draw(noteText, color: palette.foreground, in: context) }
        fill(parts.participantShapes, color: palette.surface, in: context)
        stroke(parts.participantShapes, color: palette.border, in: context)
        stroke(parts.participantFigureLines, color: palette.border, in: context)
        for participantText in parts.participantTexts { text.draw(participantText, color: palette.foreground, in: context) }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
        context.restoreGState()
    }

    /// The frames, their dashed section lines, the texts in them on their patches, and the tabs with their keywords.
    private static func drawBlocks(_ parts: SequenceDrawingParts, palette: DiagramPalette, muted: CGColor, text: inout DiagramTextDrawing,
                                   in context: CGContext) {
        stroke(parts.blockOutlines, color: palette.border, in: context)
        context.setLineDash(phase: 0, lengths: SequenceDrawingParts.dashLengths)
        stroke(parts.blockSectionLines, color: palette.border, in: context)
        context.setLineDash(phase: 0, lengths: [])
        fill(parts.blockTextPatches, color: palette.background, in: context)
        for blockText in parts.blockTexts { text.draw(blockText, color: muted, in: context) }
        fill(parts.blockTabs, color: palette.surface, in: context)
        stroke(parts.blockTabs, color: palette.border, in: context)
        for keyword in parts.blockKeywords { text.draw(keyword, color: muted, isBold: true, in: context) }
    }

    /// The color `share` of the way from `start` to `end`, in sRGB.
    static func mixed(_ start: CGColor, _ end: CGColor, share: CGFloat) -> CGColor {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let startComponents = start.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              let endComponents = end.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              startComponents.count == 4, endComponents.count == 4 else { return end }
        let components = zip(startComponents, endComponents).map { from, to in from + (to - from) * share }
        return CGColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: components[3])
    }

    private static func stroke(_ path: CGPath, color: CGColor, in context: CGContext) {
        guard !path.isEmpty else { return }
        context.setStrokeColor(color)
        context.setLineWidth(SequenceDrawingParts.lineWidth)
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
