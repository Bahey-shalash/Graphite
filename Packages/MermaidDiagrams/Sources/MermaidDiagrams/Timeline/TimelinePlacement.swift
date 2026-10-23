import CoreGraphics

/// What both of a timeline's placements share: Pele's measurements, the boxes' sizes, and where the body starts.
/// `TimelineAcrossPlacement` and `TimelineDownPlacement` place the boxes.
struct TimelinePlacement<Measurer: DiagramTextMeasuring> {
    let diagram: TimelineDiagram
    let measured: TimelineMeasurement
    let groups: [TimelineGroup]
    /// The measurer of periods' and sections' text.
    let periodText: Measurer
    let eventText: Measurer

    var columnWidth: CGFloat { measured.textWidth + 2 * TimelineGeometry.boxPadding.width }
    var eventWidth: CGFloat { measured.eventTextWidth + 2 * TimelineGeometry.boxPadding.width }
    var hasEvents: Bool { measured.eventTexts.contains { events in !events.isEmpty } }
    var hasPeriods: Bool { !diagram.periods.isEmpty }

    /// The height of a period's or a section's box around its text, at least a line high.
    func chipHeight(_ text: DiagramTextBlock) -> CGFloat {
        max(text.size.height, periodText.lineHeight) + 2 * TimelineGeometry.boxPadding.height
    }

    func eventHeight(_ text: DiagramTextBlock) -> CGFloat {
        max(text.size.height, eventText.lineHeight) + 2 * TimelineGeometry.boxPadding.height
    }

    /// A section's heading text, fitted inside a box `width` wide.
    func sectionText(_ sectionIndex: Int, boxWidth width: CGFloat) -> DiagramTextBlock {
        TimelineTextFitting.fitted(diagram.sections[sectionIndex], measurer: periodText, maximumWidth: width - 2 * TimelineGeometry.boxPadding.width)
    }

    /// A period's color: its section's, the series in turn without sections, muted before the first section.
    func color(ofPeriod periodIndex: Int, in group: TimelineGroup) -> TimelineColor {
        if let section = group.sectionIndex { return .series(section) }
        return diagram.sections.isEmpty ? .series(periodIndex) : .muted
    }

    /// The width of everything but the title.
    func bodyWidth(isDown: Bool) -> CGFloat {
        if isDown {
            if hasEvents { return columnWidth + TimelineGeometry.axisGap + 2 * TimelineGeometry.spineGap + eventWidth }
            return columnWidth + (hasPeriods ? TimelineGeometry.axisGap + TimelineGeometry.axisTail : 0)
        }
        let slots = groups.reduce(0) { slots, group in slots + max(group.periodIndices.count, 1) }
        guard slots > 0 else { return 0 }
        let arrowRoom = hasPeriods ? TimelineGeometry.axisTail + DiagramEdgeMark.arrowLength : 0
        return CGFloat(slots) * (columnWidth + TimelineGeometry.gap) - TimelineGeometry.gap + arrowRoom
    }
}

/// What a placement makes: the boxes, the axis and how far down the body reaches.
struct TimelinePlacedBody {
    var sections: [TimelineLayoutSection] = []
    var periods: [TimelineLayoutPeriod] = []
    var axis: DiagramPath?
    var axisArrow: DiagramEdgeMark?
    var bottom: CGFloat = 0
}
