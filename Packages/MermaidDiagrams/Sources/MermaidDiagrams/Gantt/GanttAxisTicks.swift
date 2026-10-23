import Foundation

/// Where a Gantt chart's axis puts its dates, as d3's time scale chooses them for Mermaid: about `count` ticks at
/// round times (every 1, 5, 15 or 30 seconds or minutes, 1, 3, 6 or 12 hours, 1 or 2 days, a week from Sunday, 1
/// or 3 months, or a number of years), on the wall clock.
enum GanttAxisTicks {
    /// The interval steps d3 chooses among, each with its length in milliseconds.
    private static let automaticIntervals: [(unit: GanttTickUnit, step: Int64, milliseconds: Double)] = [
        (.second, 1, 1_000), (.second, 5, 5_000), (.second, 15, 15_000), (.second, 30, 30_000), (.minute, 1, 60_000), (.minute, 5, 300_000),
        (.minute, 15, 900_000), (.minute, 30, 1_800_000), (.hour, 1, 3_600_000), (.hour, 3, 10_800_000), (.hour, 6, 21_600_000),
        (.hour, 12, 43_200_000), (.day, 1, 86_400_000), (.day, 2, 172_800_000), (.week, 1, 604_800_000), (.month, 1, 2_592_000_000),
        (.month, 3, 7_776_000_000), (.year, 1, 31_536_000_000),
    ]
    private static let yearMilliseconds = 31_536_000_000.0

    /// The ticks from `start` to `stop`, both included, or none when there would be more than d3 allows.
    static func automatic(from start: GanttTime, to stop: GanttTime, count: Int) -> [GanttTime] {
        let target = Double(stop.milliseconds - start.milliseconds) / Double(count)
        let index = automaticIntervals.firstIndex { interval in interval.milliseconds > target } ?? automaticIntervals.count
        let interval: GanttTickInterval
        if index == automaticIntervals.count {
            let years = step(from: Double(start.milliseconds) / yearMilliseconds, to: Double(stop.milliseconds) / yearMilliseconds, count: count)
            interval = GanttTickInterval(unit: .year, step: wholeStep(years))
        } else if index == 0 {
            let milliseconds = step(from: Double(start.milliseconds), to: Double(stop.milliseconds), count: count)
            interval = GanttTickInterval(unit: .millisecond, step: wholeStep(milliseconds))
        } else {
            let before = automaticIntervals[index - 1]
            let chosen = target / before.milliseconds < automaticIntervals[index].milliseconds / target ? before : automaticIntervals[index]
            interval = GanttTickInterval(unit: chosen.unit, step: chosen.step)
        }
        return interval.ticks(from: start, to: stop, limit: 4 * count + 8) ?? []
    }

    /// The units `tickInterval` names, each with the most values its field takes and its length in milliseconds.
    private static let namedUnits: [String: (unit: GanttTickUnit, cycle: Int64?, milliseconds: Double)] = [
        "millisecond": (.millisecond, nil, 1), "second": (.second, 60, 1_000), "minute": (.minute, 60, 60_000), "hour": (.hour, 24, 3_600_000),
        "day": (.day, 31, 86_400_000), "week": (.week, nil, 604_800_000), "month": (.month, 12, 2_592_000_000),
    ]

    /// The ticks `tickInterval` asks for (a whole number from 1, then `millisecond`, `second`, `minute`, `hour`, `day`,
    /// `week` or `month`), weeks starting on `weekStart`; nil when the text is not one, or asks for more than `limit`.
    static func interval(_ text: String, weekStart: GanttWeekday, from start: GanttTime, to stop: GanttTime, limit: Int) -> [GanttTime]? {
        let digits = text.prefix { character in character.isASCII && character.isNumber }
        guard let first = digits.first, first != "0", let step = Int64(digits),
              let named = namedUnits[String(text.dropFirst(digits.count))] else { return nil }
        let smallestStep = Double(min(step, named.cycle ?? step)) * named.milliseconds
        guard Double(stop.milliseconds - start.milliseconds) / smallestStep <= Double(limit) else { return nil }
        return GanttTickInterval(unit: named.unit, step: step, weekStart: weekStart.rawValue).ticks(from: start, to: stop, limit: limit)
    }

    /// A step of at least one, whole: a start equal to its stop gives no finite step, and one tick.
    private static func wholeStep(_ step: Double) -> Int64 {
        guard step.isFinite, step >= 1, step < Double(GanttTime.largestMilliseconds) else { return 1 }
        return Int64(step)
    }

    /// d3's `tickStep`: a step of 1, 2 or 5 times a power of ten giving about `count` steps between the bounds.
    static func step(from start: Double, to stop: Double, count: Int) -> Double {
        let rawStep = (stop - start) / Double(max(0, count))
        let power = (log10(rawStep)).rounded(.down)
        let error = rawStep / pow(10, power)
        let factor: Double = error >= 50.squareRoot() ? 10 : error >= 10.squareRoot() ? 5 : error >= 2.squareRoot() ? 2 : 1
        return pow(10, power) * factor
    }
}

