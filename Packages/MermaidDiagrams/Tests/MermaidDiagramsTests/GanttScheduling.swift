import Foundation
@testable import MermaidDiagrams

/// Wall clock times, time zones and schedules for Gantt tests, which never read the current date: `now` is given.
enum GanttScheduling {
    struct UnknownTimeZone: Error {}
    struct OutOfRange: Error {}

    static func zone(_ identifier: String) throws -> GanttTimeZone {
        guard let timeZone = TimeZone(identifier: identifier) else { throw UnknownTimeZone() }
        return GanttTimeZone(timeZone: timeZone)
    }

    static func time(_ year: Int64, _ month: Int64, _ day: Int64, _ hour: Int64 = 0, _ minute: Int64 = 0, _ second: Int64 = 0,
                     _ millisecond: Int64 = 0) throws -> GanttTime {
        guard let time = GanttTime(year: year, month: month, day: day, hour: hour, minute: minute, second: second, millisecond: millisecond) else {
            throw OutOfRange()
        }
        return time
    }

    /// 2026-10-23 15:30, the day these tests stand on.
    static func now() throws -> GanttTime {
        try time(2026, 10, 23, 15, 30)
    }

    static func schedule(_ source: String, now: GanttTime? = nil, zone: GanttTimeZone? = nil,
                         limits: MermaidDiagramLimits = .standard) throws -> (chart: GanttChart, entries: [GanttSchedule.Entry]) {
        let chart = try GanttChartReading.ganttChart(source, limits: limits)
        let schedule = try GanttSchedule(chart: chart, now: try now ?? Self.now(), zone: try zone ?? Self.zone("Europe/Paris"), limits: limits)
        return (chart, schedule.entries)
    }

    /// The error scheduling `source` throws, or nil when it schedules.
    static func scheduleError(_ source: String, limits: MermaidDiagramLimits = .standard) -> GanttLayoutError? {
        do {
            _ = try schedule(source, limits: limits)
            return nil
        } catch let error as GanttLayoutError {
            return error
        } catch {
            return nil
        }
    }
}
