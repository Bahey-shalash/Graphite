import XCTest
import GraphiteCore
@testable import GraphiteIndex

final class UiBasesRecordReuseTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!
    private let everyFile = BaseRecordPrefilter()

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("UiBasesReuseVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private func write(_ text: String, to relativePath: String) throws {
        try Data(text.utf8).write(to: vault.appendingPathComponent(relativePath))
    }

    func testReusedRecordsMatchAFullLoadAndOnlyChangedFilesAreReadAgain() async throws {
        try write("---\nstatus: open\n---\nSee [[B]]", to: "A.md")
        try write("---\nstatus: done\n---\n#tag", to: "B.md")
        try write("---\nstatus: open\n---\n", to: "C.md")
        _ = try await index.reconcile(root: vault)

        let first = try await index.baseRecords(matching: everyFile, reusing: LoadedBaseRecords())
        XCTAssertEqual(first.loadedRecords.rereadRecordCount, 3)
        let firstFullLoad = try await index.baseRecords(matching: everyFile)
        XCTAssertEqual(first.batch.records, firstFullLoad.records)

        let unchanged = try await index.baseRecords(matching: everyFile, reusing: first.loadedRecords)
        XCTAssertEqual(unchanged.loadedRecords.rereadRecordCount, 0)
        XCTAssertEqual(unchanged.batch.records, firstFullLoad.records)

        try write("---\nstatus: done\nrating: 5\n---\nNow longer text", to: "A.md")
        try FileManager.default.removeItem(at: vault.appendingPathComponent("C.md"))
        try write("---\nstatus: new\n---\n", to: "D.md")
        try await index.refresh(paths: [VaultPath("A.md"), VaultPath("C.md"), VaultPath("D.md")], root: vault)

        let afterChanges = try await index.baseRecords(matching: everyFile, reusing: unchanged.loadedRecords)
        XCTAssertEqual(afterChanges.loadedRecords.rereadRecordCount, 2, "Only the edited and the new file are read again.")
        let fullLoadAfterChanges = try await index.baseRecords(matching: everyFile)
        XCTAssertEqual(afterChanges.batch.records, fullLoadAfterChanges.records)
        XCTAssertEqual(afterChanges.batch.records.map(\.path.rawValue), ["A.md", "B.md", "D.md"])
        XCTAssertEqual(afterChanges.batch.records.first?.propertyEntry(named: "rating")?.node, .scalar(text: "5", isPlain: true))
    }

    func testReuseKeepsTheLimitAndTheCandidateCount() async throws {
        for noteNumber in 0..<5 { try write("---\nstatus: open\n---\n", to: "Note \(noteNumber).md") }
        _ = try await index.reconcile(root: vault)
        let fullLoad = try await index.baseRecords(matching: everyFile, limit: 3)
        let first = try await index.baseRecords(matching: everyFile, limit: 3, reusing: LoadedBaseRecords())
        let second = try await index.baseRecords(matching: everyFile, limit: 3, reusing: first.loadedRecords)
        for batch in [first.batch, second.batch] {
            XCTAssertEqual(batch.records, fullLoad.records)
            XCTAssertEqual(batch.candidateCount, 5)
        }
        XCTAssertEqual(second.loadedRecords.rereadRecordCount, 0)
    }
}
