/// A Mermaid timeline (`timeline`) as its text describes it: time periods in the order they are written, each with
/// its events, grouped under the sections written before them.
public struct TimelineDiagram: Equatable, Sendable {
    public internal(set) var direction: TimelineDirection
    /// `title …` in the diagram, else `title:` in the front matter, else nil.
    public internal(set) var title: String?
    /// The `section …` headings, in the order they are written.
    public internal(set) var sections: [DiagramLabel]
    public internal(set) var periods: [TimelinePeriod]
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?

    init(direction: TimelineDirection = .leftToRight, title: String? = nil, sections: [DiagramLabel] = [], periods: [TimelinePeriod] = [],
         accessibilityTitle: String? = nil, accessibilityDescription: String? = nil) {
        self.direction = direction
        self.title = title
        self.sections = sections
        self.periods = periods
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
    }
}

/// A time period of a timeline and the events that happened in it.
public struct TimelinePeriod: Equatable, Sendable {
    public let label: DiagramLabel
    /// The events, in the order they are written: after the period on its line (`2004 : Facebook : Google`) and on
    /// the lines that follow it (`     : Google`).
    public internal(set) var events: [DiagramLabel]
    /// The index in `TimelineDiagram.sections` of the section the period is written under, or nil for a period
    /// written before the first section.
    public let sectionIndex: Int?

    init(label: DiagramLabel, events: [DiagramLabel] = [], sectionIndex: Int?) {
        self.label = label
        self.events = events
        self.sectionIndex = sectionIndex
    }
}

/// The way a timeline runs.
public enum TimelineDirection: Equatable, Sendable, CaseIterable {
    /// `timeline` or `timeline LR`: periods side by side along an axis that runs right, their events below them.
    case leftToRight
    /// `timeline TD`: periods one below the other along an axis that runs down, their events beside them.
    case topToBottom
}
