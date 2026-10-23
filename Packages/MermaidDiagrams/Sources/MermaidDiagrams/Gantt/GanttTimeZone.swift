import Foundation

/// The time zone a Gantt chart is drawn in, given by the caller: it turns moments (milliseconds of Unix time) into the
/// wall clock times the chart is scheduled in, and back. The same time zone gives the same answers on every device.
struct GanttTimeZone {
    let timeZone: TimeZone

    /// The wall clock time at a moment, or nil past what a date can hold.
    func wallClockTime(unixMilliseconds: Int64) -> GanttTime? {
        guard abs(unixMilliseconds) <= GanttTime.largestMilliseconds else { return nil }
        let wallClock = unixMilliseconds + offsetMilliseconds(atUnixMilliseconds: unixMilliseconds)
        guard abs(wallClock) <= GanttTime.largestMilliseconds else { return nil }
        return GanttTime(milliseconds: wallClock)
    }

    /// The moment a wall clock time is: its offset is guessed from the time itself, then taken at the guessed moment.
    func unixMilliseconds(of time: GanttTime) -> Int64 {
        let guess = time.milliseconds - offsetMilliseconds(atUnixMilliseconds: time.milliseconds)
        return time.milliseconds - offsetMilliseconds(atUnixMilliseconds: guess)
    }

    /// How far ahead of UTC the wall clock is at `time`, in minutes rounded to a quarter hour, as Mermaid's date
    /// library writes it.
    func offsetMinutes(at time: GanttTime) -> Int64 {
        let minutes = Double(time.milliseconds - unixMilliseconds(of: time)) / Double(GanttTime.millisecondsPerMinute)
        return Int64((minutes / 15).rounded(.toNearestOrAwayFromZero)) * 15
    }

    private func offsetMilliseconds(atUnixMilliseconds milliseconds: Int64) -> Int64 {
        let moment = Date(timeIntervalSince1970: Double(milliseconds) / Double(GanttTime.millisecondsPerSecond))
        return Int64(timeZone.secondsFromGMT(for: moment)) * GanttTime.millisecondsPerSecond
    }
}
