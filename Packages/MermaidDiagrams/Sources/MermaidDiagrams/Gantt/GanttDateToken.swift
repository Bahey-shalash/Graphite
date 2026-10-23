/// A token of Mermaid's date library's formats (dayjs with its advanced-format and ISO-week plugins, in English).
enum GanttDateToken: Equatable {
    case calendar(GanttCalendarToken)
    case clock(GanttClockToken)
    case zone(GanttZoneToken)
    /// A token Mermaid's library cannot format: the week of a locale's year, a time zone's name.
    case notFormatted

    /// Each token's spelling, longer spellings of a letter before shorter ones.
    static let spellings: [(String, GanttDateToken)] = [
        ("YYYY", .calendar(.year)), ("YY", .calendar(.twoDigitYear)), ("Q", .calendar(.quarter)), ("MMMM", .calendar(.monthName)),
        ("MMM", .calendar(.monthShortName)), ("MM", .calendar(.twoDigitMonth)), ("M", .calendar(.month)), ("Do", .calendar(.dayWithOrdinal)),
        ("DD", .calendar(.twoDigitDay)), ("D", .calendar(.day)), ("dddd", .calendar(.weekdayName)), ("ddd", .calendar(.weekdayShortName)),
        ("dd", .calendar(.weekdayMinimalName)), ("d", .calendar(.weekdayNumber)), ("HH", .clock(.twoDigitHour)), ("H", .clock(.hour)),
        ("hh", .clock(.twoDigitTwelveHour)), ("h", .clock(.twelveHour)), ("kk", .clock(.twoDigitHourFromOne)), ("k", .clock(.hourFromOne)),
        ("mm", .clock(.twoDigitMinute)), ("m", .clock(.minute)), ("ss", .clock(.twoDigitSecond)), ("s", .clock(.second)),
        ("SSS", .clock(.millisecond)), ("A", .clock(.upperMeridiem)), ("a", .clock(.lowerMeridiem)), ("ZZ", .zone(.compactOffset)),
        ("Z", .zone(.offset)), ("X", .zone(.unixSeconds)), ("x", .zone(.unixMilliseconds)), ("GGGG", .calendar(.isoWeekYear)),
        ("WW", .calendar(.twoDigitIsoWeek)), ("W", .calendar(.isoWeek)), ("gggg", .notFormatted), ("wo", .notFormatted),
        ("ww", .notFormatted), ("w", .notFormatted), ("zzz", .notFormatted), ("z", .notFormatted),
    ]

    /// The milliseconds one unit of a Unix time token stands for, or nil for another token.
    var unixUnitMilliseconds: Int64? {
        switch self {
        case .zone(let token): token.unixUnitMilliseconds
        case .calendar, .clock, .notFormatted: nil
        }
    }

    /// What the token writes for `time`, or nil for a token Mermaid's library cannot format.
    func written(_ time: GanttTime, zone: GanttTimeZone) -> String? {
        switch self {
        case .calendar(let token): token.written(time)
        case .clock(let token): token.written(time)
        case .zone(let token): token.written(time, zone: zone)
        case .notFormatted: nil
        }
    }

    /// The number with zeros before it up to `width` characters, as JavaScript pads it (a minus sign counts).
    static func padded(_ number: Int64, width: Int) -> String {
        let written = String(number)
        return written.count >= width ? written : String(repeating: "0", count: width - written.count) + written
    }
}

/// The tokens that write the date: year, quarter, month, day, weekday and ISO week.
enum GanttCalendarToken: Equatable {
    case year, twoDigitYear, quarter, monthName, monthShortName, twoDigitMonth, month, dayWithOrdinal, twoDigitDay, day
    case weekdayName, weekdayShortName, weekdayMinimalName, weekdayNumber, isoWeekYear, twoDigitIsoWeek, isoWeek

