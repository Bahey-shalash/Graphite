/// A Mermaid user journey (`journey`) as its text describes it: tasks in the order they are written, each with its
/// score and the actors who take part in it, under the sections written before them.
public struct UserJourneyDiagram: Equatable, Sendable {
    /// `title …` in the diagram, else `title:` in the front matter, else nil.
    public internal(set) var title: String?
    /// The `section …` headings, in the order they are written.
    public internal(set) var sections: [DiagramLabel]
    public internal(set) var tasks: [UserJourneyTask]
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?

    init(title: String? = nil, sections: [DiagramLabel] = [], tasks: [UserJourneyTask] = [], accessibilityTitle: String? = nil,
         accessibilityDescription: String? = nil) {
        self.title = title
        self.sections = sections
        self.tasks = tasks
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
    }

    /// Everyone named on a task, once each, in the order of their names' UTF-16 code units, as Mermaid sorts them:
    /// an actor's place in this list picks its series color. A nameless actor (`Task: 5:`) is left out, as Pele draws
    /// none.
    public var actorNames: [String] {
        let names = Set(tasks.flatMap(\.actors)).subtracting([""])
        return names.sorted { first, second in first.utf16.lexicographicallyPrecedes(second.utf16) }
    }
}

/// A step of a user journey: what the user does, how it felt, and who takes part.
public struct UserJourneyTask: Equatable, Sendable {
    public let label: DiagramLabel
    /// The score as written, read as JavaScript's `Number` reads it, as Mermaid does: any number, unbounded, or nil
    /// when it is not one (`Task: x`).
    public let score: Double?
    /// The actors written after the score, separated by commas, each without the spaces at its ends: an empty name
    /// is kept, as in Mermaid (`Task: 5:` names one actor without a name).
    public let actors: [String]
    /// The index in `UserJourneyDiagram.sections` of the section the task is written under, or nil for a task
    /// written before the first section.
    public let sectionIndex: Int?

    /// The lowest and highest places on a user journey's scale, and the middle a task without a score takes.
    public static let lowestLevel = 1.0
    public static let highestLevel = 5.0
    public static let middleLevel = 3.0

    init(label: DiagramLabel, score: Double?, actors: [String], sectionIndex: Int?) {
        self.label = label
        self.score = score
        self.actors = actors
        self.sectionIndex = sectionIndex
    }

    /// Where the task's face sits on the scale from 1 to 5: its score kept within the scale, or the middle without one.
    public var level: Double {
        guard let score else { return Self.middleLevel }
        return min(Self.highestLevel, max(Self.lowestLevel, score))
    }

    /// The face the task's score shows: happy above the middle, sad below it, neutral at it or without a score.
    public var mood: UserJourneyMood {
        guard let score else { return .neutral }
        if score > Self.middleLevel { return .happy }
        return score < Self.middleLevel ? .sad : .neutral
    }
}

/// The face a task's score shows, as Pele draws it.
public enum UserJourneyMood: Equatable, Sendable, CaseIterable {
    case happy
    case neutral
    case sad
}
