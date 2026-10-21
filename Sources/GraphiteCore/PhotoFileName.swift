import Foundation

/// The name a picture made from the New menu gets: "Photo 2026-10-21 14.05".
public enum PhotoFileName {
    /// The year is read from `calendar`, which callers pass as Gregorian so names sort by date
    /// whatever calendar the device uses; the time of day is read in the calendar's time zone.
    public static func stem(createdAt date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let year = String(format: "%04d", components.year ?? 0)
        let monthAndDay = [components.month, components.day].map { number in String(format: "%02d", number ?? 0) }
        let hourAndMinute = [components.hour, components.minute].map { number in String(format: "%02d", number ?? 0) }
        return "Photo \(year)-\(monthAndDay.joined(separator: "-")) \(hourAndMinute.joined(separator: "."))"
    }
}
