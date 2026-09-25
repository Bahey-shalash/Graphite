import XCTest
@testable import GraphiteCore

/// Bases date parsing, arithmetic and formatting compared with what Obsidian (JavaScript
/// dates and moment.js) produces for the same `.base` formulas.
final class CoreBasesDatesFixTests: XCTestCase {
    private static func calendar(_ timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        return calendar
    }

    private let newYork = CoreBasesDatesFixTests.calendar("America/New_York")
    private let utc = CoreBasesDatesFixTests.calendar("UTC")

    private func parse(_ text: String, calendar: Calendar? = nil) -> BaseDate? {
        BaseDateParsing.date(from: text, calendar: calendar ?? newYork)
    }

    private func utcText(_ date: Date?, _ pattern: String = "YYYY-MM-DD[T]HH:mm:ss.SSS") -> String? {
        date.map { date in BaseDateFormatting.format(date, pattern: pattern, calendar: utc) }
    }

    private func sum(_ text: String, _ durationText: String) throws -> BaseDate {
        let date = try XCTUnwrap(parse(text))
        let duration = try XCTUnwrap(BaseDurationParsing.duration(from: durationText))
        return BaseDateArithmetic.adding(duration, to: date, calendar: newYork)
    }

    private func newYorkText(_ date: BaseDate) -> String {
        BaseDateFormatting.format(date.date, pattern: "YYYY-MM-DD HH:mm", calendar: newYork)
    }

    // MARK: Values far outside the calendar

    func testUnixTimestampTokensClampForFarDates() {
        for seconds in [1e300, -1e300, Double.infinity] {
            let date = Date(timeIntervalSince1970: seconds)
            XCTAssertFalse(BaseDateFormatting.format(date, pattern: "x X", calendar: utc).isEmpty)
        }
        let date = parse("2025-06-01T10:00:00.007Z")?.date
        XCTAssertEqual(utcText(date, "x X"), "1748772000007 1748772000")
    }

    func testFarDatesAndHugeDurationsEvaluateWithoutTrapping() throws {
        let record = BaseTestRecords.record("Notes/Far.md")
        let evaluator = BaseEvaluator(formulas: [], environment: BaseTestRecords.environment(), thisRecord: nil, knownRecords: [record])
        for formula in ["date(1e300).relative()", "date(1e300).format(\"x X YYYY\")", "(file.mtime + \"99999999999999999999999999999 years\").relative()",
                        "duration(\"99999999999999999999999999999 years\")", "file.mtime - date(\"0001-01-01\") + duration(\"99999999999999999999999999999 ms\")"] {
            XCTAssertFalse(try evaluator.evaluate(sourceText: formula, for: record).displayText.isEmpty, formula)
        }
    }

    // MARK: Parsing

    func testOutOfRangeTimeFieldsAreNotDates() {
        XCTAssertNil(parse("2025-01-01 12:75"))
        XCTAssertNil(parse("2025-01-01 12:30:99"))
        XCTAssertNil(parse("2025-01-01 23:99"))
        XCTAssertNil(parse("2025-01-01 24:00"))
        XCTAssertEqual(parse("2025-01-01 23:59:59").map(newYorkText), "2025-01-01 23:59")
    }

    func testDateOnlyTextWithAnOffsetIsNotADate() {
        XCTAssertNil(parse("2025-01-01Z"))
        XCTAssertNil(parse("2025-01-01+05:00"))
        XCTAssertEqual(utcText(parse("2025-01-01T00:00Z")?.date), "2025-01-01T00:00:00.000")
        XCTAssertEqual(parse("2025-01-01")?.hasTime, false)
    }

    func testOffsetsAreAppliedExactlyOrRejected() {
        XCTAssertNil(parse("2025-01-01T10:00+99:00"))
        XCTAssertNil(parse("2025-01-01T10:00+05:75"))
        XCTAssertEqual(utcText(parse("2025-01-01T10:00+18:30")?.date), "2024-12-31T15:30:00.000")
        XCTAssertEqual(utcText(parse("2025-01-01T10:00-0330")?.date), "2025-01-01T13:30:00.000")
        XCTAssertEqual(utcText(parse("2025-01-01T10:00:05.250+05:30")?.date), "2025-01-01T04:30:05.250")
    }

