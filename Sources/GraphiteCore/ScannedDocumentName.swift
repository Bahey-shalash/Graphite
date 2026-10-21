import Foundation

/// The name a scanned document gets: "Scan 2026-10-21 14.05", like the camera's
/// "Photo 2026-09-23 22.18.05" without the seconds. A second scan in the same minute is
/// numbered by the vault's free-name rule, so the name only has to be readable and sort by date.
public enum ScannedDocumentName {
    /// The year is read from `calendar`, which callers pass as Gregorian so names sort by date
    /// whatever calendar the device uses; the time of day is read in the calendar's time zone.
    public static func stem(createdAt date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let year = String(format: "%04d", components.year ?? 0)
        let monthAndDay = [components.month, components.day].map { number in String(format: "%02d", number ?? 0) }
        let hourAndMinute = [components.hour, components.minute].map { number in String(format: "%02d", number ?? 0) }
        return "Scan \(year)-\(monthAndDay.joined(separator: "-")) \(hourAndMinute.joined(separator: "."))"
    }
}
