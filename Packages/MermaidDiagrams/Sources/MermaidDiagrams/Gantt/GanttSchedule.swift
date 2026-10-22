import Foundation

/// When each task of a Gantt chart starts and ends, worked out as Mermaid's Gantt database does (`getTasks`): every
/// task is scheduled again on each pass, as a task may follow one written after it, up to eleven passes or until
/// every task has a start and an end. A task that waits on one that never gets them keeps neither.
struct GanttSchedule {
    struct Entry: Equatable {
        var start: GanttTime?
        var end: GanttTime?
        /// Where the bar ends when excluded days moved the task's end on, before the last excluded run; else nil.
        var drawnEnd: GanttTime?
        var isScheduled = false
        /// Whether the end is written as a date (`YYYY-MM-DD`), which excluded days do not move.
        var hasWrittenEnd = false
    }

    private(set) var entries: [Entry]
    private let chart: GanttChart
    private let today: GanttTime
    private let now: GanttTime
    private let zone: GanttTimeZone
    private let dateFormat: GanttDateFormat
    private let excludedDays: GanttExcludedDays
    /// The last task written with each identifier.
    private let taskIndexByIdentifier: [String: Int]
    private let maximumDayCount: Int
    private var steppedDayCount = 0

    /// The most passes over the tasks: Mermaid's eleven.
    static let maximumPassCount = 11
    /// How far excluded days may move a task's end before Mermaid gives up.
    static let maximumExcludedDayRun: Int64 = 10_000

    /// Schedules `chart` on the wall clock `now` reads in `zone`.
    init(chart: GanttChart, now: GanttTime, zone: GanttTimeZone, limits: MermaidDiagramLimits) throws(GanttLayoutError) {
        entries = Array(repeating: Entry(), count: chart.tasks.count)
        self.chart = chart
        self.now = now
        today = now.startOfDay
        self.zone = zone
        dateFormat = GanttDateFormat(chart.dateFormat)
        excludedDays = GanttExcludedDays(chart: chart, zone: zone)
        taskIndexByIdentifier = Dictionary(chart.tasks.enumerated().map { index, task in (task.identifier, index) }) { _, later in later }
        maximumDayCount = limits.maximumScheduledDayCount
        for _ in 0..<Self.maximumPassCount {
            var isEveryTaskScheduled = true
            for index in entries.indices {
                try schedule(taskAt: index)
                isEveryTaskScheduled = isEveryTaskScheduled && entries[index].isScheduled
            }
            if isEveryTaskScheduled { break }
        }
    }

    private mutating func schedule(taskAt index: Int) throws(GanttLayoutError) {
        let task = chart.tasks[index]
        if let startText = task.startText {
            if let start = try startTime(startText) { entries[index].start = start }
        } else {
            let previous = task.previousTaskIdentifier.flatMap { identifier in taskIndexByIdentifier[identifier] }
            entries[index].start = previous.map { previousIndex in entries[previousIndex].end } ?? today
        }
        guard let start = entries[index].start else { return }
        entries[index].end = endTime(after: start, endText: task.endText)
        guard entries[index].end != nil else { return }
        entries[index].isScheduled = true
        entries[index].hasWrittenEnd = GanttDateFormat.isoDate.parse(task.endText, now: now, zone: zone) != nil
        try moveEndPastExcludedDays(ofTaskAt: index)
    }

    /// A task's start: Unix time for the `x` and `X` formats, `after` the latest end of the tasks named, a date in
    /// `dateFormat`, or one of JavaScript's date forms read here. Nil while a task named has no end yet.
    private func startTime(_ text: String) throws(GanttLayoutError) -> GanttTime? {
        if ["x", "X"].contains(chart.dateFormat), let milliseconds = Int64(text), text.allSatisfy(\.isNumber) {
            guard let time = zone.wallClockTime(unixMilliseconds: milliseconds) else { throw .unreadableDate(text) }
            return time
        }
        if let identifiers = Self.references(after: "after", in: text) {
            let tasks = identifiers.compactMap { identifier in taskIndexByIdentifier[identifier] }
            guard let first = tasks.first else { return today }
            let latest = tasks.dropFirst().reduce(first) { latest, candidate in
                Self.isLater(entries[candidate].end, than: entries[latest].end) ? candidate : latest
            }
            return entries[latest].end
        }
        if let date = dateFormat.parse(text, now: now, zone: zone) ?? GanttFallbackDate.parse(text, zone: zone) { return date }
        throw .unreadableDate(text)
    }

    /// A task's end: `until` the earliest start of the tasks named, a date in `dateFormat` (the next day's start with
    /// `inclusiveEndDates`), or a duration after its start; a text that is none of these leaves the task no length.
    private func endTime(after start: GanttTime, endText: String) -> GanttTime? {
        if let identifiers = Self.references(after: "until", in: endText) {
            let tasks = identifiers.compactMap { identifier in taskIndexByIdentifier[identifier] }
            guard let first = tasks.first else { return today }
            let earliest = tasks.dropFirst().reduce(first) { earliest, candidate in
                Self.isLater(entries[earliest].start, than: entries[candidate].start) ? candidate : earliest
            }
            return entries[earliest].start
        }
        if let date = dateFormat.parse(endText, now: now, zone: zone) {
            return chart.isEndDateInclusive ? date.addingDays(1) ?? date : date
        }
        return GanttDuration(endText)?.added(to: start) ?? start
    }

    /// Moves the end of a task whose length is a duration one day on for every excluded day it covers.
    private mutating func moveEndPastExcludedDays(ofTaskAt index: Int) throws(GanttLayoutError) {
        guard !chart.excludedDays.isEmpty, !entries[index].hasWrittenEnd, let start = entries[index].start, var end = entries[index].end,
              var day = start.addingDays(1), let latestEnd = end.addingDays(Self.maximumExcludedDayRun) else { return }
        var isExcluded = false
        var drawnEnd: GanttTime?
        while day <= end {
            steppedDayCount += 1
            guard steppedDayCount <= maximumDayCount else { throw .tooManyScheduledDays(limit: maximumDayCount) }
            if !isExcluded { drawnEnd = end }
            isExcluded = excludedDays.isExcluded(day)
            if isExcluded {
                guard let movedEnd = end.addingDays(1), movedEnd <= latestEnd else { throw .noDayLeftAfterExclusions(task: chart.tasks[index].name) }
                end = movedEnd
            }
            guard let nextDay = day.addingDays(1) else { break }
            day = nextDay
        }
        entries[index].end = end
        entries[index].drawnEnd = drawnEnd
    }

    /// The identifiers after `keyword` and spaces (`after a1 b2`): letters, digits, `_`, `-` and spaces, then
    /// anything; nil when the text does not start so.
    static func references(after keyword: String, in text: String) -> [String]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(keyword) else { return nil }
        let rest = trimmed.dropFirst(keyword.count)
        guard let first = rest.first, first.isWhitespace else { return nil }
        let identifiers = rest.drop { character in character.isWhitespace }
            .prefix { character in character.isASCII && (character.isLetter || character.isNumber || "_- ".contains(character)) }
        guard !identifiers.isEmpty else { return nil }
        return identifiers.split(separator: " ").map(String.init)
    }

    /// `left > right` as JavaScript compares two dates that may be missing: false when either is.
    private static func isLater(_ left: GanttTime?, than right: GanttTime?) -> Bool {
        guard let left, let right else { return false }
        return left > right
    }
}
