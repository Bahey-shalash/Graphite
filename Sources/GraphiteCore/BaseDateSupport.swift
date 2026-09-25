import Foundation

/// Parses the date strings Obsidian accepts: `YYYY-MM-DD`, optionally followed by a
/// time (`HH:mm`, `HH:mm:ss`, fractional seconds) after a space or `T`, optionally with
/// a `Z` or `±HH:mm` offset after the time. Values without an offset are local wall-clock
/// times. Text that JavaScript's `Date` rejects, such as `12:75` or `2025-01-01Z`, is not a date.
public enum BaseDateParsing {
    private static let datePattern = try? NSRegularExpression(pattern:
        "^(\\d{4})-(\\d{1,2})-(\\d{1,2})(?:[T ](\\d{1,2}):(\\d{2})(?::(\\d{2})(?:\\.(\\d+))?)?)?\\s*(Z|[+-]\\d{2}:?\\d{2})?$")

    public static func date(from text: String, calendar: Calendar) -> BaseDate? {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        let foundationText = trimmedText as NSString
        guard let match = datePattern?.firstMatch(in: trimmedText, range: NSRange(location: 0, length: foundationText.length)) else { return nil }
        func component(_ groupIndex: Int) -> String? {
            let range = match.range(at: groupIndex)
            return range.location == NSNotFound ? nil : foundationText.substring(with: range)
        }
        guard let year = component(1).flatMap(Int.init), let month = component(2).flatMap(Int.init), let day = component(3).flatMap(Int.init),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents(year: year, month: month, day: day)
        let hasTime = component(4) != nil
        let offsetText = component(8)
        // Obsidian reads an offset only after a time. A date-only value sits at midnight
        // in the device zone, so midnight in another zone would show as a different day.
        if offsetText != nil, !hasTime { return nil }
        if hasTime {
            guard let hour = component(4).flatMap(Int.init), let minute = component(5).flatMap(Int.init) else { return nil }
            let second = component(6).flatMap(Int.init) ?? 0
            // Calendar.date(from:) would roll 12:75 over to 13:15; JavaScript rejects it.
            guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }
            components.hour = hour
            components.minute = minute
            components.second = second
            if let fraction = component(7) {
                let milliseconds = Int(fraction.prefix(3).padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0
                components.nanosecond = milliseconds * 1_000_000
            }
        }
        var parsingCalendar = calendar
        var offsetSeconds = 0
        if let offsetText {
            guard let writtenOffsetSeconds = Self.offsetSeconds(from: offsetText) else { return nil }
            // The offset is applied arithmetically: TimeZone(secondsFromGMT:) rejects
            // offsets beyond ±18 hours, which ISO 8601 and JavaScript accept.
            parsingCalendar.timeZone = .gmt
            offsetSeconds = writtenOffsetSeconds
        }
        guard let wallClockDate = parsingCalendar.date(from: components),
              parsingCalendar.component(.day, from: wallClockDate) == day else { return nil }
        return BaseDate(date: wallClockDate.addingTimeInterval(-Double(offsetSeconds)), hasTime: hasTime)
    }

    /// Seconds east of UTC for `Z`, `±HH:mm` or `±HHmm`; nil when the hours or minutes
    /// are out of range.
    private static func offsetSeconds(from text: String) -> Int? {
        if text == "Z" { return 0 }
        let sign = text.hasPrefix("-") ? -1 : 1
        let digits = text.dropFirst().replacingOccurrences(of: ":", with: "")
        guard digits.count == 4, let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)),
              (0...23).contains(hours), (0...59).contains(minutes) else { return nil }
        return sign * (hours * 3600 + minutes * 60)
    }
}

