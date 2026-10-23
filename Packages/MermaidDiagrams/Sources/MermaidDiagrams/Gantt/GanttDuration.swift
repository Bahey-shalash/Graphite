import Foundation

/// A task's length written as a number and a unit (`3d`, `1.5h`, `20ms`), added to its start as Mermaid's date
/// library adds it: days and weeks rounded to whole days on the calendar, months and years whole and keeping the day
/// of the month where it exists, smaller units exactly.
struct GanttDuration: Equatable {
    enum Unit: Equatable {
        case milliseconds, seconds, minutes, hours, days, weeks, months, years
    }

    let amount: Double
    let unit: Unit

    init(amount: Double, unit: Unit) {
        self.amount = amount
        self.unit = unit
    }

    /// The duration a task's end text writes (`^\d+(\.\d+)?(ms|[Mdhmswy])$`, spaces around allowed), or nil.
    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let unitText = trimmed.hasSuffix("ms") ? "ms" : String(trimmed.suffix(1))
        let number = trimmed.dropLast(unitText.count)
        guard let unit = Self.units[unitText], Self.isDecimalNumber(number), let amount = Double(number) else { return nil }
        self.amount = amount
        self.unit = unit
    }

    private static let units: [String: Unit] = [
        "ms": .milliseconds, "s": .seconds, "m": .minutes, "h": .hours, "d": .days, "w": .weeks, "M": .months, "y": .years,
    ]

    /// Digits, then optionally a point and more digits.
    private static func isDecimalNumber(_ text: Substring) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count) else { return false }
        return parts.allSatisfy { part in !part.isEmpty && part.allSatisfy { character in character.isASCII && character.isNumber } }
    }

    /// `time` moved on by the duration, or nil when that is past what a date can hold.
    func added(to time: GanttTime) -> GanttTime? {
        switch unit {
        case .months: return Self.wholeAmount(amount).flatMap { months in time.addingMonths(months) }
        case .years: return Self.wholeAmount(amount).flatMap { years in time.addingMonths(years * 12) }
        case .days: return Self.roundedAmount(amount).flatMap { days in time.addingDays(days) }
        case .weeks: return Self.roundedAmount(7 * amount).flatMap { days in time.addingDays(days) }
        case .hours: return Self.adding(amount * Double(GanttTime.millisecondsPerHour), to: time)
        case .minutes: return Self.adding(amount * Double(GanttTime.millisecondsPerMinute), to: time)
        case .seconds: return Self.adding(amount * Double(GanttTime.millisecondsPerSecond), to: time)
        case .milliseconds: return Self.adding(amount, to: time)
        }
    }

    /// The whole part, as JavaScript's `setMonth` and `setFullYear` take it.
    private static func wholeAmount(_ amount: Double) -> Int64? {
        let whole = amount.rounded(.towardZero)
        return whole.magnitude < Double(GanttTime.largestMilliseconds) ? Int64(whole) : nil
    }

    /// Rounded to the nearest whole number, a half up, as JavaScript's `Math.round`.
    private static func roundedAmount(_ amount: Double) -> Int64? {
        let rounded = (amount + 0.5).rounded(.down)
        return rounded.magnitude < Double(GanttTime.largestMilliseconds) ? Int64(rounded) : nil
    }

    /// `milliseconds` added, its fraction dropped as a JavaScript date drops it.
    private static func adding(_ milliseconds: Double, to time: GanttTime) -> GanttTime? {
        let whole = (Double(time.milliseconds) + milliseconds).rounded(.towardZero)
        guard whole.magnitude <= Double(GanttTime.largestMilliseconds) else { return nil }
        return GanttTime(milliseconds: Int64(whole))
    }
}
