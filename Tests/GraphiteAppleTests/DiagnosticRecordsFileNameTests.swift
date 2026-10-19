import XCTest
@testable import GraphiteApple

/// The names of the diagnostic records in `Library/Diagnostics`: the developer's tools copy
/// the folder off a device and sort and parse the files by these names.
final class DiagnosticRecordsFileNameTests: XCTestCase {
    func testTheFolderAndTheNumberOfFilesKept() {
        XCTAssertEqual(DiagnosticRecords.folderName, "Diagnostics")
        XCTAssertEqual(DiagnosticRecords.maximumFileCount, 80)
        XCTAssertEqual(DiagnosticRecords.folder?.lastPathComponent, "Diagnostics")
        XCTAssertEqual(DiagnosticRecords.folder?.deletingLastPathComponent().lastPathComponent, "Library")
    }

    func testATimestampIsUniversalTimeWithMillisecondsWhateverTheTimeZone() {
        let date = Date(timeIntervalSince1970: 1_791_891_782.512)
        XCTAssertEqual(DiagnosticRecords.timestamp(date), "2026-10-13T11:43:02.512Z")
        let previousTimeZone = NSTimeZone.default
        defer { NSTimeZone.default = previousTimeZone }
        for identifier in ["Pacific/Auckland", "America/Los_Angeles", "Asia/Kolkata"] {
            NSTimeZone.default = TimeZone(identifier: identifier) ?? previousTimeZone
            XCTAssertEqual(DiagnosticRecords.timestamp(date), "2026-10-13T11:43:02.512Z", identifier)
        }
    }

    func testAFileTimestampReplacesColonsWithHyphensAndKeepsEverythingElse() {
        let date = Date(timeIntervalSince1970: 1_791_891_782.512)
        XCTAssertEqual(DiagnosticRecords.fileTimestamp(date), "2026-10-13T11-43-02.512Z")
        XCTAssertFalse(DiagnosticRecords.fileTimestamp(date).contains(":"))
        XCTAssertEqual("MainThreadStall-\(DiagnosticRecords.fileTimestamp(date)).json", "MainThreadStall-2026-10-13T11-43-02.512Z.json")
    }

    func testRecordNamesSortInTimeOrderAsTextWithinOneKind() {
        let earlier = DiagnosticRecords.fileTimestamp(Date(timeIntervalSince1970: 1_791_891_782.512))
        let later = DiagnosticRecords.fileTimestamp(Date(timeIntervalSince1970: 1_791_891_782.513))
        let muchLater = DiagnosticRecords.fileTimestamp(Date(timeIntervalSince1970: 1_791_895_000))
        XCTAssertLessThan(earlier, later)
        XCTAssertLessThan(later, muchLater)
    }
}