/// Parses duration strings such as `1 day`, `7d`, `1M`, `2h 30m` or ISO 8601 `P1DT2H`.
public enum BaseDurationParsing {
    private static let partPattern = try? NSRegularExpression(pattern: "\\s*([+-]?\\d+(?:\\.\\d+)?)\\s*([A-Za-z]+)\\s*,?")
    private static let isoPattern = try? NSRegularExpression(pattern:
        "^([+-])?P(?:(\\d+(?:\\.\\d+)?)Y)?(?:(\\d+(?:\\.\\d+)?)M)?(?:(\\d+(?:\\.\\d+)?)W)?(?:(\\d+(?:\\.\\d+)?)D)?(?:(T)(?:(\\d+(?:\\.\\d+)?)H)?(?:(\\d+(?:\\.\\d+)?)M)?(?:(\\d+(?:\\.\\d+)?)S)?)?$")

    private enum Unit {
        case year, month, week, day, hour, minute, second, millisecond
    }

    /// moment.js units: `M` is a month and `m` a minute; longer names ignore case.
    private static func unit(named name: String) -> Unit? {
        switch name {
        case "y": return .year
        case "M": return .month
        case "w": return .week
        case "d": return .day
        case "h": return .hour
        case "m": return .minute
        case "s": return .second
        case "ms": return .millisecond
        default: break
        }
        switch name.lowercased() {
        case "yr", "yrs", "year", "years": return .year
        case "mo", "month", "months": return .month
        case "wk", "wks", "week", "weeks": return .week
        case "day", "days": return .day
        case "hr", "hrs", "hour", "hours": return .hour
        case "min", "mins", "minute", "minutes": return .minute
        case "sec", "secs", "second", "seconds": return .second
        case "millisecond", "milliseconds": return .millisecond
        default: return nil
        }
    }

    public static func duration(from text: String) -> BaseDuration? {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        guard !trimmedText.isEmpty else { return nil }
        if trimmedText.uppercased().hasPrefix("P") || trimmedText.uppercased().hasPrefix("-P") || trimmedText.uppercased().hasPrefix("+P") {
            return isoDuration(from: trimmedText.uppercased())
        }
        let foundationText = trimmedText as NSString
        var duration = BaseDuration()
        var consumedLength = 0
        guard let matches = partPattern?.matches(in: trimmedText, range: NSRange(location: 0, length: foundationText.length)), !matches.isEmpty else { return nil }
        for match in matches {
            // Parts must be contiguous; anything in between makes the text not a duration.
            guard match.range.location == consumedLength,
                  let amount = Double(foundationText.substring(with: match.range(at: 1))),
                  let unit = unit(named: foundationText.substring(with: match.range(at: 2))) else { return nil }
            consumedLength = NSMaxRange(match.range)
            duration = duration.adding(Self.duration(amount: amount, unit: unit))
        }
        return consumedLength == foundationText.length ? duration : nil
    }

    private static func duration(amount: Double, unit: Unit) -> BaseDuration {
        let isWhole = amount.rounded() == amount && abs(amount) < 1e9
        switch unit {
        case .year: return isWhole ? BaseDuration(months: Int(amount) * 12) : BaseDuration(milliseconds: amount * 365.2425 * BaseDuration.millisecondsPerDay)
        case .month: return isWhole ? BaseDuration(months: Int(amount)) : BaseDuration(milliseconds: amount * BaseDuration.averageDaysPerMonth * BaseDuration.millisecondsPerDay)
        case .week: return isWhole ? BaseDuration(days: Int(amount) * 7) : BaseDuration(milliseconds: amount * 7 * BaseDuration.millisecondsPerDay)
        case .day: return isWhole ? BaseDuration(days: Int(amount)) : BaseDuration(milliseconds: amount * BaseDuration.millisecondsPerDay)
        case .hour: return BaseDuration(milliseconds: amount * 3_600_000)
        case .minute: return BaseDuration(milliseconds: amount * 60_000)
        case .second: return BaseDuration(milliseconds: amount * 1_000)
        case .millisecond: return BaseDuration(milliseconds: amount)
        }
    }

