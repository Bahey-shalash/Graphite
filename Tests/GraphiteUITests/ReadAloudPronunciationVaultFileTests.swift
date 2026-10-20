import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Settings › Read Aloud › Pronunciations changes the vault's `.graphite/pronunciations.json`
/// one edit at a time, applied to what the file holds when the edit is saved. A term that
/// reached the file after the page opened, for example from another device through iCloud,
/// is kept, and a file that can no longer be rewritten whole is left untouched.
@MainActor
final class ReadAloudPronunciationVaultFileTests: XCTestCase {
    private let filePath = ReadAloudPronunciations.vaultFilePath

    private func openedPage(fileText: String) throws -> (file: ReadAloudPronunciationVaultFile, vault: TemporaryVault) {
        let vault = try TemporaryVault.make(prefix: "PronunciationVaultFile", files: [filePath: fileText], for: self)
        let file = ReadAloudPronunciationVaultFile(vaultRoot: vault.root)
        file.reload()
        return (file, vault)
    }

    private func termsOnDisk(in vault: TemporaryVault) throws -> [String] {
        let data = try Data(contentsOf: vault.root.appendingPathComponent(filePath))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return object.keys.sorted()
    }

    func testSavingATermKeepsATermThatReachedTheFileAfterThePageOpened() throws {
        let (file, vault) = try openedPage(fileText: #"{"LUT": "L U T"}"#)
        try vault.writeFiles([filePath: #"{"LUT": "L U T", "CMOS": "see moss"}"#])

        try file.save(.saving(term: "SIMDRAM", say: "sim dee ram", replacing: nil))

        XCTAssertEqual(try termsOnDisk(in: vault), ["CMOS", "LUT", "SIMDRAM"])
        XCTAssertEqual(file.entries.map(\.term), ["CMOS", "LUT", "SIMDRAM"], "The page shows what the file holds now.")
    }

    func testRemovingATermKeepsATermThatReachedTheFileAfterThePageOpened() throws {
        let (file, vault) = try openedPage(fileText: #"{"LUT": "L U T", "FF": "flip-flop"}"#)
        try vault.writeFiles([filePath: #"{"LUT": "L U T", "FF": "flip-flop", "CMOS": "see moss"}"#])

        try file.save(.removing(terms: ["FF"]))

        XCTAssertEqual(try termsOnDisk(in: vault), ["CMOS", "LUT"])
    }

    func testAFileThatCannotBeRewrittenWholeAnyMoreIsLeftUntouched() throws {
        let (file, vault) = try openedPage(fileText: #"{"LUT": "L U T"}"#)
        let damagedText = #"{"LUT": "L U T", "CMOS": "#
        try vault.writeFiles([filePath: damagedText])

        XCTAssertThrowsError(try file.save(.saving(term: "SIMDRAM", say: "sim dee ram", replacing: nil)))

        XCTAssertEqual(try String(contentsOf: vault.root.appendingPathComponent(filePath), encoding: .utf8), damagedText)
        XCTAssertEqual(file.reading, .invalid(.notJSON), "The page says why the file is read-only.")
    }
}
