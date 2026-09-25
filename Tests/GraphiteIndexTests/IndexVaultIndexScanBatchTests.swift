import XCTest
import GraphiteCore
@testable import GraphiteIndex

/// Scans check enumerated files in chunks, read changed notes in batches under one file
/// coordination, and parse them outside the actor. The index must come out the same.
final class IndexVaultIndexScanBatchTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
    }

    override func tearDown() async throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: vault.appendingPathComponent("Locked.md").path)
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private func write(_ text: String, to relativePath: String) throws {
        let location = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: location)
    }

    private func searchPaths(_ text: String) async throws -> [String] {
        try await index.search(text).results.map(\.path.rawValue)
    }

    /// More files than one unchanged-check chunk (256) and one batch (64), notes and
    /// attachments mixed: every file is counted once, and a rescan reads only what changed.
    func testScanAcrossChunksAndBatchesReadsOnlyChangedFiles() async throws {
        let noteCount = 400, attachmentCount = 200
        for noteNumber in 0..<noteCount { try write("# Note \(noteNumber)\n\nnoteword\(noteNumber)", to: String(format: "Folder %d/n%04d.md", noteNumber % 7, noteNumber)) }
        for attachmentNumber in 0..<attachmentCount { try write("image", to: String(format: "Attachments/a%04d.png", attachmentNumber)) }
        let firstReport = try await index.reconcile(root: vault)
        XCTAssertEqual(firstReport.discoveredFiles, noteCount + attachmentCount)
        XCTAssertEqual(firstReport.updatedFiles, noteCount + attachmentCount)
        XCTAssertEqual(firstReport.pendingContentFiles, 0)
        XCTAssertEqual(firstReport.failedPaths, [])
        for noteNumber in [0, 63, 64, 255, 256, 399] {
            let search = try await searchPaths("noteword\(noteNumber)")
            XCTAssertEqual(search, [String(format: "Folder %d/n%04d.md", noteNumber % 7, noteNumber)])
        }

        let unchangedReport = try await index.reconcile(root: vault)
        XCTAssertEqual(unchangedReport.discoveredFiles, noteCount + attachmentCount)
        XCTAssertEqual(unchangedReport.updatedFiles, 0)
        let fileCount = try await index.fileCount()
        XCTAssertEqual(fileCount, noteCount + attachmentCount, "Unchanged files are marked seen, not pruned.")

        let changedNumbers = [5, 257, 398]
        for noteNumber in changedNumbers { try write("# Note \(noteNumber)\n\nrewrittenword\(noteNumber) and more text", to: String(format: "Folder %d/n%04d.md", noteNumber % 7, noteNumber)) }
        let changedReport = try await index.reconcile(root: vault)
        XCTAssertEqual(changedReport.updatedFiles, changedNumbers.count)
        for noteNumber in changedNumbers {
            let search = try await searchPaths("rewrittenword\(noteNumber)")
            XCTAssertEqual(search, [String(format: "Folder %d/n%04d.md", noteNumber % 7, noteNumber)])
        }
    }

    /// A note that cannot be read costs only itself inside a batch read under one coordination.
    func testUnreadableNoteInAScanBatchCostsOnlyItself() async throws {
        for noteNumber in 0..<20 { try write("# Note \(noteNumber)\n\nbatchword\(noteNumber)end", to: String(format: "n%04d.md", noteNumber)) }
        try write("# Locked\n\nlockedword", to: "Locked.md")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: vault.appendingPathComponent("Locked.md").path)
        let report = try await index.reconcile(root: vault)
        XCTAssertEqual(report.updatedFiles, 21)
        XCTAssertEqual(report.pendingContentFiles, 1)
        XCTAssertEqual(report.failedPaths.count, 1)
        XCTAssertTrue(report.failedPaths.first?.hasPrefix("Locked.md: ") == true, "\(report.failedPaths)")
        for noteNumber in 0..<20 {
            let search = try await searchPaths("batchword\(noteNumber)end")
            XCTAssertEqual(search, [String(format: "n%04d.md", noteNumber)])
        }
        let lockedCount = try await index.fileCount(named: "Locked.md")
        XCTAssertEqual(lockedCount, 1, "The unreadable note stays in the inventory.")
        // Once readable, the next scan reads it, although its size and date did not change.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: vault.appendingPathComponent("Locked.md").path)
        let secondReport = try await index.reconcile(root: vault)
        XCTAssertEqual(secondReport.updatedFiles, 1)
        let lockedSearch = try await searchPaths("lockedword")
        XCTAssertEqual(lockedSearch, ["Locked.md"])
    }

    /// Link queries run outside the actor; a caller that is cancelled stops its query
    /// instead of running it to completion.
    func testCancelledCallerDoesNotRunItsQuery() async throws {
        let index = try XCTUnwrap(index)
        try await index.update([IndexedFile(path: VaultPath("Note.md"), size: 10, modified: .now, markdown: "# Note")], generation: "test")
        let query = Task { () async throws -> [VaultPath] in
            while !Task.isCancelled { await Task.yield() }
            return try await index.resolve("Note", from: .root)
        }
        query.cancel()
        do {
            let resolution = try await query.value
            XCTFail("A cancelled query returned \(resolution).")
        } catch is CancellationError {}
        let resolution = try await index.resolve("Note", from: .root)
        XCTAssertEqual(resolution.map(\.rawValue), ["Note.md"])
    }
}
