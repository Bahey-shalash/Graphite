import CoreGraphics

/// The fonts a diagram's text is measured in: the nodes' font, its bold, and two smaller ones. Made once for a font and
/// used for every diagram drawn in it, since reading a font's advances costs more than laying a diagram out.
public struct DiagramTypography {
    public let font: DiagramFont
    let nodeText: CoreTextDiagramTextMeasurer
    let edgeText: CoreTextDiagramTextMeasurer
    /// The nodes' font in bold: a class's name, measured as it is drawn.
    let boldNodeText: CoreTextDiagramTextMeasurer
    /// Four fifths of the nodes' size, rounded: a class's annotations and a relation's cardinalities, as in Pele.
    let smallText: CoreTextDiagramTextMeasurer

    /// Edge text is seven eighths of the nodes' size, rounded, as in Pele.
    static let edgeTextScale: CGFloat = 0.875
    static let smallTextScale: CGFloat = 0.8

    public init(font: DiagramFont) {
        self.font = font
        nodeText = CoreTextDiagramTextMeasurer(font: font)
        edgeText = CoreTextDiagramTextMeasurer(font: font.resized(to: (font.size * Self.edgeTextScale).rounded()))
        boldNodeText = CoreTextDiagramTextMeasurer(font: font, isBold: true)
        smallText = CoreTextDiagramTextMeasurer(font: font.resized(to: (font.size * Self.smallTextScale).rounded()))
    }
}
