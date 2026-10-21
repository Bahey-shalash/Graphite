import XCTest
@testable import GraphiteCore

final class PhotoFileNameTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, timeZone: TimeZone) -> (Date, Calendar) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(calendar: calendar, timeZone: timeZone, year: year, month: month, day: day, hour: hour, minute: minute)
        return (components.date ?? .distantPast, calendar)
    }

    func testTheNameIsTheDayAndTheMinute() throws {
        let (moment, calendar) = date(2026, 10, 21, 14, 5, timeZone: try XCTUnwrap(TimeZone(identifier: "Europe/Zurich")))
        XCTAssertEqual(PhotoFileName.stem(createdAt: moment, calendar: calendar), "Photo 2026-10-21 14.05")
    }

    func testTheTimeOfDayIsReadInTheCalendarsTimeZone() throws {
        let (moment, zurich) = date(2026, 1, 2, 23, 59, timeZone: try XCTUnwrap(TimeZone(identifier: "Europe/Zurich")))
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        XCTAssertEqual(PhotoFileName.stem(createdAt: moment, calendar: zurich), "Photo 2026-01-02 23.59")
        XCTAssertEqual(PhotoFileName.stem(createdAt: moment, calendar: tokyo), "Photo 2026-01-03 07.59")
    }

    func testTheYearIsGregorianWhateverTheDevicesCalendar() throws {
        let (moment, _) = date(2026, 10, 21, 9, 0, timeZone: try XCTUnwrap(TimeZone(identifier: "UTC")))
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertTrue(PhotoFileName.stem(createdAt: moment, calendar: gregorian).hasPrefix("Photo 2026-"))
    }
}
