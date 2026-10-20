import XCTest
@testable import GraphiteCore

/// The bytes of the vault's pronunciation file (`.graphite/pronunciations.json`) as Settings
/// writes them: sorted, indented, hand-written `ipa` kept, and only the edited term changed.
final class ReadAloudPronunciationVaultFileBytesTests: XCTestCase {
    private let handWrittenFile = Data("""
        {
          "LUT" : "L U T",
          "SIMDRAM" : {
            "ipa" : "ˈsɪmdiːɹæm",
            "say" : "sim dee ram"
          }
        }
        """.utf8)

    private func entries(in data: Data) throws -> [ReadAloudPronunciations.VaultEntry] {
        guard case .loaded(let loaded, _) = ReadAloudPronunciations.readVaultFile(data: data) else {
            XCTFail("The file did not load.")
            return []
        }
        return loaded
    }

    func testTheVaultFileIsKeptAtItsFixedPath() {
        XCTAssertEqual(ReadAloudPronunciations.vaultFilePath, ".graphite/pronunciations.json")
    }

    func testRewritingAFileWithoutAnyEditGivesBackTheSameBytes() throws {
        let rewritten = try ReadAloudPronunciations.vaultFileData(for: try entries(in: handWrittenFile))

        XCTAssertEqual(String(decoding: rewritten, as: UTF8.self), String(decoding: handWrittenFile, as: UTF8.self))
    }

    func testEditingOneTermChangesOnlyThatTermsBytesAndKeepsTheOthersIPA() throws {
        let updated = ReadAloudPronunciations.updatingVaultEntries(
            try entries(in: handWrittenFile), replacing: "LUT", with: "LUT", say: "look up table")

        let rewritten = try ReadAloudPronunciations.vaultFileData(for: updated)

        XCTAssertEqual(String(decoding: rewritten, as: UTF8.self), """
            {
              "LUT" : "look up table",
              "SIMDRAM" : {
                "ipa" : "ˈsɪmdiːɹæm",
                "say" : "sim dee ram"
              }
            }
            """)
    }

    func testAddingATermWritesItInTheSortedPlaceAsAPlainRespelling() throws {
        let updated = ReadAloudPronunciations.updatingVaultEntries(
            try entries(in: handWrittenFile), replacing: nil, with: "CMOS", say: "see moss")

        let rewritten = try ReadAloudPronunciations.vaultFileData(for: updated)

        XCTAssertEqual(String(decoding: rewritten, as: UTF8.self), """
            {
              "CMOS" : "see moss",
              "LUT" : "L U T",
              "SIMDRAM" : {
                "ipa" : "ˈsɪmdiːɹæm",
                "say" : "sim dee ram"
              }
            }
            """)
    }
}
