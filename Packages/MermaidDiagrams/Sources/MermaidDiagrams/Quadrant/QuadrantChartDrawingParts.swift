import CoreGraphics

/// A laid-out quadrant chart's geometry grouped by how it is painted, so that drawing it in any colors is a few fills
/// and strokes, by Core Graphics (`QuadrantChartRenderer`) or by a view's own shapes. Back to front, as Pele draws:
/// the quadrants and their texts, the axes' texts, the points, their texts, the title.
public struct QuadrantChartDrawingParts {
    /// Points painted alike, in one fill and one outline.
    public struct PointGroup {
        public let circles: CGPath
        public let fill: QuadrantChartPaint
        /// The outline, stroked its width wide; nil for points without one.
        public let stroke: QuadrantChartStroke?
    }

    /// The quadrants' boxes, filled in the surface color and stroked `lineWidth` wide in the border color.
    public let quadrants: CGPath
    /// The quadrants' texts, in the foreground color.
    public let quadrantTexts: [DiagramTextBlock]
    /// The x axis's texts, in the muted color.
    public let axisTexts: [DiagramTextBlock]
    /// The y axis's texts, in the muted color, each turned a quarter anticlockwise about its center.
    public let turnedAxisTexts: [DiagramTextBlock]
    /// The points back to front: the last written first and the first last, on top, as Mermaid puts each new point
    /// under the ones before it. Points in a row painted alike without an outline share a group.
    public let pointGroups: [PointGroup]
    /// The points' texts, in the foreground color.
    public let pointTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    /// The corner radius of a quadrant's box: Pele's `--pele-radius`.
    static let cornerRadius: CGFloat = 4

    public init(layout: QuadrantChartLayout) {
        let quadrants = CGMutablePath()
        for quadrant in layout.quadrants {
            quadrants.addPath(CGPath(roundedRect: quadrant.frame, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil))
        }
        self.quadrants = quadrants
        quadrantTexts = layout.quadrants.compactMap(\.text)
        axisTexts = layout.axisLabels.filter { label in !label.isTurned }.map(\.text)
        turnedAxisTexts = layout.axisLabels.filter(\.isTurned).map(\.text)
        pointGroups = Self.groups(of: layout.points.reversed())
        pointTexts = layout.points.map(\.text)
        title = layout.title
    }

    /// The points' circles, back to front, a new group wherever the paint changes or a point has an outline: an outline
    /// is painted over its own point's fill and under the next point's.
    private static func groups(of points: [QuadrantChartLayoutPoint]) -> [PointGroup] {
        var groups: [PointGroup] = []
        var circles = CGMutablePath()
        var current: (fill: QuadrantChartPaint, stroke: QuadrantChartStroke?)?
        for point in points {
            if let paint = current, paint.fill != point.fill || paint.stroke != nil || point.stroke != nil {
                groups.append(PointGroup(circles: circles, fill: paint.fill, stroke: paint.stroke))
                circles = CGMutablePath()
            }
            circles.addEllipse(in: CGRect(x: point.center.x - point.radius, y: point.center.y - point.radius, width: 2 * point.radius,
                                          height: 2 * point.radius))
            current = (point.fill, point.stroke)
        }
        if let paint = current { groups.append(PointGroup(circles: circles, fill: paint.fill, stroke: paint.stroke)) }
        return groups
    }
}
