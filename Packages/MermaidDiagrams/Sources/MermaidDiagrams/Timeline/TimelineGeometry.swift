import CoreGraphics

/// Pele's spacing of a timeline, in points, and the small geometry its placements share.
enum TimelineGeometry {
    /// Inside a box, across and down from its text.
    static let boxPadding = CGSize(width: 12, height: 8)
    /// Between two columns across, or two periods down.
    static let gap: CGFloat = 20
    /// Between the periods and the axis, and between the axis and the events.
    static let axisGap: CGFloat = 20
    /// Running down, between the axis and the spine that leads to the events, and between the spine and the events.
    static let spineGap: CGFloat = 14
    static let eventGap: CGFloat = 8
    static let sectionGap: CGFloat = 8
    /// Running down, the extra room below a section's heading.
    static let sectionExtraGapDown: CGFloat = 4
    /// How far the axis runs past the last period before its arrow.
    static let axisTail: CGFloat = 12

    /// A text block centered in `frame`.
    static func centered(_ text: DiagramTextBlock, in frame: CGRect) -> DiagramTextBlock {
        var centered = text
        centered.center = CGPoint(x: frame.midX, y: frame.midY)
        return centered
    }

    /// A straight line through `points`.
    static func line(_ points: CGPoint...) -> DiagramPath {
        DiagramPath(start: points[0], segments: points.dropFirst().map { point in .line(to: point) })
    }
}
