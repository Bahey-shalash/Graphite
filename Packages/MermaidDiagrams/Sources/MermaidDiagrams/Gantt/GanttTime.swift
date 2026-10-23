/// A moment as the wall clock of the chart's time zone reads it: milliseconds since 1970-01-01 00:00 on that clock.
/// A Gantt chart is scheduled and drawn in it, as Mermaid's date library works in local time; a day is 24 hours on
/// it, also across a change to or from daylight saving time. Calendar arithmetic is done here in integers, so it is
/// the same on every device for the same text, time zone and day.
struct GanttTime: Comparable, Hashable, Sendable {
    var milliseconds: Int64

    static let millisecondsPerSecond: Int64 = 1_000
    static let millisecondsPerMinute: Int64 = 60_000
    static let millisecondsPerHour: Int64 = 3_600_000
    static let millisecondsPerDay: Int64 = 86_400_000
    /// The farthest a JavaScript date reaches from 1970 either way, in milliseconds: dates past it are invalid there.
    static let largestMilliseconds: Int64 = 8_640_000_000_000_000
    /// Beyond any year a JavaScript date reaches (275,760), so that the day count cannot overflow.
    private static let largestYear: Int64 = 300_000
    private static let daysPerFourHundredYears: Int64 = 146_097
    /// The days from 0000-03-01 to 1970-01-01, the origin of the civil date computation.
    private static let daysFromYearZeroMarchToEpoch: Int64 = 719_468

    init(milliseconds: Int64) {
        self.milliseconds = milliseconds
    }

    /// The moment at a date and time, each field allowed past its range as JavaScript's `Date` allows it (month 13 is
    /// January of the next year, day 0 the last day of the month before). Nil past what a date can hold.
    init?(year: Int64, month: Int64, day: Int64, hour: Int64 = 0, minute: Int64 = 0, second: Int64 = 0, millisecond: Int64 = 0) {
        let normalizedYear = year + Self.floorDivision(month - 1, 12)
        guard abs(normalizedYear) <= Self.largestYear else { return nil }
        let firstOfMonth = Self.dayNumber(year: normalizedYear, month: Self.modulo(month - 1, 12) + 1, day: 1)
        var total = firstOfMonth * Self.millisecondsPerDay
        let parts = [(day - 1, Self.millisecondsPerDay), (hour, Self.millisecondsPerHour), (minute, Self.millisecondsPerMinute),
                     (second, Self.millisecondsPerSecond), (millisecond, 1)]
        for (amount, unit) in parts {
            let (product, productOverflows) = amount.multipliedReportingOverflow(by: unit)
            let (sum, sumOverflows) = total.addingReportingOverflow(product)
            guard !productOverflows, !sumOverflows else { return nil }
            total = sum
        }
        guard abs(total) <= Self.largestMilliseconds else { return nil }
        milliseconds = total
    }

    static func < (left: GanttTime, right: GanttTime) -> Bool {
        left.milliseconds < right.milliseconds
    }

    /// Days since 1970-01-01, rounded down.
    var dayNumber: Int64 { Self.floorDivision(milliseconds, Self.millisecondsPerDay) }
    var millisecondOfDay: Int64 { Self.modulo(milliseconds, Self.millisecondsPerDay) }
    var date: (year: Int64, month: Int64, day: Int64) { Self.civilDate(dayNumber: dayNumber) }
    var year: Int64 { date.year }
    /// 1 for January to 12 for December.
    var month: Int64 { date.month }
    var day: Int64 { date.day }
    var hour: Int64 { millisecondOfDay / Self.millisecondsPerHour }
    var minute: Int64 { millisecondOfDay / Self.millisecondsPerMinute % 60 }
    var second: Int64 { millisecondOfDay / Self.millisecondsPerSecond % 60 }
    var millisecond: Int64 { millisecondOfDay % Self.millisecondsPerSecond }
    /// 0 for Sunday to 6 for Saturday; 1970-01-01 was a Thursday.
    var weekday: Int64 { Self.modulo(dayNumber + 4, 7) }
    /// 1 for Monday to 7 for Sunday.
    var isoWeekday: Int64 { weekday == 0 ? 7 : weekday }

    /// Midnight of the same day.
    var startOfDay: GanttTime { GanttTime(milliseconds: dayNumber * Self.millisecondsPerDay) }

    /// The same time `days` days later, or nil past what a date can hold.
    func addingDays(_ days: Int64) -> GanttTime? {
        adding(milliseconds: days, unit: Self.millisecondsPerDay)
    }

    /// `amount` of `unit` later, or nil past what a date can hold.
    func adding(milliseconds amount: Int64, unit: Int64) -> GanttTime? {
        let (product, productOverflows) = amount.multipliedReportingOverflow(by: unit)
        let (sum, sumOverflows) = milliseconds.addingReportingOverflow(product)
        guard !productOverflows, !sumOverflows, abs(sum) <= Self.largestMilliseconds else { return nil }
        return GanttTime(milliseconds: sum)
    }

    /// The same time `months` months later, on the same day of the month unless that month is shorter.
    func addingMonths(_ months: Int64) -> GanttTime? {
        let (year, month, day) = date
        let target = (month - 1) + months
        let targetYear = year + Self.floorDivision(target, 12)
        let targetMonth = Self.modulo(target, 12) + 1
        guard abs(targetYear) <= Self.largestYear else { return nil }
        let targetDay = min(day, Self.daysInMonth(year: targetYear, month: targetMonth))
        return GanttTime(year: targetYear, month: targetMonth, day: targetDay, millisecond: millisecondOfDay)
    }

    static func daysInMonth(year: Int64, month: Int64) -> Int64 {
        let nextMonth = month == 12 ? dayNumber(year: year + 1, month: 1, day: 1) : dayNumber(year: year, month: month + 1, day: 1)
        return nextMonth - dayNumber(year: year, month: month, day: 1)
    }

    /// Days from 1970-01-01 to a date of the proleptic Gregorian calendar (Howard Hinnant's algorithm).
    static func dayNumber(year: Int64, month: Int64, day: Int64) -> Int64 {
        let marchYear = month <= 2 ? year - 1 : year
        let era = floorDivision(marchYear, 400)
        let yearOfEra = marchYear - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * daysPerFourHundredYears + dayOfEra - daysFromYearZeroMarchToEpoch
    }

    /// The date `dayNumber` days after 1970-01-01.
    static func civilDate(dayNumber: Int64) -> (year: Int64, month: Int64, day: Int64) {
        let shifted = dayNumber + daysFromYearZeroMarchToEpoch
        let era = floorDivision(shifted, daysPerFourHundredYears)
        let dayOfEra = shifted - era * daysPerFourHundredYears
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthFromMarch = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthFromMarch + 2) / 5 + 1
        let month = monthFromMarch < 10 ? monthFromMarch + 3 : monthFromMarch - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    static func floorDivision(_ dividend: Int64, _ divisor: Int64) -> Int64 {
        let quotient = dividend / divisor
        return (dividend % divisor != 0 && (dividend < 0) != (divisor < 0)) ? quotient - 1 : quotient
    }

    static func modulo(_ dividend: Int64, _ divisor: Int64) -> Int64 {
        dividend - floorDivision(dividend, divisor) * divisor
    }
}
