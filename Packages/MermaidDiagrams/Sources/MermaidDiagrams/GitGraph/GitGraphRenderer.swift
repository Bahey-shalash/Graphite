import CoreGraphics

/// Draws a laid-out Git graph into a Core Graphics context whose origin is the layout's top left and whose y runs down
/// (a flipped bitmap, a PDF page), from its `GitGraphDrawingParts`, back to front, as Pele does: lanes, names' boxes,
/// lines and symbols in the lanes' series colors, marks and patches and names in the background color, ids in the
/// muted color, tags in the surface and border colors with their text and the title in the foreground color.
public enum GitGraphRenderer {
    public static func draw(_ layout: GitGraphLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = GitGraphDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        context.saveGState()
        drawLanes(parts, in: context, palette: palette)
        for name in parts.names { text.draw(name, color: palette.background, in: context) }
        drawConnectors(parts, in: context, palette: palette)
        drawSymbols(parts, in: context, palette: palette)
        fill(parts.labelPatches, color: palette.background, in: context)
        for label in parts.labels { drawTurned(label, with: &text, color: palette.muted, in: context) }
        fill(parts.tagBoxes, color: palette.surface, in: context)
        context.setLineJoin(.round)
        stroke(parts.tagBoxes, width: GitGraphDrawingParts.tagLineWidth, color: palette.border, in: context)
        fill(parts.tagHoles, color: palette.border, in: context)
        for tagText in parts.tagTexts { text.draw(tagText, color: palette.foreground, in: context) }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
        context.restoreGState()
    }

    private static func drawLanes(_ parts: GitGraphDrawingParts, in context: CGContext, palette: DiagramPalette) {
        for group in parts.colorGroups {
            let color = palette.seriesColor(at: group.seriesIndex)
            stroke(group.laneLines, width: GitGraphDrawingParts.laneLineWidth, color: color, dash: GitGraphDrawingParts.laneDashLengths, in: context)
            fill(group.nameBoxes, color: color, in: context)
        }
    }

    /// The lines between lanes, then those to cherry-picks, then those along lanes, with round caps.
    private static func drawConnectors(_ parts: GitGraphDrawingParts, in context: CGContext, palette: DiagramPalette) {
        context.saveGState()
        context.setLineCap(.round)
        let width = GitGraphDrawingParts.connectorLineWidth
        for group in parts.colorGroups { stroke(group.curves, width: width, color: palette.seriesColor(at: group.seriesIndex), in: context) }
        for group in parts.colorGroups {
            stroke(group.cherryPickCurves, width: width, color: palette.seriesColor(at: group.seriesIndex), dash: GitGraphDrawingParts.cherryPickDashLengths,
                   in: context)
        }
        for group in parts.colorGroups { stroke(group.straightLines, width: width, color: palette.seriesColor(at: group.seriesIndex), in: context) }
        context.restoreGState()
    }

    /// Rings, filled in the background color and outlined, then the symbols' fills, then their marks.
    private static func drawSymbols(_ parts: GitGraphDrawingParts, in context: CGContext, palette: DiagramPalette) {
        for group in parts.colorGroups {
            let color = palette.seriesColor(at: group.seriesIndex)
            fill(group.rings, color: palette.background, in: context)
            stroke(group.rings, width: GitGraphDrawingParts.ringLineWidth, color: color, in: context)
            fill(group.symbols, color: color, in: context)
        }
        context.saveGState()
        context.setLineCap(.round)
        stroke(parts.reverseCrosses, width: GitGraphDrawingParts.crossLineWidth, color: palette.background, in: context)
        context.setLineCap(.butt)
        context.setLineJoin(.round)
        stroke(parts.cherryStems, width: GitGraphDrawingParts.cherryStemLineWidth, color: palette.background, in: context)
        context.restoreGState()
        fill(parts.cherryFruits, color: palette.background, in: context)
    }

    /// An id turned by its angle about its center.
    private static func drawTurned(_ label: GitGraphLayoutCommitLabel, with text: inout DiagramTextDrawing, color: CGColor, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: label.text.center.x, y: label.text.center.y)
        context.rotate(by: label.angle)
        var centered = label.text
        centered.center = .zero
        text.draw(centered, color: color, in: context)
        context.restoreGState()
    }

    private static func stroke(_ path: CGPath, width: CGFloat, color: CGColor, dash: [CGFloat] = [], in context: CGContext) {
        guard !path.isEmpty else { return }
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.setLineDash(phase: 0, lengths: dash)
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
