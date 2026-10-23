/// The fields a date's text gives, as Mermaid's date library collects them while it reads a date.
struct GanttDateFields {
    var year: Int64?
    /// 1 for January to 12 for December.
    var month: Int64?
    var day: Int64?
    /// Whether `Do` gave the day, which counts even when it is 0.
    var isDayGiven = false
    var hour: Int64?
    var minute: Int64?
    var second: Int64?
    var millisecond: Int64?
    /// The minutes UTC is ahead of the written time (`+01:00` gives -60), when the text gives an offset.
    var offsetMinutes: Int64?
    /// Whether `PM` (true) or `AM` (false) was written.
    var isAfternoon: Bool?

    /// The date the fields give, the missing ones taken from `now` as Mermaid's library takes them: without a year or
    /// a month, today's day; with a year and no month, January the 1st.
    func time(now: GanttTime, zone: GanttTimeZone) -> GanttTime? {
        let writtenYear = year ?? 0
        let writtenMonth = month ?? 0
        let writtenDay = day ?? 0
        let dayOfMonth = isDayGiven || writtenDay != 0 ? writtenDay : (writtenYear == 0 && writtenMonth == 0 ? now.day : 1)
        let monthOfYear = writtenYear != 0 && writtenMonth == 0 ? 1 : (writtenMonth > 0 ? writtenMonth : now.month)
        let fullYear = writtenYear != 0 ? writtenYear : now.year
        let millisecondValue = (millisecond ?? 0) + (offsetMinutes ?? 0) * GanttTime.millisecondsPerMinute
        guard let time = GanttTime(year: fullYear, month: monthOfYear, day: dayOfMonth, hour: hourOfDay ?? 0, minute: minute ?? 0,
                                   second: second ?? 0, millisecond: millisecondValue) else { return nil }
        guard offsetMinutes != nil else { return time }
        return zone.wallClockTime(unixMilliseconds: time.milliseconds)
    }

    /// The hour on a 24-hour clock, after `AM` or `PM`.
    private var hourOfDay: Int64? {
        guard let hour, let isAfternoon else { return hour }
        if isAfternoon { return hour < 12 ? hour + 12 : hour }
        return hour == 12 ? 0 : hour
    }
}

/// Reads a date's text token by token, from its start, collecting the fields each token gives. Tokens Mermaid's
/// library writes but does not read (weekday names, ISO weeks, `k`) are passed over; the format given back decides.
struct GanttDateFieldReader {
    private let bytes: [UInt8]
    private var position = 0
    private(set) var fields = GanttDateFields()

    init(text: String) {
        bytes = Array(text.utf8)
    }

    /// Moves past `literal` and returns true, or returns false when the text does not continue with it.
    mutating func skip(_ literal: String) -> Bool {
        let literalBytes = Array(literal.utf8)
        guard position + literalBytes.count <= bytes.count, Array(bytes[position..<position + literalBytes.count]) == literalBytes else { return false }
        position += literalBytes.count
        return true
    }

    mutating func read(_ token: GanttDateToken) -> Bool {
        switch token {
        case .calendar(let calendarToken): read(calendarToken)
        case .clock(let clockToken): read(clockToken)
        case .zone(let zoneToken): read(zoneToken)
        case .notFormatted: false
        }
    }

    private mutating func read(_ token: GanttCalendarToken) -> Bool {
        switch token {
        case .year: return store(digits(exactly: 4)) { fields, value in fields.year = value }
        case .twoDigitYear: return store(digits(exactly: 2)) { fields, value in fields.year = value + (value > 68 ? 1900 : 2000) }
        case .quarter: return store(digits(exactly: 1)) { fields, value in fields.month = (value - 1) * 3 + 1 }
        case .monthName, .monthShortName:
            let names = GanttCalendarToken.monthNames.map { name in token == .monthName ? name : String(name.prefix(3)) }
            return store(word().flatMap { word in names.firstIndex(of: word).map { index in Int64(index + 1) } }) { fields, value in fields.month = value }
        case .twoDigitMonth: return store(digits(exactly: 2)) { fields, value in fields.month = value }
        case .month: return store(digits(from: 1, to: 2)) { fields, value in fields.month = value }
        case .dayWithOrdinal: return readDayWithOrdinal()
        case .twoDigitDay: return store(digits(exactly: 2)) { fields, value in fields.day = value }
        case .day: return store(digits(from: 1, to: 2)) { fields, value in fields.day = value }
        case .weekdayName, .weekdayShortName, .weekdayMinimalName: return word() != nil
        case .weekdayNumber, .isoWeekYear, .twoDigitIsoWeek, .isoWeek: return digits(from: 1, to: 4) != nil
        }
    }

