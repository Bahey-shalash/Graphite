import XCTest
@testable import MermaidDiagrams

/// Pele's fixed examples of Mermaid's date library (`tests/gantt/dates.test.ts`), which Pele compared with dayjs
/// 1.11: strict reading and writing, on a wall clock where today is 2031-05-06 09:30:15.250.
final class GanttDateFormatTests: XCTestCase {
    private func time(_ year: Int64, _ month: Int64, _ day: Int64, _ hour: Int64 = 0, _ minute: Int64 = 0, _ second: Int64 = 0,
                      _ millisecond: Int64 = 0) throws -> GanttTime {
        try GanttScheduling.time(year, month, day, hour, minute, second, millisecond)
    }

    private func parse(_ text: String, _ template: String, zone: GanttTimeZone? = nil) throws -> GanttTime? {
        GanttDateFormat(template).parse(text, now: try time(2031, 5, 6, 9, 30, 15, 250), zone: try zone ?? GanttScheduling.zone("UTC"))
    }

    private func format(_ time: GanttTime, _ template: String, zone: GanttTimeZone? = nil) throws -> String? {
        GanttDateFormat(template).format(time, zone: try zone ?? GanttScheduling.zone("UTC"))
    }

    func testDatesAreReadInTheirFormat() throws {
        let cases: [(String, String, GanttTime)] = [
            ("2014-01-06", "YYYY-MM-DD", try time(2014, 1, 6)), ("06-01-2014", "DD-MM-YYYY", try time(2014, 1, 6)),
            ("14/1/6", "YY/M/D", try time(2014, 1, 6)), ("70/12/31", "YY/M/D", try time(1970, 12, 31)),
            ("2014-01-06 17:49", "YYYY-MM-DD HH:mm", try time(2014, 1, 6, 17, 49)), ("2014-01-06 7:5:9", "YYYY-MM-DD H:m:s", try time(2014, 1, 6, 7, 5, 9)),
            ("2014-01-06T07:05:09.123", "YYYY-MM-DDTHH:mm:ss.SSS", try time(2014, 1, 6, 7, 5, 9, 123)), ("9:30 PM", "h:mm A", try time(2031, 5, 6, 21, 30)),
            ("12:05 am", "hh:mm a", try time(2031, 5, 6, 0, 5)), ("12:05 pm", "hh:mm a", try time(2031, 5, 6, 12, 5)),
            ("Jan 5, 2024", "MMM D, YYYY", try time(2024, 1, 5)), ("5th January 2024", "Do MMMM YYYY", try time(2024, 1, 5)),
            ("22nd December 2024", "Do MMMM YYYY", try time(2024, 12, 22)), ("on 2024-03-01", "[on] YYYY-MM-DD", try time(2024, 3, 1)),
            ("17:49", "HH:mm", try time(2031, 5, 6, 17, 49)), ("2024", "YYYY", try time(2024, 1, 1)), ("03", "MM", try time(2031, 3, 1)),
            ("7", "D", try time(2031, 5, 7)), ("20", "ss", try time(2031, 5, 6, 0, 0, 20)), ("2 2024", "Q YYYY", try time(2024, 4, 1)),
            ("Monday 2024", "dddd YYYY", try time(2024, 1, 1)),
        ]
        for (text, template, expected) in cases {
            XCTAssertEqual(try parse(text, template), expected, "\(text) as \(template)")
        }
    }

    func testTextThatDoesNotWriteBackTheSameIsRefused() throws {
        let cases = [("2014-1-6", "YYYY-MM-DD"), ("2014-01-06 7:05:09", "YYYY-MM-DD H:m:s"), ("2014-13-01", "YYYY-MM-DD"), ("2014-02-30", "YYYY-MM-DD"),
                     ("202-12-01", "YYYY-MM-DD"), ("202304", "YYYYMMDD"), ("2014-01-06 ", "YYYY-MM-DD"), (" 2014-01-06", "YYYY-MM-DD"),
                     ("2014-01-06x", "YYYY-MM-DD"), ("0", "ss"), ("25:00", "HH:mm"), ("5 January 2024", "Do MMMM YYYY"),
                     ("5th january 2024", "Do MMMM YYYY"), ("Tuesday 2024", "dddd YYYY"), ("2014-01-06", ""), ("2014-01-06", "q"),
                     ("12/25/2020", "L"), ("2020-01", "YYYY-ww"), ("Invalid Date", ""), ("", "YYYY-MM-DD")]
        for (text, template) in cases {
            XCTAssertNil(try parse(text, template), "\(text) as \(template)")
        }
    }

