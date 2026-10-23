import CoreGraphics

/// A quadrant chart laid out on a page whose origin is the top left corner and whose y runs down, in points: the
/// title, the four quadrants, the axes' texts beside them, and the points with their texts. Drawing it needs only the
/// palette's colors, and the colors the chart's text writes for its points.
public struct QuadrantChartLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the quadrants' text and the title (bold) were measured in; the axes' texts are in its size seven
    /// eighths, the points' in three quarters.
    public let font: DiagramFont
    /// Quadrants 1 to 4: top right, top left, bottom left, bottom right.
    public let quadrants: [QuadrantChartLayoutQuadrant]
    /// The axes' texts that are written: the x axis's below or above the quadrants, the y axis's at their left.
    public let axisLabels: [QuadrantChartAxisLabel]
    /// The points drawn, in the order they are written: the first is painted last, on top, as in Mermaid.
    public let points: [QuadrantChartLayoutPoint]
    /// The chart's title above it, drawn bold, or nil.
    public let title: DiagramTextBlock?
}

/// A quadrant's box, filled in the surface color and outlined in the border color, and its text, or nil.
public struct QuadrantChartLayoutQuadrant: Equatable, Sendable {
    public let frame: CGRect
    public let text: DiagramTextBlock?
}

/// An axis's text, drawn in the muted color. A turned text, the y axis's, is drawn a quarter turn anticlockwise about
/// its center, so that it reads from bottom to top; its block is measured as if it were not turned.
public struct QuadrantChartAxisLabel: Equatable, Sendable {
    public let text: DiagramTextBlock
    public let isTurned: Bool
}

/// A point: its circle, its paint, and its text placed where it is free.
public struct QuadrantChartLayoutPoint: Equatable, Sendable {
    public let center: CGPoint
    public let radius: CGFloat
    public let fill: QuadrantChartPaint
    /// The outline, when the chart gives the point a stroke width; nil otherwise.
    public let stroke: QuadrantChartStroke?
    public let text: DiagramTextBlock
}

/// What a point is painted in: the palette's first series color, Pele's, or a color the chart's text writes.
public enum QuadrantChartPaint: Equatable, Sendable {
    case firstSeries
    case written(QuadrantChartColor)
}

/// A point's outline: its paint and its width in points.
public struct QuadrantChartStroke: Equatable, Sendable {
    public let paint: QuadrantChartPaint
    public let width: CGFloat
}
