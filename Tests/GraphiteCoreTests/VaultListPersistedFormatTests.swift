import XCTest
@testable import GraphiteCore

/// The vault list as the device's preferences store it: JSON whose dates are the encoder's
/// default, seconds since 2001-01-01 00:00:00 UTC. Changing that needs a versioned decoder,
/// because lists written by earlier builds are read by this one.
final class VaultListPersistedFormatTests: XCTestCase {
    private let studyIdentifier = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let bookmarkedIdentifier = UUID(uuidString: "AAAAAAAA-2222-3333-4444-555555555555")!

    /// 2026-05-09 06:13:20 UTC.
    private let studyOpenedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// 2026-05-09 06:15:00.5 UTC.
    private let bookmarkedOpenedDate = Date(timeIntervalSinceReferenceDate: 800_000_100.5)

    private let goldenList = """
    {"vaults":[{"id":"11111111-2222-3333-4444-555555555555","lastKnownPath":"\\/x\\/Study","lastOpenedDate":800000000,\
    "lastOpenedDocument":{"rawValue":"Notes\\/Today.md"},"location":{"anchor":{"applicationDocuments":{}},"relativePath":"Study"},"name":"Study"},\
    {"id":"AAAAAAAA-2222-3333-4444-555555555555","lastKnownPath":"\\/x\\/B","lastOpenedDate":800000100.5,\
    "location":{"anchor":{"bookmark":{"_0":"AQID"}},"relativePath":""},"name":"B"}]}
    """

    private func makeList() throws -> VaultList {
        var list = VaultList()
        list.recordOpening(identifier: studyIdentifier, name: "Study", location: VaultLocation(anchor: .applicationDocuments, relativePath: "Study"),
                           path: "/x/Study", at: studyOpenedDate)
        list.recordOpening(identifier: bookmarkedIdentifier, name: "B", location: VaultLocation(anchor: .bookmark(Data([1, 2, 3])), relativePath: ""),
                           path: "/x/B", at: bookmarkedOpenedDate)
        list.setLastOpenedDocument(try VaultPath("Notes/Today.md"), inVault: studyIdentifier)
        return list
    }

    func testListEncodesWithTheseFieldNamesAndDatesAsSecondsSince2001() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(String(decoding: try encoder.encode(try makeList()), as: UTF8.self), goldenList)
    }

    func testListStoredByAnEarlierBuildDecodesWithItsDatesAndDocuments() throws {
        let list = try JSONDecoder().decode(VaultList.self, from: Data(goldenList.utf8))
        XCTAssertEqual(list, try makeList())
        let study = try XCTUnwrap(list.vault(withIdentifier: studyIdentifier))
        XCTAssertEqual(study.lastOpenedDate, studyOpenedDate)
        XCTAssertEqual(ISO8601DateFormatter().string(from: study.lastOpenedDate), "2026-05-09T06:13:20Z")
        XCTAssertEqual(study.lastOpenedDocument, try VaultPath("Notes/Today.md"))
        XCTAssertEqual(list.vault(withIdentifier: bookmarkedIdentifier)?.lastOpenedDate, bookmarkedOpenedDate)
        XCTAssertEqual(list.mostRecentlyOpened?.id, bookmarkedIdentifier)
    }

    func testADateWrittenAsSecondsSince1970WouldReadAsAnotherInstant() throws {
        let list = try JSONDecoder().decode(VaultList.self, from: Data(goldenList.utf8))
        let reading = try XCTUnwrap(list.vault(withIdentifier: studyIdentifier)).lastOpenedDate.timeIntervalSince1970
        XCTAssertEqual(reading, 800_000_000 + Date.timeIntervalBetween1970AndReferenceDate, accuracy: 0.001)
        XCTAssertNotEqual(reading, 800_000_000, "The stored number counts from 2001, not from 1970.")
    }
}
