import CoreGraphics

/// A timeline's text measured as Pele measures it: periods wrapped at a column 152 points wide, and events at the
/// same width across or 264 points running down; a word too wide widens the columns up to 216 points, past which it
/// is cut.
struct TimelineMeasurement {
    /// The width of a period's text, and of an event's across.
    let textWidth: CGFloat
    /// The width of an event's text.
    let eventTextWidth: CGFloat
    let periodTexts: [DiagramTextBlock]
    /// Each period's events' text.
    let eventTexts: [[DiagramTextBlock]]

    static let narrowestTextWidth: CGFloat = 152
    static let widestTextWidth: CGFloat = 216
    /// The width of an event's text when the timeline runs down, beside its period.
    static let eventTextWidthDown: CGFloat = 264

    init<Measurer: DiagramTextMeasuring>(diagram: TimelineDiagram, periodText: Measurer, eventText: Measurer, isDown: Bool) {
        var textWidth = Self.narrowestTextWidth
        func eventWidth() -> CGFloat { isDown ? Self.eventTextWidthDown : textWidth }
        var periodTexts = diagram.periods.map { period in TimelineTextFitting.wrapped(period.label, measurer: periodText, maximumWidth: textWidth) }
        var eventTexts = diagram.periods.map { period in
            period.events.map { event in TimelineTextFitting.wrapped(event, measurer: eventText, maximumWidth: eventWidth()) }
        }
        var widest = periodTexts.map(\.size.width).max() ?? 0
        if !isDown { widest = max(widest, eventTexts.joined().map(\.size.width).max() ?? 0) }
        let eventOverflows = isDown && eventTexts.joined().contains { text in text.size.width > Self.eventTextWidthDown }
        if widest > textWidth || eventOverflows {
            textWidth = min(max(widest.rounded(.up), Self.narrowestTextWidth), Self.widestTextWidth)
            periodTexts = diagram.periods.map { period in TimelineTextFitting.fitted(period.label, measurer: periodText, maximumWidth: textWidth) }
            eventTexts = diagram.periods.map { period in
                period.events.map { event in TimelineTextFitting.fitted(event, measurer: eventText, maximumWidth: eventWidth()) }
            }
        }
        self.textWidth = textWidth
        eventTextWidth = eventWidth()
        self.periodTexts = periodTexts
        self.eventTexts = eventTexts
    }
}
