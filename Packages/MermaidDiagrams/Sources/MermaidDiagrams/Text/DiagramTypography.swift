import CoreGraphics

/// The fonts a diagram's text is measured in: the nodes' font and the edges' smaller one. Made once for a font and
/// used for every diagram drawn in it, since reading a font's advances costs more than laying a diagram out.
public struct DiagramTypography {
    public let font: DiagramFont
    let nodeText: CoreTextDiagramTextMeasurer
    let edgeText: CoreTextDiagramTextMeasurer

    /// Edge text is seven eighths of the nodes' size, rounded, as in Pele.
    static let edgeTextScale: CGFloat = 0.875

    public init(font: DiagramFont) {
        self.font = font
        nodeText = CoreTextDiagramTextMeasurer(font: font)
        edgeText = CoreTextDiagramTextMeasurer(font: font.resized(to: (font.size * Self.edgeTextScale).rounded()))
    }
}
