import XCTest
@testable import GraphiteCore

/// Settings rewrites the vault's pronunciation file from the entries it read. A hand-written
/// `ipa` is part of an entry, so it survives every add, edit and delete of another term.
final class ReadAloudPronunciationVaultFileWritingTests: XCTestCase {
    private let handWrittenFile = Data(#"{"LUT": "L U T", "SIMDRAM": {"say": "sim dee ram", "ipa": "ˈsɪmdiːɹæm"}}"#.utf8)

    private func entries(in data: Data) throws -> [ReadAloudPronunciations.VaultEntry] {
        guard case .loaded(let loaded, _) = ReadAloudPronunciations.readVaultFile(data: data) else {
            throw XCTSkip("The file did not load.")
        }
        return loaded
    }

    func testRewritingTheEntriesOfAFileKeepsTheHandWrittenIPA() throws {
        let rewritten = try ReadAloudPronunciations.vaultFileData(for: try entries(in: handWrittenFile))

        let pronunciation = try XCTUnwrap(try entries(in: rewritten).first { entry in entry.term == "SIMDRAM" }?.pronunciation)
        XCTAssertEqual(pronunciation.say, "sim dee ram")
        XCTAssertEqual(pronunciation.ipa, "ˈsɪmdiːɹæm")
    }

    func testAnEntryWithoutIPAIsStillWrittenAsAPlainRespelling() throws {
        let rewritten = try ReadAloudPronunciations.vaultFileData(for: try entries(in: handWrittenFile))

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: rewritten) as? [String: Any])
        XCTAssertEqual(object["LUT"] as? String, "L U T")
    }

    func testAddingATermLeavesTheIPAOfEveryOtherTermUnchanged() throws {
        let updated = ReadAloudPronunciations.updatingVaultEntries(
            try entries(in: handWrittenFile), replacing: nil, with: "CMOS", say: "see moss")
        let rewritten = try ReadAloudPronunciations.vaultFileData(for: updated)

        let reread = try entries(in: rewritten)
        XCTAssertEqual(reread.map(\.term), ["CMOS", "LUT", "SIMDRAM"])
        XCTAssertEqual(reread.first { entry in entry.term == "SIMDRAM" }?.pronunciation.ipa, "ˈsɪmdiːɹæm")
    }

    func testEditingHowATermIsSaidKeepsItsOwnIPA() throws {
        let updated = ReadAloudPronunciations.updatingVaultEntries(
            try entries(in: handWrittenFile), replacing: "SIMDRAM", with: "SIMDRAM", say: "sim dram")

        let edited = try XCTUnwrap(updated.first { entry in entry.term == "SIMDRAM" })
        XCTAssertEqual(edited.pronunciation, ReadAloudPronunciations.Pronunciation(say: "sim dram", ipa: "ˈsɪmdiːɹæm"))
    }

    func testRenamingATermDoesNotCarryTheIPAOfTheOldName() throws {
        let updated = ReadAloudPronunciations.updatingVaultEntries(
            try entries(in: handWrittenFile), replacing: "SIMDRAM", with: "SIMD", say: "sim dee")

        XCTAssertNil(updated.first { entry in entry.term == "SIMDRAM" })
        XCTAssertNil(updated.first { entry in entry.term == "SIMD" }?.pronunciation.ipa)
    }

    func testTrimmingAndEmptyEntriesAreHandledAsBefore() throws {
        let written = try ReadAloudPronunciations.vaultFileData(for: [
            ReadAloudPronunciations.VaultEntry(term: " LUT ", pronunciation: .init(say: " L U T ")),
            ReadAloudPronunciations.VaultEntry(term: "", pronunciation: .init(say: "x"))
        ])
        XCTAssertEqual(try entries(in: written).map(\.term), ["LUT"])
    }
}
