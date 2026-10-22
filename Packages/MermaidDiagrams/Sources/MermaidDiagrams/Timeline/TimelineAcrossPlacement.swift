import CoreGraphics

/// Places a timeline that runs across, as Pele does: each period in a column, a section's heading over its periods'
/// columns, the periods in a row, the axis below them with a dot under each, and each period's events stacked under
/// the axis, joined to it by a line.
struct TimelineAcrossPlacement<Measurer: DiagramTextMeasuring> {
    let placement: TimelinePlacement<Measurer>

    /// The body placed with its top left corner at `origin`.
    func placed(at origin: CGPoint) -> TimelinePlacedBody {
        let columnWidth = placement.columnWidth
        let pitch = columnWidth + TimelineGeometry.gap
        let sectionTexts = placement.groups.map { group in
            group.sectionIndex.map { section in placement.sectionText(section, boxWidth: span(of: group) * pitch - TimelineGeometry.gap) }
        }
        let headerHeight = sectionTexts.compactMap { text in text.map(placement.chipHeight) }.max() ?? 0
        let chipHeight = placement.measured.periodTexts.map(placement.chipHeight).max() ?? 0
        let periodsTop = origin.y + (placement.diagram.sections.isEmpty ? 0 : headerHeight + TimelineGeometry.sectionGap)
        let axisY = periodsTop + chipHeight + (chipHeight > 0 ? TimelineGeometry.axisGap : 0)
        var body = TimelinePlacedBody()
        body.bottom = placement.hasPeriods ? axisY + TimelineGeometry.axisTail : origin.y + headerHeight
        var slot: CGFloat = 0
        for (group, sectionText) in zip(placement.groups, sectionTexts) {
            let groupLeft = origin.x + slot * pitch
            if let section = group.sectionIndex, let sectionText {
                let frame = CGRect(x: groupLeft, y: origin.y, width: span(of: group) * pitch - TimelineGeometry.gap, height: headerHeight)
                body.sections.append(TimelineLayoutSection(sectionIndex: section, frame: frame, text: TimelineGeometry.centered(sectionText, in: frame)))
            }
            for (position, periodIndex) in group.periodIndices.enumerated() {
                let frame = CGRect(x: groupLeft + CGFloat(position) * pitch, y: periodsTop, width: columnWidth, height: chipHeight)
                let period = placedPeriod(periodIndex, in: group, frame: frame, axisY: axisY)
                body.bottom = max(body.bottom, period.events.last.map(\.frame.maxY) ?? body.bottom)
                body.periods.append(period)
            }
            slot += span(of: group)
        }
        if placement.hasPeriods {
            let tip = CGPoint(x: origin.x + placement.bodyWidth(isDown: false), y: axisY)
            body.axis = TimelineGeometry.line(CGPoint(x: origin.x, y: axisY), CGPoint(x: tip.x - DiagramEdgeMark.arrowLength + 1, y: axisY))
            body.axisArrow = DiagramEdgeMark(arrowhead: .arrow, tip: tip, direction: CGVector(dx: 1, dy: 0))
        }
        return body
    }

    /// How many columns a group takes: one per period, and one for a section without periods.
    private func span(of group: TimelineGroup) -> CGFloat {
        CGFloat(max(group.periodIndices.count, 1))
    }

    /// A period in its column: its box, its dot on the axis, and its events stacked below the axis.
    private func placedPeriod(_ periodIndex: Int, in group: TimelineGroup, frame: CGRect, axisY: CGFloat) -> TimelineLayoutPeriod {
        let eventTexts = placement.measured.eventTexts[periodIndex]
        let eventsTop = axisY + TimelineGeometry.axisGap
        var connectors = [TimelineGeometry.line(CGPoint(x: frame.midX, y: frame.maxY),
                                                           CGPoint(x: frame.midX, y: eventTexts.isEmpty ? axisY : eventsTop))]
        var events: [TimelineLayoutEvent] = []
        var eventTop = eventsTop
        for eventText in eventTexts {
            if eventTop > eventsTop {
                connectors.append(TimelineGeometry.line(CGPoint(x: frame.midX, y: eventTop - TimelineGeometry.eventGap), CGPoint(x: frame.midX, y: eventTop)))
            }
            let eventFrame = CGRect(x: frame.minX, y: eventTop, width: placement.eventWidth, height: placement.eventHeight(eventText))
            events.append(TimelineLayoutEvent(frame: eventFrame, text: TimelineGeometry.centered(eventText, in: eventFrame)))
            eventTop = eventFrame.maxY + TimelineGeometry.eventGap
        }
        return TimelineLayoutPeriod(color: placement.color(ofPeriod: periodIndex, in: group), frame: frame,
                                    text: TimelineGeometry.centered(placement.measured.periodTexts[periodIndex], in: frame),
                                    dot: CGPoint(x: frame.midX, y: axisY), connectors: connectors, events: events)
    }
}