    private static func isoDuration(from text: String) -> BaseDuration? {
        let foundationText = text as NSString
        guard let match = isoPattern?.firstMatch(in: text, range: NSRange(location: 0, length: foundationText.length)) else { return nil }
        func isPresent(_ groupIndex: Int) -> Bool { match.range(at: groupIndex).location != NSNotFound }
        func amount(_ groupIndex: Int) -> Double {
            isPresent(groupIndex) ? Double(foundationText.substring(with: match.range(at: groupIndex))) ?? 0 : 0
        }
        // ISO 8601 needs at least one element, and a `T` must introduce at least one time
        // element: `P`, `PT` and `P1DT` are not durations (a zero one is `PT0S`).
        let dateElementGroups = [2, 3, 4, 5], timeElementGroups = [7, 8, 9]
        let hasTimeElement = timeElementGroups.contains(where: isPresent)
        guard dateElementGroups.contains(where: isPresent) || hasTimeElement, isPresent(6) == hasTimeElement else { return nil }
        var duration = BaseDuration()
        duration = duration.adding(Self.duration(amount: amount(2), unit: .year))
        duration = duration.adding(Self.duration(amount: amount(3), unit: .month))
        duration = duration.adding(Self.duration(amount: amount(4), unit: .week))
        duration = duration.adding(Self.duration(amount: amount(5), unit: .day))
        duration = duration.adding(Self.duration(amount: amount(7), unit: .hour))
        duration = duration.adding(Self.duration(amount: amount(8), unit: .minute))
        duration = duration.adding(Self.duration(amount: amount(9), unit: .second))
        let isNegative = isPresent(1) && foundationText.substring(with: match.range(at: 1)) == "-"
        return isNegative ? duration.negated() : duration
    }
}

/// Date arithmetic as Obsidian's Bases performs it: every part of the duration moves the
/// local wall-clock time, the way JavaScript's `setMonth`, `setDate` and `setHours` do.
/// A month or year past the end of the shorter month overflows into the next one
/// (January 31 + 1 month is March 3 in 2025), and `+ "24h"` across a daylight-saving
/// change lands on the same wall-clock time the next day.
public enum BaseDateArithmetic {
    public static func adding(_ duration: BaseDuration, to date: BaseDate, calendar: Calendar) -> BaseDate {
        let addsTimeOfDay = duration.milliseconds.truncatingRemainder(dividingBy: BaseDuration.millisecondsPerDay) != 0
        let hasTime = date.hasTime || addsTimeOfDay
        guard !duration.isZero else { return BaseDate(date: date.date, hasTime: hasTime) }
        // Durations come from formulas; beyond the calendar's range, or with a number that is
        // not finite, the exact total length is the only meaningful answer left.
        let resultDate = wallClockSum(of: duration, and: date.date, calendar: calendar)
            ?? date.date.addingTimeInterval(duration.totalMilliseconds / 1_000)
        return BaseDate(date: resultDate, hasTime: hasTime)
    }

    public static func startOfDay(_ date: BaseDate, calendar: Calendar) -> BaseDate {
        BaseDate(date: calendar.startOfDay(for: date.date), hasTime: false)
    }

