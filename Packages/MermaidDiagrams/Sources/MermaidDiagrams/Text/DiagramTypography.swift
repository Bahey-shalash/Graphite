import CoreGraphics

/// The fonts a diagram's text is measured in: the nodes' font, its bold, and the smaller ones of edges, annotations,
/// chart rows and axes. Made once for a font and
/// used for every diagram drawn in it, since reading a font's advances costs more than laying a diagram out.
public struct DiagramTypography {
    public let font: DiagramFont
    let nodeText: CoreTextDiagramTextMeasurer
    let edgeText: CoreTextDiagramTextMeasurer
    /// The nodes' font in bold: a class's name, measured as it is drawn.
    let boldNodeText: CoreTextDiagramTextMeasurer
    /// Four fifths of the nodes' size, rounded: a class's annotations and a relation's cardinalities, as in Pele.
    let smallText: CoreTextDiagramTextMeasurer
    /// The text of a chart's rows, such as a Gantt chart's tasks and sections: thirteen sixteenths of the size.
    let rowText: CoreTextDiagramTextMeasurer
    /// The dates of a chart's axis: three quarters of the size.
    let axisText: CoreTextDiagramTextMeasurer

    /// Edge text is seven eighths of the nodes' size, rounded, as in Pele.
    static let edgeTextScale: CGFloat = 0.875
    static let smallTextScale: CGFloat = 0.8
    /// Pele's Gantt task labels: 13 points at 16.
    static let rowTextScale: CGFloat = 0.8125
    /// Pele's axis dates: 12 points at 16.
    static let axisTextScale: CGFloat = 0.75

    public init(font: DiagramFont) {
        self.font = font
        nodeText = CoreTextDiagramTextMeasurer(font: font)
        edgeText = CoreTextDiagramTextMeasurer(font: font.resized(to: (font.size * Self.edgeTextScale).rounded()))
        boldNodeText = CoreTextDiagramTextMeasurer(font: font, isBold: true)
        smallText = CoreTextDiagramTextMeasurer(font: font.resized(to: (font.size * Self.smallTextScale).rounded()))
        rowText = CoreTextDiagramTextMeasurer(font: font.resized(to: (font.size * Self.rowTextScale).rounded()))
        axisText = CoreTextDiagramTextMeasurer(font: font.resized(to: (font.size * Self.axisTextScale).rounded()))
    }
}