    func testUnixTimeIsReadInSecondsAndMilliseconds() throws {
        XCTAssertEqual(try parse("1410715640", "X")?.milliseconds, 1_410_715_640_000)
        XCTAssertEqual(try parse("1410715640579", "x")?.milliseconds, 1_410_715_640_579)
        XCTAssertEqual(try parse("-5", "x")?.milliseconds, -5)
        for (text, template) in [("1410715640.579", "X"), ("1e3", "x"), ("", "x")] { XCTAssertNil(try parse(text, template), text) }
    }

    func testAnOffsetIsReadOnlyWhenItIsTheWallClocksOwn() throws {
        let paris = try GanttScheduling.zone("Europe/Paris")
        XCTAssertEqual(try parse("2024-01-05T10:00:00+01:00", "YYYY-MM-DDTHH:mm:ssZ", zone: paris), try time(2024, 1, 5, 10))
        XCTAssertEqual(try parse("2024-01-05T10:00:00+0100", "YYYY-MM-DDTHH:mm:ssZZ", zone: paris), try time(2024, 1, 5, 10))
        XCTAssertNil(try parse("2024-01-05T10:00:00+05:45", "YYYY-MM-DDTHH:mm:ssZ", zone: paris))
    }

    func testTimesAreWrittenInEveryToken() throws {
        let date = try time(2024, 2, 3, 15, 4, 5, 67)
        let cases = [("YYYY-MM-DD", "2024-02-03"), ("YY M D", "24 2 3"), ("MMM MMMM", "Feb February"), ("d dd ddd dddd", "6 Sa Sat Saturday"),
                     ("H HH h hh", "15 15 3 03"), ("m mm s ss SSS", "4 04 5 05 067"), ("a A", "pm PM"), ("Do [of] MMMM", "3rd of February"),
                     ("Q", "1"), ("k kk", "15 15"), ("W WW GGGG", "5 05 2024"), ("[YYYY] YYYY", "YYYY 2024"), ("Y YYY", "Y 24Y"), ("S SS", "S SS")]
        for (template, expected) in cases {
            XCTAssertEqual(try format(date, template), expected, template)
        }
        let paris = try GanttScheduling.zone("Europe/Paris")
        XCTAssertEqual(try format(date, "Z", zone: paris), "+01:00")
        XCTAssertEqual(try format(date, "ZZ", zone: paris), "+0100")
        XCTAssertEqual(try format(date, "", zone: paris), "2024-02-03T15:04:05+01:00")
        XCTAssertEqual(try format(date, "x", zone: paris), String(1_706_969_045_067))
    }

    func testOrdinalsMidnightAndIsoWeeksAtTheEdgesOfAYear() throws {
        let ordinals = try [1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 31].map { day in try format(try time(2024, 1, Int64(day)), "Do") }
        XCTAssertEqual(ordinals, ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd", "31st"])
        XCTAssertEqual(try format(try time(2024, 1, 1, 0, 30), "k h a"), "24 12 am")
        XCTAssertEqual(try format(try time(2021, 1, 3), "GGGG-[W]WW"), "2020-W53")
        XCTAssertEqual(try format(try time(2024, 12, 30), "GGGG-[W]WW"), "2025-W01")
        XCTAssertEqual(try format(try time(2026, 1, 1), "W"), "1")
    }

    func testTokensMermaidsLibraryCannotWriteWriteNothing() throws {
        let date = try time(2024, 2, 3)
        for template in ["w", "ww", "wo", "gggg", "z", "zzz", "YYYY-ww"] { XCTAssertNil(try format(date, template), template) }
        XCTAssertEqual(try format(date, "[w] YYYY"), "w 2024")
    }
}