/// A unit of time an axis' ticks fall on.
enum GanttTickUnit {
    case millisecond, second, minute, hour, day, week, month, year
}

/// A tick interval as d3's `unit.every(step)` gives it: times that are whole units, and among those, for seconds to
/// months, the ones whose field (seconds, minutes, hours, day of the month less one, month) is a multiple of the step.
struct GanttTickInterval {
    let unit: GanttTickUnit
    let step: Int64
    /// The day weeks start on, 0 for Sunday.
    var weekStart: Int64 = 0

    /// The ticks from `start` to `stop` included, or nil when there would be more than `limit`.
    func ticks(from start: GanttTime, to stop: GanttTime, limit: Int) -> [GanttTime]? {
        guard var tick = floor(GanttTime(milliseconds: start.milliseconds - 1)).flatMap({ time in next(after: time) }) else { return [] }
        var ticks: [GanttTime] = []
        var previous = Int64.min
        while tick <= stop, tick.milliseconds > previous {
            guard ticks.count < limit else { return nil }
            previous = tick.milliseconds
            ticks.append(tick)
            guard let following = next(after: tick) else { break }
            tick = following
        }
        return ticks
    }

    /// The first interval boundary after `time`.
    private func next(after time: GanttTime) -> GanttTime? {
        offset(time, by: 1).flatMap(floor)
    }

    /// The latest interval boundary at or before `time`.
    func floor(_ time: GanttTime) -> GanttTime? {
        guard step > 1 else { return baseFloor(time) }
        switch unit {
        case .millisecond: return GanttTime(milliseconds: GanttTime.floorDivision(time.milliseconds, step) * step)
        case .year: return GanttTime(year: GanttTime.floorDivision(time.year, step) * step, month: 1, day: 1)
        case .week:
            guard let epochWeek = baseFloor(GanttTime(milliseconds: 0)), let floored = baseFloor(time) else { return nil }
            let weeks = GanttTime.floorDivision(floored.dayNumber - epochWeek.dayNumber, 7)
            return floored.addingDays(-7 * GanttTime.modulo(weeks, step))
        case .second, .minute, .hour, .day, .month:
            var floored = baseFloor(time)
            while let candidate = floored, !isOnStep(candidate) { floored = baseFloor(GanttTime(milliseconds: candidate.milliseconds - 1)) }
            return floored
        }
    }

    /// `time` moved on by `count` intervals.
    private func offset(_ time: GanttTime, by count: Int64) -> GanttTime? {
        switch unit {
        case .millisecond: return time.adding(milliseconds: count * step, unit: 1)
        case .year: return time.addingMonths(12 * count * step)
        case .week: return time.addingDays(7 * count * step)
        case .second, .minute, .hour, .day, .month:
            guard step > 1 else { return baseOffset(time, by: count) }
            var moved: GanttTime? = time
            for _ in 0..<count {
                repeat { moved = moved.flatMap { current in baseOffset(current, by: 1) } } while moved.map(isOnStep) == false
            }
            return moved
        }
    }

    /// Whether `time`'s field is a multiple of the step.
    private func isOnStep(_ time: GanttTime) -> Bool {
        let field: Int64
        switch unit {
        case .second: field = time.second
        case .minute: field = time.minute
        case .hour: field = time.hour
        case .day: field = time.day - 1
        case .month: field = time.month - 1
        case .millisecond, .week, .year: return true
        }
        return field % step == 0
    }

    private func baseFloor(_ time: GanttTime) -> GanttTime? {
        let milliseconds = time.milliseconds
        switch unit {
        case .millisecond: return time
        case .second: return GanttTime(milliseconds: milliseconds - GanttTime.modulo(milliseconds, GanttTime.millisecondsPerSecond))
        case .minute: return GanttTime(milliseconds: milliseconds - GanttTime.modulo(milliseconds, GanttTime.millisecondsPerMinute))
        case .hour: return GanttTime(milliseconds: milliseconds - GanttTime.modulo(milliseconds, GanttTime.millisecondsPerHour))
        case .day: return time.startOfDay
        case .week: return time.startOfDay.addingDays(-GanttTime.modulo(time.weekday - weekStart, 7))
        case .month: return GanttTime(year: time.year, month: time.month, day: 1)
        case .year: return GanttTime(year: time.year, month: 1, day: 1)
        }
    }

    private func baseOffset(_ time: GanttTime, by count: Int64) -> GanttTime? {
        switch unit {
        case .millisecond: return time.adding(milliseconds: count, unit: 1)
        case .second: return time.adding(milliseconds: count, unit: GanttTime.millisecondsPerSecond)
        case .minute: return time.adding(milliseconds: count, unit: GanttTime.millisecondsPerMinute)
        case .hour: return time.adding(milliseconds: count, unit: GanttTime.millisecondsPerHour)
        case .day: return time.addingDays(count)
        case .week: return time.addingDays(7 * count)
        case .month: return time.addingMonths(count)
        case .year: return time.addingMonths(12 * count)
        }
    }
}
