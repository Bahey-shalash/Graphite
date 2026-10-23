import CoreGraphics

/// Places a user journey's body as Pele does, from the top left corner of its first card's column: the section bands
/// in a row, the cards in a row below them, then the scale, each face at its task's level with a dashed stem up to its
/// card, and the line from face to face.
struct UserJourneyPlacement<Measurer: DiagramTextMeasuring> {
    let diagram: UserJourneyDiagram
    let measured: UserJourneyMeasurement
    /// Each actor's place among the journey's actors, by name.
    let actorIndices: [String: Int]
    let taskText: Measurer
    let scaleText: Measurer

    /// The body with its bands' top and its first card's left edge at `origin`.
    func placed(at origin: CGPoint) -> UserJourneyPlacedBody {
        guard !diagram.tasks.isEmpty else { return UserJourneyPlacedBody(bottom: origin.y) }
        let runs = UserJourneySectionRun.runs(of: diagram)
        let headings = runs.map { run in run.heading.map { heading in headingText(heading, taskCount: run.taskCount) } }
        let bandHeight = headings.compactMap { heading in heading.map(bandHeight) }.max() ?? 0
        let cardsTop = origin.y + (bandHeight > 0 ? bandHeight + UserJourneyGeometry.bandPadding : 0)
        let cardHeight = measured.textHeight + (actorIndices.isEmpty ? 0 : UserJourneyGeometry.dotRowHeight) + 2 * UserJourneyGeometry.cardPadding.height
        let chartTop = cardsTop + cardHeight + UserJourneyGeometry.faceRadius + UserJourneyGeometry.chartGap
        var body = UserJourneyPlacedBody(bottom: chartTop + UserJourneyGeometry.offset(ofLevel: UserJourneyTask.lowestLevel) + UserJourneyGeometry.faceRadius)
        for (run, heading) in zip(runs, headings) {
            guard let heading else { continue }
            let frame = CGRect(x: origin.x + CGFloat(run.firstTaskIndex) * measured.cardPitch, y: origin.y,
                               width: CGFloat(run.taskCount) * measured.cardPitch - UserJourneyGeometry.cardGap, height: bandHeight)
            body.sections.append(UserJourneyLayoutSection(frame: frame, text: Self.centered(heading, at: CGPoint(x: frame.midX, y: frame.midY))))
        }
        body.tasks = diagram.tasks.indices.map { index in
            placedTask(index, frame: CGRect(x: origin.x + CGFloat(index) * measured.cardPitch, y: cardsTop, width: measured.cardWidth, height: cardHeight),
                       chartTop: chartTop)
        }
        body.scaleLevels = scaleLevels(left: origin.x, chartTop: chartTop)
        if body.tasks.count > 1, let first = body.tasks.first {
            body.scoreLine = DiagramPath(start: first.faceCenter, segments: body.tasks.dropFirst().map { task in .line(to: task.faceCenter) })
        }
        return body
    }

    /// A band's heading, fitted within the band less a card's padding at each end.
    private func headingText(_ heading: DiagramLabel, taskCount: Int) -> DiagramTextBlock {
        let bandWidth = CGFloat(taskCount) * measured.cardPitch - UserJourneyGeometry.cardGap
        return TimelineTextFitting.fitted(heading, measurer: taskText, maximumWidth: bandWidth - 2 * UserJourneyGeometry.cardPadding.width)
    }

    private func bandHeight(_ heading: DiagramTextBlock) -> CGFloat {
        max(heading.size.height, taskText.lineHeight) + 2 * UserJourneyGeometry.bandPadding
    }

    /// The task at `index` with its card at `frame`: its text at the card's top, its actors' dots along its bottom,
    /// spread at most 13 points apart and closer to stay inside it, and its face on the scale.
    private func placedTask(_ index: Int, frame: CGRect, chartTop: CGFloat) -> UserJourneyLayoutTask {
        let task = diagram.tasks[index]
        let text = Self.centered(measured.taskTexts[index],
                                 at: CGPoint(x: frame.midX, y: frame.minY + UserJourneyGeometry.cardPadding.height + measured.textHeight / 2))
        let faceCenter = CGPoint(x: frame.midX, y: chartTop + UserJourneyGeometry.offset(ofLevel: task.level))
        let stem = DiagramPath(start: CGPoint(x: frame.midX, y: frame.maxY),
                               segments: [.line(to: CGPoint(x: frame.midX, y: faceCenter.y - UserJourneyGeometry.faceRadius))])
        let named = task.actors.filter { name in !name.isEmpty }
        let room = frame.width - 2 * UserJourneyGeometry.cardPadding.width - 2 * UserJourneyGeometry.dotRadius
        let spacing = min(UserJourneyGeometry.dotSpacing, room / CGFloat(max(named.count - 1, 1)))
        let dotsY = frame.maxY - UserJourneyGeometry.cardPadding.height - UserJourneyGeometry.dotRadius
        let dots = named.enumerated().map { position, name in
            UserJourneyActorDot(center: CGPoint(x: frame.midX + (CGFloat(position) - CGFloat(named.count - 1) / 2) * spacing, y: dotsY),
                                seriesIndex: actorIndices[name] ?? 0)
        }
        return UserJourneyLayoutTask(frame: frame, text: text, faceCenter: faceCenter, mood: task.mood, stem: stem, actorDots: dots)
    }

    /// A line across the chart at each level, from a little left of the first card to the last card's right edge,
    /// with the level's number to the left of it.
    private func scaleLevels(left: CGFloat, chartTop: CGFloat) -> [UserJourneyScaleLevel] {
        UserJourneyGeometry.levels.map { level in
            let y = chartTop + UserJourneyGeometry.offset(ofLevel: Double(level))
            let line = DiagramPath(start: CGPoint(x: left - UserJourneyGeometry.scaleLineOverhang, y: y),
                                   segments: [.line(to: CGPoint(x: left + measured.plotWidth, y: y))])
            let text = DiagramTextBlock(label: DiagramLabel(String(level)), measurer: scaleText, maximumWidth: UserJourneyGeometry.scaleGutter)
            let center = CGPoint(x: left - UserJourneyGeometry.scaleTextGap - text.size.width / 2, y: y)
            return UserJourneyScaleLevel(score: level, line: line, text: Self.centered(text, at: center))
        }
    }

    private static func centered(_ text: DiagramTextBlock, at center: CGPoint) -> DiagramTextBlock {
        var centered = text
        centered.center = center
        return centered
    }
}

/// What the placement makes: the bands, the tasks, the scale and the line through the faces, and how far down the
/// lowest face reaches.
struct UserJourneyPlacedBody {
    var sections: [UserJourneyLayoutSection] = []
    var tasks: [UserJourneyLayoutTask] = []
    var scaleLevels: [UserJourneyScaleLevel] = []
    var scoreLine: DiagramPath?
    var bottom: CGFloat
}
