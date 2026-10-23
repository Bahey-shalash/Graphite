import CoreGraphics

/// A user journey laid out on a page whose origin is the top left corner and whose y runs down, in points: the
/// title, the section bands over their tasks' cards, the scale below the cards with a face per task at its score, the
/// line from face to face, and the legend of actors. Drawing it needs only colors.
public struct UserJourneyLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the title was measured in, bold; the cards, bands and legend are in its size seven eighths, the
    /// scale's numbers three quarters.
    public let font: DiagramFont
    /// A band over each run of tasks written one after the other under sections of one name.
    public let sections: [UserJourneyLayoutSection]
    /// The tasks in the order they are written, left to right.
    public let tasks: [UserJourneyLayoutTask]
    /// The scale's levels from 5 at the top to 1 at the bottom; none without tasks.
    public let scaleLevels: [UserJourneyScaleLevel]
    /// The line from face to face, in the order the tasks are written; nil with fewer than two tasks.
    public let scoreLine: DiagramPath?
    /// One entry per actor, in `UserJourneyDiagram.actorNames`'s order, centered below the scale in rows.
    public let legend: [UserJourneyLegendEntry]
    /// The diagram's title above it, drawn bold, or nil.
    public let title: DiagramTextBlock?
}

/// The band over a run of tasks under one section, filled in the second surface, with its heading drawn bold.
public struct UserJourneyLayoutSection: Equatable, Sendable {
    public let frame: CGRect
    public let text: DiagramTextBlock
}

/// A task: its card with its text and its actors' dots, and its face on the scale with the dashed stem down to it.
public struct UserJourneyLayoutTask: Equatable, Sendable {
    /// The card, filled in the surface color and outlined in the border color.
    public let frame: CGRect
    public let text: DiagramTextBlock
    /// The center of the face, at the task's level on the scale.
    public let faceCenter: CGPoint
    public let mood: UserJourneyMood
    /// The dashed line from the card's bottom to the top of the face.
    public let stem: DiagramPath
    /// The dots of the actors named on the task, in the order they are written, along the card's bottom.
    public let actorDots: [UserJourneyActorDot]
}

/// An actor's dot, on a task's card or in the legend.
public struct UserJourneyActorDot: Equatable, Sendable {
    public let center: CGPoint
    /// The actor's place in `UserJourneyDiagram.actorNames`, which picks its series color.
    public let seriesIndex: Int
}

/// A level of the scale: the line across the chart at it and its number at the left.
public struct UserJourneyScaleLevel: Equatable, Sendable {
    public let score: Int
    public let line: DiagramPath
    public let text: DiagramTextBlock
}

/// A row of the legend: an actor's dot in its series color, then its name.
public struct UserJourneyLegendEntry: Equatable, Sendable {
    public let dot: UserJourneyActorDot
    public let text: DiagramTextBlock
}