    /// Adds the duration to the local wall-clock reading of `date`, held as if it were a
    /// UTC instant so that no daylight-saving change interferes, then reads the sum back
    /// as local time. Nil when a part does not fit the calendar.
    private static func wallClockSum(of duration: BaseDuration, and date: Date, calendar: Calendar) -> Date? {
        guard duration.milliseconds.isFinite, date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        var wallClockCalendar = calendar
        wallClockCalendar.timeZone = .gmt
        let originalOffsetSeconds = calendar.timeZone.secondsFromGMT(for: date)
        var wallClock = date.addingTimeInterval(Double(originalOffsetSeconds))
        if duration.months != 0 {
            var dayComponents = wallClockCalendar.dateComponents([.era, .year, .month, .day], from: wallClock)
            let timeOfDay = wallClock.timeIntervalSince(wallClockCalendar.startOfDay(for: wallClock))
            guard let month = dayComponents.month else { return nil }
            let shiftedMonth = month.addingReportingOverflow(duration.months)
            guard !shiftedMonth.overflow else { return nil }
            // Calendar.date(from:) normalizes February 31 to March 3, as JavaScript does.
            dayComponents.month = shiftedMonth.partialValue
            guard let shiftedDay = wallClockCalendar.date(from: dayComponents) else { return nil }
            wallClock = shiftedDay.addingTimeInterval(timeOfDay)
        }
        wallClock = wallClock.addingTimeInterval(Double(duration.days) * 86_400 + duration.milliseconds / 1_000)
        // Calendar resolves the local reading the way JavaScript does: a time skipped by a
        // daylight-saving change moves forward, and a repeated one takes the first occurrence.
        // Keeping the original offset instead would pick the second occurrence when the sum
        // starts in standard time and lands in the repeated hour.
        let wholeSecondComponents = wallClockCalendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: wallClock)
        guard let wholeSecondWallClock = wallClockCalendar.date(from: wholeSecondComponents),
              let wholeSecondLocalDate = calendar.date(from: wholeSecondComponents) else { return nil }
        return wholeSecondLocalDate.addingTimeInterval(wallClock.timeIntervalSince(wholeSecondWallClock))
    }
}

/// moment.js-compatible formatting for `date.format()`, plus the default text for
/// dates, durations and relative times.
///
/// Text follows moment's default English locale, the language Obsidian uses unless its
/// interface is switched to another one and the one Graphite's templates write, so a
/// formula gives the same text on every device. Mixing the device's month names with
/// moment's English ordinals and AM/PM gave text in two languages at once.
public enum BaseDateFormatting {
    /// Gregorian calendar in the device time zone, for display outside an evaluation.
    public static var displayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// Obsidian's `toString()` for dates: `YYYY-MM-DD`, or `YYYY-MM-DDTHH:mm:ss` with a
    /// time. Group keys and the Unique summary compare this text, so it keeps the seconds.
    public static func defaultText(for date: BaseDate, calendar: Calendar) -> String {
        format(date.date, pattern: date.hasTime ? "YYYY-MM-DD[T]HH:mm:ss" : "YYYY-MM-DD", calendar: calendar)
    }

    private static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// Tokens are matched longest first; text inside `[brackets]` is copied literally.
    private static let tokens = [
        "YYYYYY", "YYYYY", "YYYY", "YY", "Y", "Qo", "Q", "MMMM", "MMM", "Mo", "MM", "M", "DDDD", "DDDo", "DDD", "Do", "DD", "D",
        "dddd", "ddd", "do", "dd", "d", "E", "e", "WW", "Wo", "W", "ww", "wo", "w", "GGGGG", "GGGG", "GG", "ggggg", "gggg", "gg",
        "HH", "H", "hh", "h", "kk", "k", "mm", "m", "ss", "s", "SSS", "SS", "S", "A", "a", "ZZ", "Z", "X", "x",
    ]

    /// moment's English long date formats, longest first. moment expands them before
    /// reading the other tokens.
    private static let longDateFormats: [(token: String, expansion: String)] = [
        ("LTS", "h:mm:ss A"), ("LT", "h:mm A"),
        ("LLLL", "dddd, MMMM D, YYYY h:mm A"), ("LLL", "MMMM D, YYYY h:mm A"), ("LL", "MMMM D, YYYY"), ("L", "MM/DD/YYYY"),
        ("llll", "ddd, MMM D, YYYY h:mm A"), ("lll", "MMM D, YYYY h:mm A"), ("ll", "MMM D, YYYY"), ("l", "M/D/YYYY"),
    ]

    /// Tokens grouped by their first character, keeping the longest-first order, so each
    /// character of a pattern is compared with a few tokens instead of all of them.
    private static let tokensByFirstCharacter = Dictionary(grouping: tokens) { token in token.first }
    private static let longDateFormatsByFirstCharacter = Dictionary(grouping: longDateFormats) { longDateFormat in longDateFormat.token.first }

