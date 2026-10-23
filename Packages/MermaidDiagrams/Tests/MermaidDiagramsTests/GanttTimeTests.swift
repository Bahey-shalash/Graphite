import XCTest
@testable import MermaidDiagrams

/// Wall clock times: the calendar arithmetic in integers, the time zone's conversions, and the date forms of
/// JavaScript's `Date` that Mermaid falls back to.
final class GanttTimeTests: XCTestCase {
    private func time(_ year: Int64, _ month: Int64, _ day: Int64, _ hour: Int64 = 0, _ minute: Int64 = 0) throws -> GanttTime {
        try GanttScheduling.time(year, month, day, hour, minute)
    }

    func testDatesRoundTripThroughTheirDayNumber() throws {
        for (year, month, day) in [(1970, 1, 1), (2000, 2, 29), (1900, 3, 1), (-44, 3, 15), (2024, 12, 31), (275_000, 6, 1)] as [(Int64, Int64, Int64)] {
            let moment = try time(year, month, day)
            XCTAssertEqual(moment.date.year, year)
            XCTAssertEqual(moment.date.month, month)
            XCTAssertEqual(moment.date.day, day)
        }
        XCTAssertEqual(try time(1970, 1, 1).milliseconds, 0)
        XCTAssertEqual(try time(1970, 1, 1).weekday, 4, "A Thursday")
        XCTAssertEqual(try time(2024, 2, 3).weekday, 6, "A Saturday")
        XCTAssertEqual(try time(1969, 12, 31, 23, 30).date.day, 31)
    }

    func testFieldsPastTheirRangeRollOverAsJavaScriptsDateDoes() throws {
        XCTAssertEqual(try time(2014, 13, 1), try time(2015, 1, 1))
        XCTAssertEqual(try time(2014, 3, 0), try time(2014, 2, 28))
        XCTAssertEqual(try time(2014, 1, 1, 25), try time(2014, 1, 2, 1))
        XCTAssertNil(GanttTime(year: 300_001, month: 1, day: 1))
        XCTAssertNil(GanttTime(year: 2014, month: 1, day: Int64.max))
    }

    func testTheTimeZoneTurnsMomentsIntoWallClockTimesAndBack() throws {
        let paris = try GanttScheduling.zone("Europe/Paris")
        let winter = try XCTUnwrap(paris.wallClockTime(unixMilliseconds: 1_704_110_400_000))
        XCTAssertEqual(winter, try time(2024, 1, 1, 13), "12:00 UTC is 13:00 in Paris in winter")
        XCTAssertEqual(paris.unixMilliseconds(of: winter), 1_704_110_400_000)
        XCTAssertEqual(paris.offsetMinutes(at: try time(2024, 7, 1, 12)), 120)
        XCTAssertNil(paris.wallClockTime(unixMilliseconds: GanttTime.largestMilliseconds + 1))
    }

    func testTheFallbackReadsISODatesAtMidnightUTCAndOtherFormsOnTheWallClock() throws {
        let paris = try GanttScheduling.zone("Europe/Paris")
        XCTAssertEqual(GanttFallbackDate.parse("2014-01-06", zone: paris), try time(2014, 1, 6, 1))
        XCTAssertEqual(GanttFallbackDate.parse("2014", zone: paris), try time(2014, 1, 1, 1))
        XCTAssertEqual(GanttFallbackDate.parse("2014-01-06T10:30", zone: paris), try time(2014, 1, 6, 10, 30))
        XCTAssertEqual(GanttFallbackDate.parse("2014-01-06T10:30:00Z", zone: paris), try time(2014, 1, 6, 11, 30))
        XCTAssertEqual(GanttFallbackDate.parse("2014-01-06T10:30:00.5+02:00", zone: paris)?.milliseconds,
                       try time(2014, 1, 6, 9, 30).milliseconds + 500)
        XCTAssertEqual(GanttFallbackDate.parse("2014-1-6", zone: paris), try time(2014, 1, 6))
        XCTAssertEqual(GanttFallbackDate.parse("2014/01/06 9:15", zone: paris), nil, "A time needs two digits for its hour")
        XCTAssertEqual(GanttFallbackDate.parse("2014/01/06 09:15", zone: paris), try time(2014, 1, 6, 9, 15))
        for text in ["March 7, 2014", "2014-13-01", "0", "", "2014-01-06T25:00", "20000-01-01T00:00"] {
            XCTAssertNil(GanttFallbackDate.parse(text, zone: paris), text)
        }
    }
}