    func testISODurationsNeedAnElement() {
        for text in ["P", "PT", "-P", "+P", "P1DT", "p"] {
            XCTAssertNil(BaseDurationParsing.duration(from: text), text)
        }
        XCTAssertEqual(BaseDurationParsing.duration(from: "PT0S")?.isZero, true)
        XCTAssertEqual(BaseDurationParsing.duration(from: "P1D"), BaseDuration(days: 1))
        XCTAssertEqual(BaseDurationParsing.duration(from: "-PT2H"), BaseDuration(milliseconds: -7_200_000))
        XCTAssertEqual(BaseDurationParsing.duration(from: "P1Y2M3W4DT5H6M7S"), BaseDuration(months: 14, days: 25, milliseconds: 18_367_000))
    }

    // MARK: Arithmetic

    func testMonthsAndYearsOverflowPastShortMonthsAsInObsidian() throws {
        XCTAssertEqual(newYorkText(try sum("2025-01-31", "1M")), "2025-03-03 00:00")
        XCTAssertEqual(newYorkText(try sum("2024-02-29", "1y")), "2025-03-01 00:00")
        XCTAssertEqual(newYorkText(try sum("2025-03-31", "-1M")), "2025-03-03 00:00")
        XCTAssertEqual(newYorkText(try sum("2025-01-15 09:45", "1M")), "2025-02-15 09:45")
        XCTAssertEqual(newYorkText(try sum("2024-12-01", "13M")), "2026-01-01 00:00")
        XCTAssertEqual(try sum("2025-01-31", "1M").hasTime, false)
    }

    func testHoursMoveTheWallClockAcrossDaylightSavingChanges() throws {
        XCTAssertEqual(newYorkText(try sum("2025-11-02", "24h")), "2025-11-03 00:00")
        XCTAssertEqual(newYorkText(try sum("2025-03-09", "24h")), "2025-03-10 00:00")
        XCTAssertEqual(newYorkText(try sum("2025-03-09 01:30", "1h")), "2025-03-09 03:30", "02:30 does not exist and moves forward, as in JavaScript.")
        XCTAssertEqual(newYorkText(try sum("2025-11-03", "-24h")), "2025-11-02 00:00")
        XCTAssertEqual(newYorkText(try sum("2025-11-02", "1d")), "2025-11-03 00:00")
        let repeatedHour = try sum("2025-11-03 01:30", "-1d")
        XCTAssertEqual(BaseDateFormatting.format(repeatedHour.date, pattern: "YYYY-MM-DD HH:mm Z", calendar: newYork), "2025-11-02 01:30 -04:00",
                       "A repeated local time takes its first occurrence, as in JavaScript, even from standard time.")
        let exactTime = try sum("2025-06-01T10:00:00.007Z", "1500ms")
        XCTAssertEqual(utcText(exactTime.date), "2025-06-01T10:00:01.507")
    }

    // MARK: Text

    func testDefaultTextKeepsSecondsLikeObsidiansToString() throws {
        let first = BaseValue.date(try XCTUnwrap(parse("2025-09-16 07:20:01", calendar: BaseDateFormatting.displayCalendar)))
        let second = BaseValue.date(try XCTUnwrap(parse("2025-09-16 07:20:41", calendar: BaseDateFormatting.displayCalendar)))
        XCTAssertEqual(first.displayText, "2025-09-16T07:20:01")
        XCTAssertNotEqual(first.displayText, second.displayText)
        XCTAssertEqual(BaseValue.date(try XCTUnwrap(parse("2025-09-16", calendar: BaseDateFormatting.displayCalendar))).displayText, "2025-09-16")
    }