    public static func format(_ date: Date, pattern: String, calendar: Calendar) -> String {
        let fields = MomentDateFields(date: date, calendar: calendar)
        var output = ""
        append(pattern, formattedWith: fields, to: &output)
        return output
    }

    private static func append(_ pattern: String, formattedWith fields: MomentDateFields, to output: inout String) {
        var remaining = Substring(pattern)
        while let first = remaining.first {
            if first == "[" {
                if let closing = remaining.firstIndex(of: "]") {
                    output += remaining[remaining.index(after: remaining.startIndex)..<closing]
                    remaining = remaining[remaining.index(after: closing)...]
                    continue
                }
            }
            if let longDateFormat = longDateFormatsByFirstCharacter[first]?.first(where: { longDateFormat in remaining.hasPrefix(longDateFormat.token) }) {
                append(longDateFormat.expansion, formattedWith: fields, to: &output)
                remaining = remaining.dropFirst(longDateFormat.token.count)
            } else if let token = tokensByFirstCharacter[first]?.first(where: { token in remaining.hasPrefix(token) }) {
                output += text(for: token, fields: fields)
                remaining = remaining.dropFirst(token.count)
            } else {
                output.append(first)
                remaining = remaining.dropFirst()
            }
        }
    }

    private static func text(for token: String, fields: MomentDateFields) -> String {
        let year = fields.year, month = fields.month, day = fields.day, hour = fields.hour
        let weekdayIndex = fields.weekdayIndex
        let twelveHour = hour % 12 == 0 ? 12 : hour % 12
        switch token {
        case "YYYYYY": return (year < 0 ? "-" : "+") + padded(abs(year), 6)
        case "YYYYY": return padded(year, 5)
        case "YYYY": return padded(year, 4)
        case "YY": return padded(year % 100, 2)
        case "Y": return year <= 9999 ? padded(year, 4) : "+" + String(year)
        case "Q": return String((month - 1) / 3 + 1)
        case "Qo": return ordinal((month - 1) / 3 + 1)
        case "MMMM": return monthNames[month - 1]
        case "MMM": return String(monthNames[month - 1].prefix(3))
        case "Mo": return ordinal(month)
        case "MM": return padded(month, 2)
        case "M": return String(month)
        case "DDDD": return padded(fields.dayOfYear, 3)
        case "DDDo": return ordinal(fields.dayOfYear)
        case "DDD": return String(fields.dayOfYear)
        case "Do": return ordinal(day)
        case "DD": return padded(day, 2)
        case "D": return String(day)
        case "dddd": return weekdayNames[weekdayIndex]
        case "ddd": return String(weekdayNames[weekdayIndex].prefix(3))
        case "dd": return String(weekdayNames[weekdayIndex].prefix(2))
        case "do": return ordinal(weekdayIndex)
        case "d", "e": return String(weekdayIndex)
        case "E": return String(weekdayIndex == 0 ? 7 : weekdayIndex)
        case "WW": return padded(fields.isoWeek.week, 2)
        case "Wo": return ordinal(fields.isoWeek.week)
        case "W": return String(fields.isoWeek.week)
        case "ww": return padded(fields.localeWeek.week, 2)
        case "wo": return ordinal(fields.localeWeek.week)
        case "w": return String(fields.localeWeek.week)
        case "GGGGG": return padded(fields.isoWeek.year, 5)
        case "GGGG": return padded(fields.isoWeek.year, 4)
        case "GG": return padded(fields.isoWeek.year % 100, 2)
        case "ggggg": return padded(fields.localeWeek.year, 5)
        case "gggg": return padded(fields.localeWeek.year, 4)
        case "gg": return padded(fields.localeWeek.year % 100, 2)
        case "HH": return padded(hour, 2)
        case "H": return String(hour)
        case "hh": return padded(twelveHour, 2)
        case "h": return String(twelveHour)
        case "kk": return padded(hour == 0 ? 24 : hour, 2)
        case "k": return String(hour == 0 ? 24 : hour)
        case "mm": return padded(fields.minute, 2)
        case "m": return String(fields.minute)
        case "ss": return padded(fields.second, 2)
        case "s": return String(fields.second)
        case "SSS": return padded(fields.millisecond, 3)
        case "SS": return padded(fields.millisecond / 10, 2)
        case "S": return String(fields.millisecond / 100)
        case "A": return hour < 12 ? "AM" : "PM"
        case "a": return hour < 12 ? "am" : "pm"
        case "ZZ": return offset(fields.offsetSeconds, separator: "")
        case "Z": return offset(fields.offsetSeconds, separator: ":")
        // A date moved by a huge duration lies beyond Int's range; clamp instead of trapping.
        case "X": return String(Int(clampingWholePartOf: (fields.millisecondsSince1970 / 1_000).rounded(.down)) ?? 0)
        case "x": return String(Int(clampingWholePartOf: fields.millisecondsSince1970) ?? 0)
        default: return token
        }
    }

