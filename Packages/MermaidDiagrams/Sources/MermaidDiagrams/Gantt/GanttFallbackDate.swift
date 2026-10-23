/// The dates JavaScript's `Date` reads that Mermaid falls back to when a start date does not fit `dateFormat`, among
/// the forms read here: an ISO date (`2014-01-06`, `2014-01`, `2014`), which JavaScript takes at midnight UTC; an ISO
/// date and time (`2014-01-06T10:00`, seconds and milliseconds optional), on the wall clock unless `Z` or an offset
/// follows; and a year, a month and a day of one or two digits apart by `-` or `/` (`2014-1-6`, `202-12-01`), on the
/// wall clock, a time after a space optional. JavaScript reads other forms (`March 7, 2014`) that are not read here.
enum GanttFallbackDate {
    /// Mermaid refuses a fallback date whose year is further than this from year 0.
    static let largestYear: Int64 = 10_000
    private static let hyphen = UInt8(ascii: "-")
    private static let slash = UInt8(ascii: "/")
    private static let letterT = UInt8(ascii: "T")

    static func parse(_ text: String, zone: GanttTimeZone) -> GanttTime? {
        let bytes = Array(text.utf8)
        let timeSeparator = bytes.firstIndex { byte in byte == letterT || byte == MermaidByte.space }
        let dateBytes = Array(bytes[..<(timeSeparator ?? bytes.count)])
        guard let date = DateFields(dateBytes) else { return nil }
        var clock = ClockFields()
        if let timeSeparator {
            guard date.isISO == (bytes[timeSeparator] == letterT), date.hasDay,
                  let parsedClock = ClockFields(Array(bytes[(timeSeparator + 1)...]), allowsZone: date.isISO) else { return nil }
            clock = parsedClock
        }
        guard abs(date.year) <= largestYear,
              let time = GanttTime(year: date.year, month: date.month, day: date.day, hour: clock.hour, minute: clock.minute, second: clock.second,
                                   millisecond: clock.millisecond + clock.offsetMinutes * GanttTime.millisecondsPerMinute) else { return nil }
        let isUniversal = (date.isISO && timeSeparator == nil) || clock.hasZone
        return isUniversal ? zone.wallClockTime(unixMilliseconds: time.milliseconds) : time
    }

    /// The year, month and day of a date's text, and whether they are written as ISO 8601 writes them.
    private struct DateFields {
        let year: Int64
        let month: Int64
        let day: Int64
        let hasDay: Bool
        let isISO: Bool

        init?(_ bytes: [UInt8]) {
            let separator = bytes.first { byte in byte == GanttFallbackDate.hyphen || byte == GanttFallbackDate.slash } ?? GanttFallbackDate.hyphen
            let parts = bytes.split(separator: separator, omittingEmptySubsequences: false)
            guard (1...3).contains(parts.count), parts.allSatisfy({ part in !part.isEmpty && part.allSatisfy(MermaidByte.isDigit) }) else { return nil }
            let numbers = parts.compactMap { part in Int64(String(decoding: part, as: UTF8.self)) }
            guard numbers.count == parts.count else { return nil }
            isISO = separator == GanttFallbackDate.hyphen && parts[0].count == 4 && parts.dropFirst().allSatisfy { part in part.count == 2 }
            guard isISO || (parts.count == 3 && parts[0].count <= 6 && parts.dropFirst().allSatisfy { part in part.count <= 2 }) else { return nil }
            year = numbers[0]
            month = numbers.count > 1 ? numbers[1] : 1
            day = numbers.count > 2 ? numbers[2] : 1
            hasDay = numbers.count == 3
            guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        }
    }

    /// A time of day: `10:00`, `10:00:30`, `10:00:30.250`, then, for an ISO date, `Z` or `+01:00`.
    private struct ClockFields {
        var hour: Int64 = 0
        var minute: Int64 = 0
        var second: Int64 = 0
        var millisecond: Int64 = 0
        /// The minutes to add to the written time to reach UTC.
        var offsetMinutes: Int64 = 0
        var hasZone = false

        init() {}

        init?(_ bytes: [UInt8], allowsZone: Bool) {
            var clockBytes = bytes
            if allowsZone, let zoneStart = clockBytes.lastIndex(where: Self.startsZone) {
                guard let offset = Self.offsetMinutes(Array(clockBytes[zoneStart...])) else { return nil }
                offsetMinutes = offset
                hasZone = true
                clockBytes = Array(clockBytes[..<zoneStart])
            }
            let fractionParts = clockBytes.split(separator: MermaidByte.period, omittingEmptySubsequences: false)
            let parts = fractionParts[0].split(separator: MermaidByte.colon, omittingEmptySubsequences: false)
            guard fractionParts.count <= 2, (2...3).contains(parts.count),
                  parts.allSatisfy({ part in part.count == 2 && part.allSatisfy(MermaidByte.isDigit) }),
                  let hour = Int64(String(decoding: parts[0], as: UTF8.self)), let minute = Int64(String(decoding: parts[1], as: UTF8.self)) else {
                return nil
            }
            self.hour = hour
            self.minute = minute
            second = parts.count == 3 ? Int64(String(decoding: parts[2], as: UTF8.self)) ?? 0 : 0
            if fractionParts.count == 2 {
                let fraction = fractionParts[1]
                guard parts.count == 3, (1...3).contains(fraction.count), fraction.allSatisfy(MermaidByte.isDigit),
                      let value = Int64(String(decoding: fraction, as: UTF8.self) + String(repeating: "0", count: 3 - fraction.count)) else { return nil }
                millisecond = value
            }
            guard hour <= 24, minute < 60, second < 60 else { return nil }
        }

        private static func startsZone(_ byte: UInt8) -> Bool {
            byte == UInt8(ascii: "Z") || byte == UInt8(ascii: "+") || byte == GanttFallbackDate.hyphen
        }

        /// `Z`, or `+01:00` and `-05:30`: the minutes to add to reach UTC.
        private static func offsetMinutes(_ bytes: [UInt8]) -> Int64? {
            if bytes == [UInt8(ascii: "Z")] { return 0 }
            guard bytes.count == 6, bytes[3] == MermaidByte.colon, let hours = Int64(String(decoding: bytes[1..<3], as: UTF8.self)),
                  let minutes = Int64(String(decoding: bytes[4..<6], as: UTF8.self)) else { return nil }
            let total = hours * 60 + minutes
            return bytes[0] == UInt8(ascii: "+") ? -total : total
        }
    }
}