    func testMomentLongFormatsAndFiveDigitYears() throws {
        let date = try XCTUnwrap(parse("2025-08-15T14:05:09Z")).date
        XCTAssertEqual(utcText(date, "YYYYY"), "02025")
        XCTAssertEqual(utcText(date, "LL"), "August 15, 2025")
        XCTAssertEqual(utcText(date, "l"), "8/15/2025")
        XCTAssertEqual(utcText(date, "L LT LTS"), "08/15/2025 2:05 PM 2:05:09 PM")
        XCTAssertEqual(utcText(date, "LLLL"), "Friday, August 15, 2025 2:05 PM")
        XCTAssertEqual(utcText(date, "llll"), "Fri, Aug 15, 2025 2:05 PM")
        XCTAssertEqual(utcText(date, "[LL] Y GG gg"), "LL 2025 25 25")
    }

    func testMillisecondTokensMatchTheWrittenMilliseconds() throws {
        for millisecond in 0..<1_000 {
            let writtenMilliseconds = String(format: "%03d", millisecond)
            let date = try XCTUnwrap(parse("2025-06-01T10:00:00.\(writtenMilliseconds)Z")).date
            XCTAssertEqual(utcText(date, "ss.SSS SS S"), "00.\(writtenMilliseconds) \(writtenMilliseconds.prefix(2)) \(writtenMilliseconds.prefix(1))")
        }
    }

    func testYearsBeforeTheCommonEraAreAstronomical() throws {
        XCTAssertEqual(utcText(parse("0000-01-01", calendar: utc)?.date, "YYYY-MM-DD YYYYYY"), "0000-01-01 +000000")
        let beforeCommonEra = try XCTUnwrap(utc.date(from: DateComponents(era: 0, year: 251, month: 10, day: 19)))
        XCTAssertEqual(utcText(beforeCommonEra, "YYYY-MM-DD YYYYYY YY"), "-0250-10-19 -000250 -50")
    }

    func testFormattingIsTheSameInEveryLocale() throws {
        let date = try XCTUnwrap(parse("2025-08-15T14:00:00Z")).date
        for localeIdentifier in ["en_US", "fr_FR", "ru_RU", "ja_JP", "ar_EG"] {
            var localizedCalendar = utc
            localizedCalendar.locale = Locale(identifier: localeIdentifier)
            let text = BaseDateFormatting.format(date, pattern: "Do MMMM YYYY, dddd h A", calendar: localizedCalendar)
            XCTAssertEqual(text, "15th August 2025, Friday 2 PM", localeIdentifier)
        }
    }

    func testRelativeTextRoundsBeforeComparingLikeMoment() {
        let now = Date(timeIntervalSince1970: 1_758_000_000)
        func relative(_ elapsedSeconds: Double) -> String {
            BaseDateFormatting.relativeText(from: now.addingTimeInterval(-elapsedSeconds), to: now)
        }
        XCTAssertEqual(relative(44), "a few seconds ago")
        XCTAssertEqual(relative(45), "a minute ago")
        XCTAssertEqual(relative(90), "2 minutes ago")
        XCTAssertEqual(relative(2_682), "an hour ago")
        XCTAssertEqual(relative(78_120), "a day ago")
        XCTAssertEqual(relative(2_220_480), "a month ago")
        XCTAssertEqual(relative(-3 * 86_400), "in 3 days")
        XCTAssertEqual(relative(320 * 86_400), "a year ago")
        XCTAssertEqual(relative(3 * 365.2425 * 86_400), "3 years ago")
    }

    func testDurationTextKeepsFractionalSeconds() {
        XCTAssertEqual(BaseDateFormatting.text(for: BaseDuration(milliseconds: 500)), "0.5 seconds")
        XCTAssertEqual(BaseDateFormatting.text(for: BaseDuration(milliseconds: 1_500)), "1.5 seconds")
        XCTAssertEqual(BaseDateFormatting.text(for: BaseDuration(milliseconds: 1_000)), "1 second")
        XCTAssertEqual(BaseDateFormatting.text(for: BaseDuration(milliseconds: 61_250)), "1 minute 1.25 seconds")
        XCTAssertEqual(BaseDateFormatting.text(for: BaseDuration(days: 2, milliseconds: 3 * 3_600_000)), "2 days 3 hours")
        XCTAssertEqual(BaseDateFormatting.text(for: BaseDuration()), "0 seconds")
    }
}
