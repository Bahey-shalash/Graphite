/// A Mermaid Gantt chart (`gantt`) as its text describes it: its settings, its sections and its tasks in the order
/// they are written. Dates stay as written: what they mean depends on `dateFormat`, the other tasks and the day the
/// chart is drawn, and is worked out when the chart is scheduled.
public struct GanttChart: Equatable, Sendable {
    /// `title …`, else `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the chart, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?
    /// `dateFormat`, the format of the dates in tasks, in Mermaid's date library's tokens (`YYYY-MM-DD`); empty when
    /// the chart sets none.
    public internal(set) var dateFormat: String
    /// `axisFormat`, the format of the axis' dates in d3's specifiers (`%Y-%m-%d`); empty when the chart sets none.
    public internal(set) var axisFormat: String
    /// `inclusiveEndDates`: an end date written as a date includes that whole day.
    public internal(set) var isEndDateInclusive: Bool
    /// `topAxis`: the axis' dates are shown above the tasks too.
    public internal(set) var showsTopAxis: Bool
    /// `tickInterval`, where the axis' dates fall (`1week`, `2day`); empty when the chart sets none, and the axis then
    /// chooses them.
    public internal(set) var tickInterval: String
    /// `weekday …`: the day a week of `tickInterval` starts on.
    public internal(set) var weekStart: GanttWeekday
    /// `excludes …`: lowercased words, in the order first written: `weekends`, day names and dates.
    public internal(set) var excludedDays: [String]
    /// `includes …`: lowercased dates that are never excluded.
    public internal(set) var includedDays: [String]
    /// `weekend friday` or `weekend saturday`: the first day of the weekend `excludes weekends` leaves out.
    public internal(set) var weekendStart: GanttWeekendStart
    public internal(set) var todayMarker: GanttTodayMarker
    /// The `section …` names, in the order written.
    public internal(set) var sections: [String]
    public internal(set) var tasks: [GanttTask]
    /// Statements read that the chart is not drawn with yet, in the order first written.
    public internal(set) var statementsNotDrawn: [GanttStatementNotDrawn]

    init() {
        title = nil
        accessibilityTitle = nil
        accessibilityDescription = nil
        dateFormat = ""
        axisFormat = ""
        isEndDateInclusive = false
        showsTopAxis = false
        tickInterval = ""
        weekStart = .sunday
        excludedDays = []
        includedDays = []
        weekendStart = .saturday
        todayMarker = .standard
        sections = []
        tasks = []
        statementsNotDrawn = []
    }
}

/// One task: a row of the chart with a bar, or a milestone.
public struct GanttTask: Equatable, Sendable {
    /// Its text, as written before the colon, without the spaces at either end.
    public let name: String
    /// The section it is written under; empty before the first section.
    public let section: String
    /// Its identifier: the one written, else `task1`, `task2`… counting the tasks written without one.
    public let identifier: String
    public let isDone: Bool
    public let isActive: Bool
    public let isCritical: Bool
    public let isMilestone: Bool
    /// When it starts, as written (`2014-01-01`, `after a1 b2`); nil when it starts where the task before it ends.
    public let startText: String?
    /// When it ends, as written: a date, a duration (`3d`) or `until a1`.
    public let endText: String
    /// The identifier of the task written before it, whatever its section, or nil for the first task.
    public let previousTaskIdentifier: String?
}

/// The first day of the weekend that `excludes weekends` leaves out, with the day after it.
public enum GanttWeekendStart: Equatable, Sendable {
    case friday
    case saturday
}

/// A day of the week, numbered from Sunday as JavaScript numbers them.
public enum GanttWeekday: Int64, Equatable, Sendable, CaseIterable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday

    /// The day a lowercased English name names, or nil.
    init?(name: String) {
        guard let day = Self.allCases.first(where: { day in "\(day)" == name }) else { return nil }
        self = day
    }
}

/// `todayMarker`: whether a line marks today.
public enum GanttTodayMarker: Equatable, Sendable {
    /// No `todayMarker`: the line is drawn.
    case standard
    /// `todayMarker off`.
    case hidden
    /// `todayMarker` with CSS declarations for the line; they are read and not applied, and the standard line is drawn.
    case styled(String)
}

/// A statement of a Gantt chart that is read and not drawn yet. A chart with one is shown as its text: drawn without
/// it, it would look complete and be wrong.
public enum GanttStatementNotDrawn: Equatable, Sendable {
    /// `click`: a link or a script call on a task.
    case click
    /// A task tagged `vert`: a vertical line across the chart instead of a row.
    case verticalMarker
}
