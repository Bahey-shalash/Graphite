/// ISO 8601 weeks, which start on Monday; the first week of a year is the one with its first Thursday.
enum GanttIsoWeek {
    private static let thursday: Int64 = 4
    private static let daysPerWeek: Int64 = 7

    /// The Thursday of the week `time` is in, which decides the week's year.
    static func thursday(of time: GanttTime) -> GanttTime {
        GanttTime(milliseconds: time.milliseconds + (thursday - time.isoWeekday) * GanttTime.millisecondsPerDay)
    }

    /// The number of the week `time` is in, from 1.
    static func number(of time: GanttTime) -> Int64 {
        let weekThursday = thursday(of: time)
        let januaryFirst = GanttTime.dayNumber(year: weekThursday.year, month: 1, day: 1)
        let januaryFirstWeekday = GanttTime(milliseconds: januaryFirst * GanttTime.millisecondsPerDay).isoWeekday
        let firstThursday = januaryFirst + thursday - januaryFirstWeekday + (januaryFirstWeekday > thursday ? daysPerWeek : 0)
        return GanttTime.floorDivision(weekThursday.dayNumber - firstThursday, daysPerWeek) + 1
    }
}
