import XCTest
@testable import GraphiteCore

final class ScannedDocumentNameTests: XCTestCase {
    private func calendar(timeZoneIdentifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZoneIdentifier))
        return calendar
    }

    func testNameHasTheDateAndTheMinuteWithoutSeconds() throws {
        let date = Date(timeIntervalSince1970: 1_792_591_530) // 2026-10-21 14:05:30 UTC
        XCTAssertEqual(ScannedDocumentName.stem(createdAt: date, calendar: try calendar(timeZoneIdentifier: "UTC")), "Scan 2026-10-21 14.05")
    }

    func testTimeOfDayIsReadInTheCalendarsTimeZone() throws {
        let date = Date(timeIntervalSince1970: 1_792_591_530)
        XCTAssertEqual(ScannedDocumentName.stem(createdAt: date, calendar: try calendar(timeZoneIdentifier: "Europe/Zurich")), "Scan 2026-10-21 16.05")
    }

    func testSmallNumbersAreZeroPaddedSoNamesSortByDate() throws {
        let date = Date(timeIntervalSince1970: 1_767_513_960) // 2026-01-04 08:06:00 UTC
        XCTAssertEqual(ScannedDocumentName.stem(createdAt: date, calendar: try calendar(timeZoneIdentifier: "UTC")), "Scan 2026-01-04 08.06")
    }

    func testNameIsAllowedAsAFileName() throws {
        let stem = ScannedDocumentName.stem(createdAt: Date(timeIntervalSince1970: 1_792_591_530), calendar: try calendar(timeZoneIdentifier: "UTC"))
        XCTAssertNil(FileNameRules.problem(with: stem, isNote: false))
    }
}
