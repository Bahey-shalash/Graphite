import CoreGraphics

/// Lays a user journey out in Pele's style: the tasks as cards side by side under their sections' bands, a scale
/// from 5 to 1 below them with a face per task at its score (happy, neutral or sad) and a line from face to face, the
/// actors' dots on the cards in their series colors, the legend of actors centered below, and the title above. Cards
/// and bands are in the smaller text size, seven eighths of the title's, and the scale's numbers in three quarters.
public enum UserJourneyLayoutEngine {
    /// Around the whole diagram.
    static let padding: CGFloat = 8
    /// Between the title and the diagram.
    static let titleGap: CGFloat = 16
    /// The narrowest a title wraps at, when the body is narrower.
    static let narrowestTitleWidth: CGFloat = 320

    public static func layout(_ diagram: UserJourneyDiagram, typography: DiagramTypography) -> UserJourneyLayout {
        layout(diagram, taskText: typography.edgeText, scaleText: typography.axisText, titleText: typography.boldNodeText, font: typography.font)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: UserJourneyDiagram, taskText: Measurer, scaleText: Measurer, titleText: Measurer,
                                                       font: DiagramFont) -> UserJourneyLayout {
        let measured = UserJourneyMeasurement(diagram: diagram, taskText: taskText)
        let actorNames = diagram.actorNames
        let legend = UserJourneyLegendRows(actorNames: actorNames, measurer: taskText,
                                           rowWidth: max(measured.plotWidth, UserJourneyGeometry.narrowestLegendWidth))
        let bodyWidth = diagram.tasks.isEmpty ? 0 : UserJourneyGeometry.scaleGutter + measured.plotWidth
        let title = diagram.title.map { title in
            TimelineTextFitting.fitted(DiagramLabelDecoder.label(from: title, form: .literal), measurer: titleText,
                                       maximumWidth: max(bodyWidth, narrowestTitleWidth))
        }
        let titleSize = title?.size ?? .zero
        let legendWidth = diagram.tasks.isEmpty ? 0 : UserJourneyGeometry.scaleGutter + legend.size.width
        let width = max(bodyWidth, titleSize.width, legendWidth)
        let origin = CGPoint(x: padding + (width - bodyWidth) / 2 + UserJourneyGeometry.scaleGutter,
                             y: padding + (title == nil ? 0 : titleSize.height + titleGap))
        let actorIndices = Dictionary(uniqueKeysWithValues: actorNames.enumerated().map { index, name in (name, index) })
        let body = UserJourneyPlacement(diagram: diagram, measured: measured, actorIndices: actorIndices, taskText: taskText, scaleText: scaleText)
            .placed(at: origin)
        var bottom = body.bottom
        var legendEntries: [UserJourneyLegendEntry] = []
        if !diagram.tasks.isEmpty, !legend.entries.isEmpty {
            let legendOrigin = CGPoint(x: origin.x + (measured.plotWidth - legend.size.width) / 2, y: body.bottom + UserJourneyGeometry.legendGap)
            legendEntries = legend.placed(at: legendOrigin)
            bottom = legendOrigin.y + legend.size.height
        }
        let size = CGSize(width: (width + 2 * padding).rounded(.up), height: (max(bottom, padding) + padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: padding + width / 2, y: padding + titleSize.height / 2)
        return UserJourneyLayout(size: size, font: font, sections: body.sections, tasks: body.tasks, scaleLevels: body.scaleLevels,
                                 scoreLine: body.scoreLine, legend: legendEntries, title: placedTitle)
    }
}
