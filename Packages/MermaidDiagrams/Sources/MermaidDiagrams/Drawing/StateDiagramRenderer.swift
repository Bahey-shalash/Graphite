import CoreGraphics

/// Draws a laid-out state diagram into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down (a flipped bitmap, a PDF page), from its `StateDiagramDrawingParts`, back to front. Nothing is parsed or
/// measured here, so drawing again in other colors is cheap.
public enum StateDiagramRenderer {
    public static func draw(_ layout: StateDiagramLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = StateDiagramDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        let lineWidth = StateDiagramDrawingParts.lineWidth
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        stroke(parts.transitionLines, width: lineWidth, color: palette.line, in: context)
        context.setLineDash(phase: 0, lengths: StateDiagramDrawingParts.noteConnectorDashLengths)
        stroke(parts.noteConnectors, width: lineWidth, color: palette.border, in: context)
        context.setLineDash(phase: 0, lengths: [])
        fill(parts.arrows, color: palette.line, in: context)
        fill(parts.transitionTextPatches, color: palette.background, in: context)
        for transitionText in parts.transitionTexts { text.draw(transitionText, color: palette.foreground, in: context) }
        fill(parts.stateFills, color: palette.surface, in: context)
        stroke(parts.stateOutlines, width: lineWidth, color: palette.border, in: context)
        fill(parts.endRings, color: palette.background, in: context)
        stroke(parts.endRings, width: lineWidth, color: palette.line, in: context)
        fill(parts.solidMarks, color: palette.line, in: context)
        for stateText in parts.stateTexts { text.draw(stateText, color: palette.foreground, in: context) }
        fill(parts.noteSheets, color: palette.background, in: context)
        stroke(parts.noteSheets, width: lineWidth, color: palette.border, in: context)
        stroke(parts.noteFolds, width: lineWidth, color: palette.border, in: context)
        for noteText in parts.noteTexts { text.draw(noteText, color: palette.noteText, in: context) }
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

extension DiagramPalette {
    /// How far from the background toward the text a note's text is: Pele's muted gray, #6e6e6e, between its white
    /// page and its #1f1f1f text.
    public static let noteTextShare: CGFloat = 0.65

    /// The color of a note's text: between the background and the text, so that a note reads as an aside.
    public var noteText: CGColor {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let backgroundComponents = background.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components,
              let foregroundComponents = foreground.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components,
              backgroundComponents.count == foregroundComponents.count else { return foreground }
        let mixed = zip(backgroundComponents, foregroundComponents).map { backgroundComponent, foregroundComponent in
            backgroundComponent + (foregroundComponent - backgroundComponent) * Self.noteTextShare
        }
        return CGColor(colorSpace: sRGB, components: mixed) ?? foreground
    }
}
