import Foundation

/// Dates written with the format strings Obsidian uses (Moment.js), such as
/// `YYYY-MM-DD` or `dddd, MMMM Do YYYY`, in Moment's default English locale, as Obsidian's
/// Templates and Daily notes plugins write them.
public enum MomentDateFormat {
    public static let defaultDateFormat = "YYYY-MM-DD"
    public static let defaultTimeFormat = "HH:mm"

    private static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    /// Longest first, so `YYYY` is not read as two `YY`.
    private static let tokens = [
        "YYYY", "YY", "Y", "Qo", "Q", "MMMM", "MMM", "MM", "Mo", "M", "DDDD", "DDDo", "DDD", "DD", "Do", "D",
        "dddd", "ddd", "dd", "do", "d", "E", "e", "ww", "wo", "w", "WW", "Wo", "W", "gggg", "gg", "GGGG", "GG",
        "HH", "H", "hh", "h", "kk", "k", "mm", "m", "ss", "s", "SSS", "SS", "S", "A", "a", "X", "x", "ZZ", "Z",
    ]
    /// Moment's English long date formats.
    private static let longDateFormats = [
        "LLLL": "dddd, MMMM D, YYYY h:mm A", "LLL": "MMMM D, YYYY h:mm A", "LL": "MMMM D, YYYY",
        "LTS": "h:mm:ss A", "LT": "h:mm A", "L": "MM/DD/YYYY",
    ]

    private enum Piece: Equatable {
        case token(String)
        case literal(String)
    }

    /// The date written in `format`.
    public static func string(from date: Date, format: String, timeZone: TimeZone = .current) -> String {
        let calendar = gregorianCalendar(timeZone: timeZone)
        return pieces(of: format).map { piece in
            switch piece {
            case .literal(let text): text
            case .token(let token): value(of: token, for: date, calendar: calendar, timeZone: timeZone)
            }
        }.joined()
    }

