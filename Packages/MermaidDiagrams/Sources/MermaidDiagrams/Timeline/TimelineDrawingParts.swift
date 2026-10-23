import CoreGraphics

/// A laid-out timeline's geometry grouped by how it is painted, so that drawing it in any colors is a few fills and
/// strokes per color, by Core Graphics (`TimelineRenderer`) or by a view's own shapes. Back to front: the axis and
/// its arrow, the lines to the events, then per color the section and period boxes, the event boxes and the dots,
/// then the text and the title.
public struct TimelineDrawingParts {
    /// The boxes and dots painted in one color: a series color, the colors taken in turn after
    /// `DiagramPalette.peleSeries.count`, or the muted color.
    public struct ColorGroup {
        public let color: TimelineColor
        /// Section headings and period boxes, filled in the color.
        public let boxes: CGPath
        /// Event boxes, filled with the color at `eventFillOpacity`.
        public let eventBoxes: CGPath
        /// The dots on the axis, filled in the color and outlined `dotOutlineWidth` wide in the background color.
        public let dots: CGPath
    }

    public let colorGroups: [ColorGroup]
    /// The axis, stroked `lineWidth` wide in the line color.
    public let axis: CGPath
    /// The axis's arrow, filled in the line color.
    public let axisArrow: CGPath
    /// The lines from periods to the axis and on to their events, stroked `lineWidth` wide in the border color.
    public let connectors: CGPath
    /// Section headings' text, bold, and periods' text, on their boxes in the background color.
    public let sectionTexts: [DiagramTextBlock]
    public let periodTexts: [DiagramTextBlock]
    /// Events' text, in the foreground color.
    public let eventTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    public static let dotOutlineWidth: CGFloat = 2
    /// How much of its period's color an event's box takes, over the background: Pele's tint.
    public static let eventFillOpacity: CGFloat = 0.16
    /// The corner radius of every box: Pele's `--pele-radius`.
    static let boxCornerRadius: CGFloat = 4
    static let dotRadius: CGFloat = 4

    public init(layout: TimelineLayout) {
        let groups = ColorGroups()
        for section in layout.sections { groups.paths(for: .series(section.sectionIndex)).boxes.addPath(Self.box(section.frame)) }
        let connectors = CGMutablePath()
        for period in layout.periods {
            let paths = groups.paths(for: period.color)
            paths.boxes.addPath(Self.box(period.frame))
            for event in period.events { paths.eventBoxes.addPath(Self.box(event.frame)) }
            paths.dots.addEllipse(in: CGRect(x: period.dot.x - Self.dotRadius, y: period.dot.y - Self.dotRadius, width: 2 * Self.dotRadius,
                                             height: 2 * Self.dotRadius))
            for connector in period.connectors { connectors.addPath(DiagramEdgeDrawing.path(connector)) }
        }
        colorGroups = groups.drawn
        axis = layout.axis.map(DiagramEdgeDrawing.path) ?? CGMutablePath()
        let arrow = CGMutablePath()
        if let axisArrow = layout.axisArrow { DiagramEdgeDrawing.addMark(axisArrow, filled: arrow, stroked: CGMutablePath()) }
        axisArrow = arrow
        self.connectors = connectors
        sectionTexts = layout.sections.map(\.text)
        periodTexts = layout.periods.map(\.text)
        eventTexts = layout.periods.flatMap { period in period.events.map(\.text) }
        title = layout.title
    }

    private static func box(_ frame: CGRect) -> CGPath {
        CGPath(roundedRect: frame, cornerWidth: boxCornerRadius, cornerHeight: boxCornerRadius, transform: nil)
    }

    /// The paths of each color: one per series color, the series counted again after the eighth, and the muted color.
    private struct ColorGroups {
        private let series = DiagramPalette.peleSeries.indices.map { _ in GroupPaths() }
        private let muted = GroupPaths()

        func paths(for color: TimelineColor) -> GroupPaths {
            switch color {
            case .series(let index): series[index % series.count]
            case .muted: muted
            }
        }

        var drawn: [ColorGroup] {
            let all = series.enumerated().map { index, paths in (TimelineColor.series(index), paths) } + [(TimelineColor.muted, muted)]
            return all.compactMap { color, paths in
                paths.boxes.isEmpty && paths.dots.isEmpty ? nil : ColorGroup(color: color, boxes: paths.boxes, eventBoxes: paths.eventBoxes, dots: paths.dots)
            }
        }
    }

    /// Core Graphics paths are references: a copy of these adds to the same paths.
    private struct GroupPaths {
        let boxes = CGMutablePath()
        let eventBoxes = CGMutablePath()
        let dots = CGMutablePath()
    }
}
