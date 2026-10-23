import CoreGraphics

/// A laid-out pie chart's geometry grouped by how it is painted, so that drawing it in any colors is a few fills and
/// strokes, by Core Graphics (`PieChartRenderer`) or by a view's own shapes. Back to front, as Pele draws: the slices
/// and their edges, the percentages, the legend, the title.
public struct PieChartDrawingParts {
    /// For each series color, the slices and legend swatches filled in it: entry `k` is filled in
    /// `DiagramPalette.seriesColor(at: k)` and holds the slices and swatches whose index leaves `k` when divided by the
    /// number of series colors. As many entries as the chart has slices, up to that number.
    public let seriesFills: [CGPath]
    /// The edges of the slices drawn, stroked one point wide in the background color with round joins, so that
    /// neighbouring slices stand apart.
    public let sliceEdges: CGPath
    /// The pie's circle when no slice is drawn (no slices, or none with a share), stroked one point wide in the border
    /// color; empty otherwise.
    public let emptyPieOutline: CGPath
    /// The percentages inside their slices, drawn in the background color.
    public let insidePercentages: [DiagramTextBlock]
    /// The percentages outside the rim, drawn in the text color.
    public let outsidePercentages: [DiagramTextBlock]
    /// The legend's labels, drawn in the text color.
    public let legendTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    /// Pele's eight `--pele-series-*` colors, which the slices take in turn.
    public static let seriesColorCount = DiagramPalette.peleSeries.count
    /// The corner radius of a legend swatch.
    static let swatchCornerRadius: CGFloat = 2

    public init(layout: PieChartLayout) {
        let fills = (0..<min(layout.legend.count, Self.seriesColorCount)).map { _ in CGMutablePath() }
        let edges = CGMutablePath()
        for slice in layout.slices {
            let wedge = Self.wedge(slice, center: layout.center, radius: layout.radius)
            fills[slice.seriesIndex % Self.seriesColorCount].addPath(wedge)
            edges.addPath(wedge)
        }
        for entry in layout.legend {
            fills[entry.seriesIndex % Self.seriesColorCount].addRoundedRect(in: entry.swatch, cornerWidth: Self.swatchCornerRadius,
                                                                            cornerHeight: Self.swatchCornerRadius)
        }
        seriesFills = fills
        sliceEdges = edges
        let pieFrame = CGRect(x: layout.center.x - layout.radius, y: layout.center.y - layout.radius, width: 2 * layout.radius, height: 2 * layout.radius)
        emptyPieOutline = layout.slices.isEmpty ? CGPath(ellipseIn: pieFrame, transform: nil) : CGMutablePath()
        insidePercentages = layout.slices.filter { slice in slice.percentagePlacement == .insideSlice }.map(\.percentage)
        outsidePercentages = layout.slices.filter { slice in slice.percentagePlacement == .outsideRim }.map(\.percentage)
        legendTexts = layout.legend.map(\.text)
        title = layout.title
    }

    /// A slice from the center out to the rim and back, or the whole circle for a slice that is the whole pie.
    static func wedge(_ slice: PieChartLayoutSlice, center: CGPoint, radius: CGFloat) -> CGPath {
        guard !slice.isWholePie else {
            return CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius), transform: nil)
        }
        let path = CGMutablePath()
        path.move(to: center)
        path.addLine(to: PieChartSlicePlacement.point(at: slice.startAngle, distance: radius, from: center))
        // Core Graphics measures angles from the x axis toward the y axis, which runs down here: a quarter turn
        // before the top, and with increasing angles, which turn clockwise on this page.
        path.addArc(center: center, radius: radius, startAngle: slice.startAngle - .pi / 2, endAngle: slice.endAngle - .pi / 2, clockwise: false)
        path.closeSubpath()
        return path
    }
}