    /// The day a text written in `format` names, for file names such as daily notes. Only
    /// formats made of years, months, days, weekday names and literal text can be read.
    public static func date(from text: String, format: String, timeZone: TimeZone = .current) -> Date? {
        var pattern = "^"
        var fields: [String] = []
        for piece in pieces(of: format) {
            switch piece {
            case .literal(let literal):
                pattern += NSRegularExpression.escapedPattern(for: literal)
            case .token(let token):
                switch token {
                case "YYYY": pattern += "(\\d{4})"; fields.append(token)
                case "YY": pattern += "(\\d{2})"; fields.append(token)
                case "MMMM": pattern += "(" + monthNames.joined(separator: "|") + ")"; fields.append(token)
                case "MMM": pattern += "(" + monthNames.map { name in String(name.prefix(3)) }.joined(separator: "|") + ")"; fields.append(token)
                case "MM", "DD": pattern += "(\\d{2})"; fields.append(token)
                case "M", "D": pattern += "(\\d{1,2})"; fields.append(token)
                case "Do": pattern += "(\\d{1,2})(?:st|nd|rd|th)"; fields.append(token)
                case "dddd": pattern += "(?:" + weekdayNames.joined(separator: "|") + ")"
                case "ddd": pattern += "(?:" + weekdayNames.map { name in String(name.prefix(3)) }.joined(separator: "|") + ")"
                case "dd": pattern += "(?:" + weekdayNames.map { name in String(name.prefix(2)) }.joined(separator: "|") + ")"
                default: return nil
                }
            }
        }
        pattern += "$"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return nil }
        var components = DateComponents()
        for (fieldIndex, field) in fields.enumerated() {
            let captured = (text as NSString).substring(with: match.range(at: fieldIndex + 1))
            switch field {
            case "YYYY": components.year = Int(captured)
            case "YY": components.year = Int(captured).map { twoDigits in twoDigits > 68 ? 1900 + twoDigits : 2000 + twoDigits }
            case "MMMM": components.month = monthNames.firstIndex { name in name.caseInsensitiveCompare(captured) == .orderedSame }.map { index in index + 1 }
            case "MMM": components.month = monthNames.firstIndex { name in name.prefix(3).caseInsensitiveCompare(captured) == .orderedSame }.map { index in index + 1 }
            case "MM", "M": components.month = Int(captured)
            case "DD", "D", "Do": components.day = Int(captured)
            default: break
            }
        }
        guard components.year != nil, components.month != nil, components.day != nil else { return nil }
        let calendar = gregorianCalendar(timeZone: timeZone)
        guard let date = calendar.date(from: components) else { return nil }
        // Written back the same way, or it named a day that does not exist (31 April).
        return string(from: date, format: format, timeZone: timeZone).caseInsensitiveCompare(text) == .orderedSame ? date : nil
    }

    // MARK: Private

    private static func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        // Moment's English locale: weeks start on Sunday, and week 1 holds January 1.
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    private static func pieces(of format: String) -> [Piece] {
        var pieces: [Piece] = []
        var remaining = Substring(format)
        func appendLiteral(_ text: String) {
            if case .literal(let previous) = pieces.last { pieces[pieces.count - 1] = .literal(previous + text) } else { pieces.append(.literal(text)) }
        }
        while let first = remaining.first {
            if first == "[" {
                // Text in brackets is written as it is.
                if let closing = remaining.firstIndex(of: "]") {
                    appendLiteral(String(remaining[remaining.index(after: remaining.startIndex)..<closing]))
                    remaining = remaining[remaining.index(after: closing)...]
                } else {
                    appendLiteral(String(remaining))
                    remaining = ""
                }
                continue
            }
            if let longFormat = longDateFormats.keys.sorted(by: { first, second in first.count > second.count }).first(where: { key in remaining.hasPrefix(key) }),
               let expansion = longDateFormats[longFormat] {
                pieces += Self.pieces(of: expansion)
                remaining = remaining.dropFirst(longFormat.count)
                continue
            }
            if let token = tokens.first(where: { token in remaining.hasPrefix(token) }) {
                pieces.append(.token(token))
                remaining = remaining.dropFirst(token.count)
                continue
            }
            appendLiteral(String(first))
            remaining = remaining.dropFirst()
        }
        return pieces
    }

    private static func value(of token: String, for date: Date, calendar: Calendar, timeZone: TimeZone) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond, .weekday, .weekOfYear, .yearForWeekOfYear], from: date)
        let year = components.year ?? 0, month = components.month ?? 1, day = components.day ?? 1
        let hour = components.hour ?? 0, minute = components.minute ?? 0, second = components.second ?? 0
        let weekdayIndex = (components.weekday ?? 1) - 1
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = timeZone
        let isoComponents = isoCalendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        func padded(_ number: Int, _ width: Int) -> String {
            let digits = String(abs(number))
            return (number < 0 ? "-" : "") + String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        switch token {
        case "YYYY": return padded(year, 4)
        case "YY": return padded(year % 100, 2)
        case "Y": return String(year)
        case "Q": return String((month - 1) / 3 + 1)
        case "Qo": return ordinal((month - 1) / 3 + 1)
        case "MMMM": return monthNames[month - 1]
        case "MMM": return String(monthNames[month - 1].prefix(3))
        case "MM": return padded(month, 2)
        case "Mo": return ordinal(month)
        case "M": return String(month)
        case "DDDD": return padded(dayOfYear, 3)
        case "DDDo": return ordinal(dayOfYear)
        case "DDD": return String(dayOfYear)
        case "DD": return padded(day, 2)
        case "Do": return ordinal(day)
        case "D": return String(day)
        case "dddd": return weekdayNames[weekdayIndex]
        case "ddd": return String(weekdayNames[weekdayIndex].prefix(3))
        case "dd": return String(weekdayNames[weekdayIndex].prefix(2))
        case "do": return ordinal(weekdayIndex)
        case "d", "e": return String(weekdayIndex)
        case "E": return String(weekdayIndex == 0 ? 7 : weekdayIndex)
        case "ww": return padded(components.weekOfYear ?? 1, 2)
        case "wo": return ordinal(components.weekOfYear ?? 1)
        case "w": return String(components.weekOfYear ?? 1)
        case "WW": return padded(isoComponents.weekOfYear ?? 1, 2)
        case "Wo": return ordinal(isoComponents.weekOfYear ?? 1)
        case "W": return String(isoComponents.weekOfYear ?? 1)
        case "gggg": return padded(components.yearForWeekOfYear ?? year, 4)
        case "gg": return padded((components.yearForWeekOfYear ?? year) % 100, 2)
        case "GGGG": return padded(isoComponents.yearForWeekOfYear ?? year, 4)
        case "GG": return padded((isoComponents.yearForWeekOfYear ?? year) % 100, 2)
        case "HH": return padded(hour, 2)
        case "H": return String(hour)
        case "hh": return padded(hour % 12 == 0 ? 12 : hour % 12, 2)
        case "h": return String(hour % 12 == 0 ? 12 : hour % 12)
        case "kk": return padded(hour == 0 ? 24 : hour, 2)
        case "k": return String(hour == 0 ? 24 : hour)
        case "mm": return padded(minute, 2)
        case "m": return String(minute)
        case "ss": return padded(second, 2)
        case "s": return String(second)
        case "SSS": return padded((components.nanosecond ?? 0) / 1_000_000, 3)
        case "SS": return padded((components.nanosecond ?? 0) / 10_000_000, 2)
        case "S": return String((components.nanosecond ?? 0) / 100_000_000)
        case "A": return hour < 12 ? "AM" : "PM"
        case "a": return hour < 12 ? "am" : "pm"
        case "X": return String(Int(date.timeIntervalSince1970))
        case "x": return String(Int(date.timeIntervalSince1970 * 1000))
        case "Z", "ZZ":
            let offsetMinutes = timeZone.secondsFromGMT(for: date) / 60
            let sign = offsetMinutes < 0 ? "-" : "+"
            return sign + padded(abs(offsetMinutes) / 60, 2) + (token == "Z" ? ":" : "") + padded(abs(offsetMinutes) % 60, 2)
        default: return token
        }
    }

    private static func ordinal(_ number: Int) -> String {
        let lastTwoDigits = number % 100
        if (11...13).contains(lastTwoDigits) { return "\(number)th" }
        switch number % 10 {
        case 1: return "\(number)st"
        case 2: return "\(number)nd"
        case 3: return "\(number)rd"
        default: return "\(number)th"
        }
    }
}