    private static func padded(_ number: Int, _ width: Int) -> String {
        let digits = String(number.magnitude)
        return (number < 0 ? "-" : "") + String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    private static func offset(_ offsetSeconds: Int, separator: String) -> String {
        let totalMinutes = abs(offsetSeconds) / 60
        return (offsetSeconds < 0 ? "-" : "+") + padded(totalMinutes / 60, 2) + separator + padded(totalMinutes % 60, 2)
    }

    /// English ordinals, as moment's default locale writes them.
    static func ordinal(_ number: Int) -> String {
        let lastTwoDigits = abs(number) % 100
        let suffix: String
        if (11...13).contains(lastTwoDigits) { suffix = "th" }
        else {
            switch abs(number) % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(number)\(suffix)"
    }

    /// moment.js `fromNow()` wording and thresholds, for `date.relative()`. moment rounds
    /// each unit first and compares the rounded numbers, so 44.7 minutes is "an hour".
    public static func relativeText(from date: Date, to now: Date) -> String {
        let elapsedSeconds = now.timeIntervalSince(date)
        guard !elapsedSeconds.isNaN else { return "Invalid date" }
        let isPast = elapsedSeconds >= 0
        let exactSeconds = abs(elapsedSeconds)
        let exactDays = exactSeconds / 86_400
        let seconds = exactSeconds.rounded(), minutes = (exactSeconds / 60).rounded(), hours = (exactSeconds / 3_600).rounded()
        let days = exactDays.rounded(), months = (exactDays / BaseDuration.averageDaysPerMonth).rounded(), years = (exactDays / 365.2425).rounded()
        // A date moved by a huge duration can lie beyond Int's range, or be infinite.
        func count(_ amount: Double) -> Int { Int(clampingWholePartOf: amount) ?? 0 }
        let phrase: String
        if seconds <= 44 { phrase = "a few seconds" }
        else if minutes <= 1 { phrase = "a minute" }
        else if minutes < 45 { phrase = "\(count(minutes)) minutes" }
        else if hours <= 1 { phrase = "an hour" }
        else if hours < 22 { phrase = "\(count(hours)) hours" }
        else if days <= 1 { phrase = "a day" }
        else if days < 26 { phrase = "\(count(days)) days" }
        else if months <= 1 { phrase = "a month" }
        else if months < 11 { phrase = "\(count(months)) months" }
        else if years <= 1 { phrase = "a year" }
        else { phrase = "\(count(years)) years" }
        return isPast ? "\(phrase) ago" : "in \(phrase)"
    }

    /// Readable duration text, for example `2 days 3 hours` or `1.5 seconds`.
    public static func text(for duration: BaseDuration) -> String {
        var parts: [String] = []
        func append(_ amount: Int, _ singular: String) {
            guard amount != 0 else { return }
            parts.append("\(amount) \(singular)\(abs(amount) == 1 ? "" : "s")")
        }
        append(duration.months / 12, "year")
        append(duration.months % 12, "month")
        // Durations come from formulas and notes (`1e300 ms`), so each whole amount is
        // clamped instead of trapping, and adding the days saturates instead of overflowing.
        var remainingMilliseconds = duration.milliseconds
        let wholeDays = Int(clampingWholePartOf: remainingMilliseconds / BaseDuration.millisecondsPerDay) ?? 0
        let totalDays = duration.days.addingReportingOverflow(wholeDays)
        append(totalDays.overflow ? (wholeDays > 0 ? .max : -.max) : totalDays.partialValue, "day")
        remainingMilliseconds -= Double(wholeDays) * BaseDuration.millisecondsPerDay
        let wholeHours = Int(clampingWholePartOf: remainingMilliseconds / 3_600_000) ?? 0
        append(wholeHours, "hour")
        remainingMilliseconds -= Double(wholeHours) * 3_600_000
        let wholeMinutes = Int(clampingWholePartOf: remainingMilliseconds / 60_000) ?? 0
        append(wholeMinutes, "minute")
        remainingMilliseconds -= Double(wholeMinutes) * 60_000
        // Seconds keep their milliseconds, so 500 ms reads "0.5 seconds" rather than the
        // "0 seconds" of an empty duration.
        let seconds = remainingMilliseconds.rounded() / 1_000
        if seconds != 0, seconds.isFinite {
            parts.append(BaseValue.formatted(seconds) + (abs(seconds) == 1 ? " second" : " seconds"))
        }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }
}

/// The calendar fields of one date that `BaseDateFormatting.format` writes. The day of the
/// year and the week numbers each cost a separate calendar computation, and most patterns
/// use none of them, so they are computed on first use.
private final class MomentDateFields {
    let calendar: Calendar
    /// The date truncated to a whole millisecond, as JavaScript stores dates. `Date` counts
    /// binary seconds from 2001, so a whole millisecond such as .007 can come back a few
    /// nanoseconds short and truncate to .006; a microsecond of tolerance restores it.
    let millisecondsSince1970: Double
    /// Half a millisecond into that millisecond, so the representation error cannot carry
    /// the calendar fields across a second, minute or day boundary.
    let fieldDate: Date
    let year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, millisecond: Int
    let weekdayIndex: Int
    let offsetSeconds: Int

    init(date: Date, calendar: Calendar) {
        self.calendar = calendar
        millisecondsSince1970 = (date.timeIntervalSince1970 * 1_000 + 0.001).rounded(.down)
        fieldDate = millisecondsSince1970.isFinite ? Date(timeIntervalSince1970: (millisecondsSince1970 + 0.5) / 1_000) : date
        let components = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second, .nanosecond, .weekday], from: fieldDate)
        let eraYear = components.year ?? 0
        // moment counts years astronomically: 1 BCE is year 0 and 2 BCE is year -1, while
        // the Gregorian calendar counts BCE years upward from 1 in era 0.
        year = components.era == 0 ? 1 - eraYear : eraYear
        month = components.month ?? 1
        day = components.day ?? 1
        hour = components.hour ?? 0
        minute = components.minute ?? 0
        second = components.second ?? 0
        millisecond = (components.nanosecond ?? 0) / 1_000_000
        weekdayIndex = (components.weekday ?? 1) - 1
        offsetSeconds = calendar.timeZone.secondsFromGMT(for: fieldDate)
    }

    lazy var dayOfYear: Int = calendar.ordinality(of: .day, in: .year, for: fieldDate) ?? 1

    lazy var isoWeek: (week: Int, year: Int) = {
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = calendar.timeZone
        let components = isoCalendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: fieldDate)
        return (components.weekOfYear ?? 1, components.yearForWeekOfYear ?? year)
    }()

    /// moment's English locale: weeks start on Sunday, and week 1 holds January 1.
    lazy var localeWeek: (week: Int, year: Int) = {
        var localeCalendar = calendar
        localeCalendar.firstWeekday = 1
        localeCalendar.minimumDaysInFirstWeek = 1
        let components = localeCalendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: fieldDate)
        return (components.weekOfYear ?? 1, components.yearForWeekOfYear ?? year)
    }()
}
