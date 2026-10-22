/// Writes the axis' dates with `axisFormat`'s d3 time format specifiers (`%Y-%m-%d`, `%b %e`), in English, as
/// d3-time-format writes them for Mermaid: `%` then an optional padding (`-` none, `_` spaces, `0` zeros) and a
/// letter; any other character is written as it is.
enum GanttAxisFormat {
    private static let percent: Character = "%"
    private static let paddings: [Character: String] = ["-": "", "_": " ", "0": "0"]

    static func format(_ specifier: String, _ time: GanttTime, zone: GanttTimeZone) -> String {
        var written = ""
        var characters = Substring(specifier)
        while let character = characters.popFirst() {
            guard character == percent else {
                written.append(character)
                continue
            }
            // A `%` that ends the specifier writes nothing.
            guard var directive = characters.popFirst() else { break }
            var padding = directive == "e" ? " " : "0"
            if let chosen = paddings[directive], let next = characters.popFirst() {
                padding = chosen
                directive = next
            }
            written += self.directive(directive, time, padding: padding, zone: zone)
        }
        return written
    }

    private static func directive(_ letter: Character, _ time: GanttTime, padding: String, zone: GanttTimeZone) -> String {
        if let calendarText = calendarDirective(letter, time, padding: padding) { return calendarText }
        if let clockText = clockDirective(letter, time, padding: padding, zone: zone) { return clockText }
        return String(letter)
    }

    /// The year, month, week and day directives.
    private static func calendarDirective(_ letter: Character, _ time: GanttTime, padding: String) -> String? {
        let weekdayName = GanttCalendarToken.weekdayNames[Int(time.weekday)]
        let monthName = GanttCalendarToken.monthNames[Int(time.month - 1)]
        switch letter {
        case "a": return String(weekdayName.prefix(3))
        case "A": return weekdayName
        case "b": return String(monthName.prefix(3))
        case "B": return monthName
        case "d", "e": return padded(time.day, padding, 2)
        case "g": return padded(GanttIsoWeek.thursday(of: time).year % 100, padding, 2)
        case "G": return padded(GanttIsoWeek.thursday(of: time).year % 10_000, padding, 4)
        case "j": return padded(1 + time.dayNumber - GanttTime.dayNumber(year: time.year, month: 1, day: 1), padding, 3)
        case "m": return padded(time.month, padding, 2)
        case "q": return String((time.month + 2) / 3)
        case "u": return String(time.isoWeekday)
        case "U": return padded(weekOfYear(time, weekStart: 0), padding, 2)
        case "V": return padded(GanttIsoWeek.number(of: time), padding, 2)
        case "w": return String(time.weekday)
        case "W": return padded(weekOfYear(time, weekStart: 1), padding, 2)
        case "y": return padded(time.year % 100, padding, 2)
        case "Y": return padded(time.year % 10_000, padding, 4)
        default: return nil
        }
    }

    /// The time of day, Unix time, the offset and the combined directives.
    private static func clockDirective(_ letter: Character, _ time: GanttTime, padding: String, zone: GanttTimeZone) -> String? {
        switch letter {
        case "c": return format("%x, %X", time, zone: zone)
        case "f": return padded(time.millisecond, padding, 3) + "000"
        case "H": return padded(time.hour, padding, 2)
        case "I": return padded(time.hour % 12 == 0 ? 12 : time.hour % 12, padding, 2)
        case "L": return padded(time.millisecond, padding, 3)
        case "M": return padded(time.minute, padding, 2)
        case "p": return time.hour >= 12 ? "PM" : "AM"
        case "Q": return String(zone.unixMilliseconds(of: time))
        case "s": return String(GanttTime.floorDivision(zone.unixMilliseconds(of: time), GanttTime.millisecondsPerSecond))
        case "S": return padded(time.second, padding, 2)
        case "x": return format("%-m/%-d/%Y", time, zone: zone)
        case "X": return format("%-I:%M:%S %p", time, zone: zone)
        case "Z":
            let minutes = zone.offsetMinutes(at: time)
            return (minutes >= 0 ? "+" : "-") + padded(abs(minutes) / 60, "0", 2) + padded(abs(minutes) % 60, "0", 2)
        case "%": return "%"
        default: return nil
        }
    }

    /// Weeks since the last `weekStart` day (0 for Sunday) before the year began: d3's `%U` and `%W`.
    private static func weekOfYear(_ time: GanttTime, weekStart: Int64) -> Int64 {
        func weekStartDay(onOrBefore dayNumber: Int64) -> Int64 {
            dayNumber - GanttTime.modulo(GanttTime(milliseconds: dayNumber * GanttTime.millisecondsPerDay).weekday - weekStart, 7)
        }
        let lastDayBefore = GanttTime.dayNumber(year: time.year, month: 1, day: 1) - 1
        return (weekStartDay(onOrBefore: time.dayNumber) - weekStartDay(onOrBefore: lastDayBefore)) / 7
    }

    /// The number with `padding` before it up to `width` characters, a minus sign before the padding.
    private static func padded(_ number: Int64, _ padding: String, _ width: Int) -> String {
        let digits = String(abs(number))
        let filled = digits.count < width ? String(repeating: padding, count: width - digits.count) + digits : digits
        return (number < 0 ? "-" : "") + filled
    }
}