    static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November",
                             "December"]
    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    func written(_ time: GanttTime) -> String {
        switch self {
        case .year: GanttDateToken.padded(time.year, width: 4)
        case .twoDigitYear: String(String(time.year).suffix(2))
        case .quarter: String((time.month + 2) / 3)
        case .monthName: Self.monthNames[Int(time.month - 1)]
        case .monthShortName: String(Self.monthNames[Int(time.month - 1)].prefix(3))
        case .twoDigitMonth: GanttDateToken.padded(time.month, width: 2)
        case .month: String(time.month)
        case .dayWithOrdinal: Self.ordinal(time.day)
        case .twoDigitDay: GanttDateToken.padded(time.day, width: 2)
        case .day: String(time.day)
        case .weekdayName: Self.weekdayNames[Int(time.weekday)]
        case .weekdayShortName: String(Self.weekdayNames[Int(time.weekday)].prefix(3))
        case .weekdayMinimalName: String(Self.weekdayNames[Int(time.weekday)].prefix(2))
        case .weekdayNumber: String(time.weekday)
        case .isoWeekYear: String(GanttIsoWeek.thursday(of: time).year)
        case .twoDigitIsoWeek: GanttDateToken.padded(GanttIsoWeek.number(of: time), width: 2)
        case .isoWeek: String(GanttIsoWeek.number(of: time))
        }
    }

    /// `1st`, `2nd`, `3rd`, `4th`, `11th`, `21st`, as Mermaid's library writes them.
    static func ordinal(_ number: Int64) -> String {
        let lastTwoDigits = number % 100
        let lastDigit = lastTwoDigits % 10
        let isTeen = (11...13).contains(lastTwoDigits)
        let suffix = isTeen ? "th" : (lastDigit == 1 ? "st" : lastDigit == 2 ? "nd" : lastDigit == 3 ? "rd" : "th")
        return String(number) + suffix
    }
}

/// The tokens that write the time of day.
enum GanttClockToken: Equatable {
    case twoDigitHour, hour, twoDigitTwelveHour, twelveHour, twoDigitHourFromOne, hourFromOne
    case twoDigitMinute, minute, twoDigitSecond, second, millisecond, upperMeridiem, lowerMeridiem

    func written(_ time: GanttTime) -> String {
        let twelveHour = time.hour % 12 == 0 ? 12 : time.hour % 12
        let hourFromOne = time.hour == 0 ? 24 : time.hour
        switch self {
        case .twoDigitHour: return GanttDateToken.padded(time.hour, width: 2)
        case .hour: return String(time.hour)
        case .twoDigitTwelveHour: return GanttDateToken.padded(twelveHour, width: 2)
        case .twelveHour: return String(twelveHour)
        case .twoDigitHourFromOne: return GanttDateToken.padded(hourFromOne, width: 2)
        case .hourFromOne: return String(hourFromOne)
        case .twoDigitMinute: return GanttDateToken.padded(time.minute, width: 2)
        case .minute: return String(time.minute)
        case .twoDigitSecond: return GanttDateToken.padded(time.second, width: 2)
        case .second: return String(time.second)
        case .millisecond: return GanttDateToken.padded(time.millisecond, width: 3)
        case .upperMeridiem: return time.hour < 12 ? "AM" : "PM"
        case .lowerMeridiem: return time.hour < 12 ? "am" : "pm"
        }
    }
}

/// The tokens that depend on the time zone: the offset from UTC and Unix time.
enum GanttZoneToken: Equatable {
    /// `+01:00`.
    case offset
    /// `+0100`.
    case compactOffset
    case unixSeconds
    case unixMilliseconds

    var unixUnitMilliseconds: Int64? {
        switch self {
        case .unixSeconds: GanttTime.millisecondsPerSecond
        case .unixMilliseconds: 1
        case .offset, .compactOffset: nil
        }
    }

    func written(_ time: GanttTime, zone: GanttTimeZone) -> String {
        switch self {
        case .offset, .compactOffset:
            let minutes = zone.offsetMinutes(at: time)
            let hours = GanttDateToken.padded(abs(minutes) / 60, width: 2)
            let rest = GanttDateToken.padded(abs(minutes) % 60, width: 2)
            return (minutes >= 0 ? "+" : "-") + hours + (self == .offset ? ":" : "") + rest
        case .unixSeconds: return String(GanttTime.floorDivision(zone.unixMilliseconds(of: time), GanttTime.millisecondsPerSecond))
        case .unixMilliseconds: return String(zone.unixMilliseconds(of: time))
        }
    }
}
