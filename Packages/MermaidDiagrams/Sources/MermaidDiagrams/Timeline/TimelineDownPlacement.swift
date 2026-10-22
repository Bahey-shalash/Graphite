import CoreGraphics

/// Places a timeline that runs down, as Pele does: the periods one below the other in a column, a section's heading
/// across the whole width above its periods, the axis to the right of the periods with a dot level with each, and
/// each period's events stacked beside it, reached by a spine; a period and its first event share a center line.
struct TimelineDownPlacement<Measurer: DiagramTextMeasuring> {
    let placement: TimelinePlacement<Measurer>

    /// The body placed with its top left corner at `origin`.
    func placed(at origin: CGPoint) -> TimelinePlacedBody {
        let bodyWidth = placement.bodyWidth(isDown: true)
        let axisX = origin.x + placement.columnWidth + TimelineGeometry.axisGap
        var body = TimelinePlacedBody()
        var top = origin.y
        for group in placement.groups {
            if let section = group.sectionIndex {
                let text = placement.sectionText(section, boxWidth: bodyWidth)
                let frame = CGRect(x: origin.x, y: top, width: bodyWidth, height: placement.chipHeight(text))
                body.sections.append(TimelineLayoutSection(sectionIndex: section, frame: frame, text: TimelineGeometry.centered(text, in: frame)))
                top = frame.maxY + TimelineGeometry.sectionGap + TimelineGeometry.sectionExtraGapDown
            }
            for periodIndex in group.periodIndices {
                let period = placedPeriod(periodIndex, in: group, top: top, left: origin.x, axisX: axisX)
                body.periods.append(period)
                top = max(period.frame.maxY, period.events.last?.frame.maxY ?? period.frame.maxY) + TimelineGeometry.gap
            }
            if group.periodIndices.isEmpty { top += TimelineGeometry.gap - TimelineGeometry.sectionGap - TimelineGeometry.sectionExtraGapDown }
        }
        if !placement.groups.isEmpty { top -= TimelineGeometry.gap }
        if placement.hasPeriods {
            let tip = CGPoint(x: axisX, y: top + TimelineGeometry.axisTail + DiagramEdgeMark.arrowLength)
            body.axis = TimelineGeometry.line(CGPoint(x: axisX, y: origin.y), CGPoint(x: axisX, y: tip.y - DiagramEdgeMark.arrowLength + 1))
            body.axisArrow = DiagramEdgeMark(arrowhead: .arrow, tip: tip, direction: CGVector(dx: 0, dy: 1))
            top = tip.y
        }
        body.bottom = top
        return body
    }

    /// A period from `top`: its box and its first event centered on one line, the line to the axis and its dot, and
    /// its events stacked to the right, each reached from the spine.
    private func placedPeriod(_ periodIndex: Int, in group: TimelineGroup, top: CGFloat, left: CGFloat, axisX: CGFloat) -> TimelineLayoutPeriod {
        let periodText = placement.measured.periodTexts[periodIndex]
        let eventTexts = placement.measured.eventTexts[periodIndex]
        let height = placement.chipHeight(periodText)
        let firstEventHeight = eventTexts.first.map(placement.eventHeight) ?? height
        let centerY = top + max(height, firstEventHeight) / 2
        let frame = CGRect(x: left, y: centerY - height / 2, width: placement.columnWidth, height: height)
        let spineX = axisX + TimelineGeometry.spineGap
        let eventsX = spineX + TimelineGeometry.spineGap
        var connectors = [TimelineGeometry.line(CGPoint(x: frame.maxX, y: centerY), CGPoint(x: axisX, y: centerY))]
        var events: [TimelineLayoutEvent] = []
        var eventTop = centerY - firstEventHeight / 2
        for eventText in eventTexts {
            let eventFrame = CGRect(x: eventsX, y: eventTop, width: placement.eventWidth, height: placement.eventHeight(eventText))
            connectors.append(TimelineGeometry.line(CGPoint(x: spineX, y: eventFrame.midY), CGPoint(x: eventsX, y: eventFrame.midY)))
            events.append(TimelineLayoutEvent(frame: eventFrame, text: TimelineGeometry.centered(eventText, in: eventFrame)))
            eventTop = eventFrame.maxY + TimelineGeometry.eventGap
        }
        if let lastEvent = events.last {
            connectors.append(TimelineGeometry.line(CGPoint(x: axisX, y: centerY), CGPoint(x: spineX, y: centerY),
                                                    CGPoint(x: spineX, y: lastEvent.frame.midY)))
        }
        return TimelineLayoutPeriod(color: placement.color(ofPeriod: periodIndex, in: group), frame: frame,
                                    text: TimelineGeometry.centered(periodText, in: frame), dot: CGPoint(x: axisX, y: centerY),
                                    connectors: connectors, events: events)
    }
}