    private mutating func read(_ token: GanttClockToken) -> Bool {
        switch token {
        case .twoDigitHour, .hour, .twoDigitTwelveHour, .twelveHour: return store(digits(from: 1, to: 2)) { fields, value in fields.hour = value }
        case .twoDigitHourFromOne, .hourFromOne: return digits(from: 1, to: 2) != nil
        case .twoDigitMinute, .minute: return store(digits(from: 1, to: 2)) { fields, value in fields.minute = value }
        case .twoDigitSecond, .second: return store(digits(from: 1, to: 2)) { fields, value in fields.second = value }
        case .millisecond: return store(digits(exactly: 3)) { fields, value in fields.millisecond = value }
        case .upperMeridiem, .lowerMeridiem:
            guard let meridiem = word() else { return false }
            fields.isAfternoon = meridiem == (token == .upperMeridiem ? "PM" : "pm")
            return true
        }
    }

    private mutating func read(_ token: GanttZoneToken) -> Bool {
        switch token {
        case .offset, .compactOffset: return readOffset()
        case .unixSeconds, .unixMilliseconds: return digits(from: 1, to: 16) != nil
        }
    }

    /// `1st`, `22nd`: the digits give the day, even 0; the format given back checks the suffix.
    private mutating func readDayWithOrdinal() -> Bool {
        guard let digitsValue = digits(from: 1, to: 2), word() != nil else { return false }
        fields.day = digitsValue
        fields.isDayGiven = true
        return true
    }

    /// `+01:00`, `+0100`, `+01` or `Z`.
    private mutating func readOffset() -> Bool {
        if position < bytes.count, bytes[position] == UInt8(ascii: "Z") {
            position += 1
            fields.offsetMinutes = 0
            return true
        }
        guard position < bytes.count, bytes[position] == UInt8(ascii: "+") || bytes[position] == UInt8(ascii: "-") else { return false }
        let isAhead = bytes[position] == UInt8(ascii: "+")
        position += 1
        guard let hours = digits(exactly: 2) else { return false }
        if position < bytes.count, bytes[position] == MermaidByte.colon { position += 1 }
        let minutes = digits(exactly: 2) ?? 0
        let total = hours * 60 + minutes
        fields.offsetMinutes = total == 0 ? 0 : (isAhead ? -total : total)
        return true
    }

    private mutating func store(_ value: Int64?, _ apply: (inout GanttDateFields, Int64) -> Void) -> Bool {
        guard let value else { return false }
        apply(&fields, value)
        return true
    }

    /// `count` digits, or nil with the position where it was.
    private mutating func digits(exactly count: Int) -> Int64? {
        digits(from: count, to: count)
    }

    /// As many digits as there are, from `least` to `most`, or nil with the position where it was.
    private mutating func digits(from least: Int, to most: Int) -> Int64? {
        var end = position
        while end < bytes.count, end - position < most, MermaidByte.isDigit(bytes[end]) { end += 1 }
        guard end - position >= least, let value = Int64(String(decoding: bytes[position..<end], as: UTF8.self)) else { return nil }
        position = end
        return value
    }

    /// A run of ASCII letters, or nil when there is none.
    private mutating func word() -> String? {
        var end = position
        while end < bytes.count, MermaidByte.isLetter(bytes[end]) { end += 1 }
        guard end > position else { return nil }
        defer { position = end }
        return String(decoding: bytes[position..<end], as: UTF8.self)
    }
}
