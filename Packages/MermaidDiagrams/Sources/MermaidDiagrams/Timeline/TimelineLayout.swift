import CoreGraphics

/// A timeline laid out on a page whose origin is the top left corner and whose y runs down, in points. Drawing it
/// needs only colors: every position, path and text measurement is here.
public struct TimelineLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the periods' and sections' text was measured in; events' text is in the same font at its own size.
    public let font: DiagramFont
    public let direction: TimelineDirection
    /// The section headings, each over or before the periods written under it.
    public let sections: [TimelineLayoutSection]
    /// The periods in the order they are written.
    public let periods: [TimelineLayoutPeriod]
    /// The axis the periods hang from, which stops where its arrow begins, and the arrow; nil without periods.
    public let axis: DiagramPath?
    public let axisArrow: DiagramEdgeMark?
    /// The diagram's title above it, or nil.
    public let title: DiagramTextBlock?
}

/// A section heading: a box in its section's series color with its text, drawn bold in the background color.
public struct TimelineLayoutSection: Equatable, Sendable {
    public let sectionIndex: Int
    public let frame: CGRect
    public let text: DiagramTextBlock
}

/// A period: its box, in its color, with its text in the background color; its dot on the axis; the lines from it to
/// the axis and on to its events; and its events' boxes, tinted in its color, with their text.
public struct TimelineLayoutPeriod: Equatable, Sendable {
    public let color: TimelineColor
    public let frame: CGRect
    public let text: DiagramTextBlock
    /// The center of the dot where the period meets the axis.
    public let dot: CGPoint
    public let connectors: [DiagramPath]
    public let events: [TimelineLayoutEvent]
}

public struct TimelineLayoutEvent: Equatable, Sendable {
    public let frame: CGRect
    public let text: DiagramTextBlock
}

/// The color a period takes, as Pele colors them: its section's series color; without sections, the series colors
/// in turn; a period before the first section of a timeline that has sections is muted.
public enum TimelineColor: Equatable, Sendable {
    case series(Int)
    case muted
}
