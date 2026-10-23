import CoreGraphics

/// A laid-out user journey's geometry grouped by how it is painted, so that drawing it in any colors is a few fills
/// and strokes, by Core Graphics (`UserJourneyRenderer`) or by a view's own shapes. Back to front, as Pele draws: the
/// scale, the stems, the line from face to face, the faces, the bands, the cards with their text and dots, the
/// legend, the title.
public struct UserJourneyDrawingParts {
    /// The scale's lines, stroked `lineWidth` wide in the second surface.
    public let scaleLines: CGPath
    /// The dashed stems from the cards to the faces, stroked `lineWidth` wide in the border color, `stemDashLengths`.
    public let stems: CGPath
    /// The line from face to face, stroked `lineWidth` wide in the line color with round joins; empty for one task.
    public let scoreLine: CGPath
    /// The faces' circles, filled in the background color and stroked `lineWidth` wide in the line color.
    public let faces: CGPath
    /// The faces' eyes, filled in the line color.
    public let eyes: CGPath
    /// The faces' mouths, stroked `lineWidth` wide in the line color with round caps.
    public let mouths: CGPath
    /// The sections' bands, filled in the second surface.
    public let sectionBands: CGPath
    /// The cards, filled in the surface color and stroked `lineWidth` wide in the border color.
    public let cards: CGPath
    /// For each series color, the actors' dots on the cards in it: entry `k` is filled in
    /// `DiagramPalette.seriesColor(at: k)` and stroked `lineWidth` wide in the surface color, and holds the dots of the
    /// actors whose index leaves `k` when divided by the number of series colors.
    public let cardDotsBySeries: [CGPath]
    /// For each series color, the legend's dots in it, filled only.
    public let legendDotsBySeries: [CGPath]
    /// The scale's numbers, in the muted color.
    public let scaleTexts: [DiagramTextBlock]
    /// The bands' headings, drawn bold in the foreground color.
    public let sectionTexts: [DiagramTextBlock]
    /// The cards' text and the legend's names, in the foreground color.
    public let taskTexts: [DiagramTextBlock]
    public let legendTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    /// Pele's `2 3`: two points drawn, three left.
    public static let stemDashLengths: [CGFloat] = [2, 3]
    /// Pele's eight `--pele-series-*` colors, which the actors take in turn.
    public static let seriesColorCount = DiagramPalette.peleSeries.count
    /// The corner radius of the cards and bands: Pele's `--pele-radius`.
    static let cornerRadius: CGFloat = 4

    public init(layout: UserJourneyLayout) {
        let faces = CGMutablePath()
        let eyes = CGMutablePath()
        let mouths = CGMutablePath()
        let stems = CGMutablePath()
        let cards = CGMutablePath()
        let actorCount = layout.legend.count
        let cardDots = (0..<min(actorCount, Self.seriesColorCount)).map { _ in CGMutablePath() }
        for task in layout.tasks {
            UserJourneyFaceShape.add(task.mood, at: task.faceCenter, circles: faces, eyes: eyes, mouths: mouths)
            stems.addPath(DiagramEdgeDrawing.path(task.stem))
            cards.addPath(Self.roundedRectangle(task.frame))
            for dot in task.actorDots { Self.add(dot, to: cardDots) }
        }
        let legendDots = (0..<min(actorCount, Self.seriesColorCount)).map { _ in CGMutablePath() }
        for entry in layout.legend { Self.add(entry.dot, to: legendDots) }
        let scaleLines = CGMutablePath()
        for level in layout.scaleLevels { scaleLines.addPath(DiagramEdgeDrawing.path(level.line)) }
        let bands = CGMutablePath()
        for section in layout.sections { bands.addPath(Self.roundedRectangle(section.frame)) }
        self.scaleLines = scaleLines
        self.stems = stems
        scoreLine = layout.scoreLine.map(DiagramEdgeDrawing.path) ?? CGMutablePath()
        self.faces = faces
        self.eyes = eyes
        self.mouths = mouths
        sectionBands = bands
        self.cards = cards
        cardDotsBySeries = cardDots
        legendDotsBySeries = legendDots
        scaleTexts = layout.scaleLevels.map(\.text)
        sectionTexts = layout.sections.map(\.text)
        taskTexts = layout.tasks.map(\.text)
        legendTexts = layout.legend.map(\.text)
        title = layout.title
    }

    private static func add(_ dot: UserJourneyActorDot, to dotsBySeries: [CGMutablePath]) {
        let radius = UserJourneyGeometry.dotRadius
        dotsBySeries[dot.seriesIndex % seriesColorCount].addEllipse(in: CGRect(x: dot.center.x - radius, y: dot.center.y - radius,
                                                                               width: 2 * radius, height: 2 * radius))
    }

    private static func roundedRectangle(_ frame: CGRect) -> CGPath {
        CGPath(roundedRect: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    }
}
