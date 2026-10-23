import CoreGraphics

/// A pie chart laid out on a page whose origin is the top left corner and whose y runs down, in points: the pie, its
/// legend on the right and its title above. Drawing it needs only colors.
public struct PieChartLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the text was measured in: the title at its size, percentages and legend at their own `fontSize`.
    public let font: DiagramFont
    /// The pie's center.
    public let center: CGPoint
    public let radius: CGFloat
    /// The slices drawn, clockwise from the top in the order they are written. A slice under one percent of the
    /// whole is not drawn, and its legend entry stays.
    public let slices: [PieChartLayoutSlice]
    /// One entry per slice of the chart, in the order they are written.
    public let legend: [PieChartLegendEntry]
    /// The chart's title above it, or nil.
    public let title: DiagramTextBlock?
}

public struct PieChartLayoutSlice: Equatable, Sendable {
    /// The slice's place among the chart's slices, which picks its series color.
    public let seriesIndex: Int
    /// Where the slice starts, in radians clockwise from the top of the pie.
    public let startAngle: CGFloat
    /// Where the slice ends, in radians clockwise from the top of the pie.
    public let endAngle: CGFloat
    /// The slice's share of the whole in whole percent (`79%`).
    public let percentage: DiagramTextBlock
    public let percentagePlacement: PieChartPercentagePlacement

    /// Whether the slice is the whole pie, drawn as a circle.
    public var isWholePie: Bool {
        endAngle - startAngle >= 2 * .pi - PieChartLayoutEngine.wholePieTolerance
    }
}

/// Where a slice's percentage is drawn.
public enum PieChartPercentagePlacement: Equatable, Sendable {
    /// Inside the slice, three quarters of the way out, in the background color.
    case insideSlice
    /// Outside the rim, in the text color, for a slice too thin to hold it.
    case outsideRim
}

/// One row of the legend: a swatch in the slice's series color, then the slice's label.
public struct PieChartLegendEntry: Equatable, Sendable {
    public let seriesIndex: Int
    public let swatch: CGRect
    /// The label, followed by the value in brackets when the chart shows its values (`Dogs [386]`).
    public let text: DiagramTextBlock
}
