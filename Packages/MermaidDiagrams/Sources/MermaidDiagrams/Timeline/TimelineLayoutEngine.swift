import CoreGraphics

/// Lays a timeline out in Pele's style: across, its periods in columns along an axis with their events below; down
/// (`timeline TD`), its periods in a column beside the axis with their events to the right. Periods and sections are
/// boxes in their series colors, events tinted boxes, text wrapped in columns 152 to 216 points wide (events at
/// seven eighths of the size), and the title above.
public enum TimelineLayoutEngine {
    /// Around the whole diagram.
    static let padding: CGFloat = 8
    /// Between the title and the diagram.
    static let titleGap: CGFloat = 16
    /// The narrowest a title wraps at, when the body is narrower.
    static let narrowestTitleWidth: CGFloat = 320

    public static func layout(_ diagram: TimelineDiagram, typography: DiagramTypography) -> TimelineLayout {
        layout(diagram, periodText: typography.nodeText, eventText: typography.edgeText, font: typography.font)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: TimelineDiagram, periodText: Measurer, eventText: Measurer,
                                                       font: DiagramFont) -> TimelineLayout {
        let isDown = diagram.direction == .topToBottom
        let placement = TimelinePlacement(diagram: diagram,
                                          measured: TimelineMeasurement(diagram: diagram, periodText: periodText, eventText: eventText, isDown: isDown),
                                          groups: TimelineGroup.groups(of: diagram), periodText: periodText, eventText: eventText)
        let bodyWidth = placement.bodyWidth(isDown: isDown)
        let title = diagram.title.map { title in
            TimelineTextFitting.fitted(DiagramLabelDecoder.label(from: title, form: .literal), measurer: periodText,
                                       maximumWidth: max(bodyWidth, narrowestTitleWidth))
        }
        let titleSize = title?.size ?? .zero
        let width = max(bodyWidth, titleSize.width)
        let origin = CGPoint(x: padding + (width - bodyWidth) / 2, y: padding + (title == nil ? 0 : titleSize.height + titleGap))
        let body = isDown ? TimelineDownPlacement(placement: placement).placed(at: origin) : TimelineAcrossPlacement(placement: placement).placed(at: origin)
        let size = CGSize(width: (width + 2 * padding).rounded(.up), height: max(body.bottom + padding, 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        return TimelineLayout(size: size, font: font, direction: diagram.direction, sections: body.sections, periods: body.periods, axis: body.axis,
                              axisArrow: body.axisArrow, title: placedTitle)
    }
}
