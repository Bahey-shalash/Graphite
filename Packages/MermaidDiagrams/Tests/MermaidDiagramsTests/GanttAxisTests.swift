import XCTest
@testable import MermaidDiagrams

/// The axis' formats and ticks, as d3-time-format and d3's time scale give them for Mermaid: Pele's fixed examples
/// (`tests/gantt/dates.test.ts`), which Pele compared with d3-time 3 and d3-time-format 4.
final class GanttAxisTests: XCTestCase {
    private func time(_ year: Int64, _ month: Int64, _ day: Int64, _ hour: Int64 = 0, _ minute: Int64 = 0, _ second: Int64 = 0,
                      _ millisecond: Int64 = 0) throws -> GanttTime {
        try GanttScheduling.time(year, month, day, hour, minute, second, millisecond)
    }

    private func format(_ specifier: String, _ time: GanttTime) throws -> String {
        GanttAxisFormat.format(specifier, time, zone: try GanttScheduling.zone("Europe/Paris"))
    }

    func testEverySpecifierIsWritten() throws {
        let date = try time(2024, 2, 3, 15, 4, 5, 67)
        let cases = [("%Y-%m-%d", "2024-02-03"), ("%a %A %b %B", "Sat Saturday Feb February"), ("%H:%M:%S.%L", "15:04:05.067"), ("%I %p", "03 PM"),
                     ("%e|%-d|%_d|%0e", " 3|3| 3|03"), ("%j", "034"), ("%U %W %V", "04 05 05"), ("%u %w", "6 6"), ("%y %G %g", "24 2024 24"),
                     ("%q", "1"), ("%x", "2/3/2024"), ("%X", "3:04:05 PM"), ("%c", "2/3/2024, 3:04:05 PM"), ("%f", "067000"), ("%%Y %k %", "%Y k "),
                     ("%s", "1706969045"), ("%Q", "1706969045067"), ("%Z", "+0100")]
        for (specifier, expected) in cases {
            XCTAssertEqual(try format(specifier, date), expected, specifier)
        }
    }

    func testWeeksAreNumberedFromTheFirstSundayTheFirstMondayAndByISORules() throws {
        XCTAssertEqual(try format("%U %W %V %G", try time(2023, 1, 1)), "01 00 52 2022")
        XCTAssertEqual(try format("%U %W %V %G", try time(2024, 12, 30)), "52 53 01 2025")
        XCTAssertEqual(try format("%U %W %V", try time(2024, 1, 1)), "00 01 01")
    }

    func testTicksFallOnRoundStepsForTheSpan() throws {
        func ticks(_ start: GanttTime, _ stop: GanttTime, _ count: Int) -> [Int64] {
            GanttAxisTicks.automatic(from: start, to: stop, count: count).map(\.milliseconds)
        }
        XCTAssertEqual(ticks(try time(2014, 1, 1), try time(2014, 2, 20), 10), try (0..<7).map { week in try time(2014, 1, 5 + 7 * week).milliseconds })
        XCTAssertEqual(ticks(try time(2024, 1, 10, 9), try time(2024, 1, 10, 18), 10), try (9...18).map { hour in try time(2024, 1, 10, hour).milliseconds })
        XCTAssertEqual(ticks(try time(1900, 1, 1), try time(2020, 1, 1), 10), try (0..<13).map { decade in try time(1900 + 10 * decade, 1, 1).milliseconds })
        XCTAssertEqual(ticks(try time(2024, 1, 1), try time(2024, 7, 31), 7), try (1...7).map { month in try time(2024, month, 1).milliseconds })
        XCTAssertEqual(ticks(GanttTime(milliseconds: 0), GanttTime(milliseconds: 71_000), 10), (0..<15).map { step in Int64(step) * 5_000 })
        XCTAssertEqual(ticks(GanttTime(milliseconds: 0), GanttTime(milliseconds: 30), 10), stride(from: 0, through: 30, by: 2).map(Int64.init))
    }

    func testAChartSpanningNoTimeHasOneTick() throws {
        let moment = try time(2024, 1, 1)
        XCTAssertEqual(GanttAxisTicks.automatic(from: moment, to: moment, count: 8), [moment])
    }

    func testATickIntervalFollowsItsUnitAndTheWeekdayWeeksStartOn() throws {
        let start = try time(2024, 1, 1)
        let stop = try time(2024, 1, 31)
        func ticks(_ interval: String, _ weekStart: GanttWeekday = .sunday, from: GanttTime? = nil, to: GanttTime? = nil, limit: Int = 100) -> [GanttTime]? {
            GanttAxisTicks.interval(interval, weekStart: weekStart, from: from ?? start, to: to ?? stop, limit: limit)
        }
        XCTAssertEqual(ticks("1week", .monday), try [1, 8, 15, 22, 29].map { day in try time(2024, 1, day) })
        XCTAssertEqual(ticks("1week"), try [7, 14, 21, 28].map { day in try time(2024, 1, day) })
        XCTAssertEqual(ticks("1week", .thursday), try [4, 11, 18, 25].map { day in try time(2024, 1, day) })
        XCTAssertEqual(ticks("10day"), try [1, 11, 21, 31].map { day in try time(2024, 1, day) })
        XCTAssertEqual(ticks("1month", to: try time(2024, 4, 2)), try (1...4).map { month in try time(2024, month, 1) })
        XCTAssertEqual(ticks("6hour", to: try time(2024, 1, 2)), try [0, 6, 12, 18, 24].map { hour in try time(2024, 1, 1, hour) })
        XCTAssertEqual(ticks("15minute", from: try time(2024, 1, 1, 9, 5), to: try time(2024, 1, 1, 10)),
                       try [15, 30, 45, 60].map { minute in try time(2024, 1, 1, 9, minute) })
        XCTAssertLessThanOrEqual(try XCTUnwrap(ticks("2week", .monday)).count, 3)
    }

    func testAnIntervalNotKnownOrAskingForTooManyTicksIsDeclined() throws {
        let start = try time(2024, 1, 1)
        let stop = try time(2024, 1, 31)
        for interval in ["", "1decade", "1year", "0day", "01day", "1 day", "1days", "day", "1.5day", "-1day"] {
            XCTAssertNil(GanttAxisTicks.interval(interval, weekStart: .sunday, from: start, to: stop, limit: 100), interval)
        }
        XCTAssertNil(GanttAxisTicks.interval("1second", weekStart: .sunday, from: start, to: stop, limit: 1_000))
        XCTAssertNil(GanttAxisTicks.interval("99999999second", weekStart: .sunday, from: start, to: stop, limit: 1_000))
        XCTAssertEqual(GanttAxisTicks.interval("1day", weekStart: .sunday, from: start, to: stop, limit: 100)?.count, 31)
    }
}
