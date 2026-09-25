import XCTest
@testable import GraphiteIndex
import GraphiteCore

/// Vault path rules as the index sees them during a scan.
final class CoreFilesSettingsIndexTests: XCTestCase {
    func testBackslashFileNameNeitherFailsTheScanNorStopsPruning() async throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        let cache = vault.appendingPathExtension("cache")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: vault)
            try? FileManager.default.removeItem(at: cache)
        }
        for name in ["Windows\\path.txt", "Deleted.md", "Kept.md"] { try Data("text".utf8).write(to: vault.appendingPathComponent(name)) }
        let index = try VaultIndex(databaseURL: cache.appendingPathComponent("index.sqlite"))
        let firstReport = try await index.reconcile(root: vault)
        XCTAssertEqual(firstReport.failedPaths, [])
        let firstCount = try await index.fileCount()
        XCTAssertEqual(firstCount, 3)
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Deleted.md"))
        _ = try await index.reconcile(root: vault)
        let deletedCount = try await index.fileCount(named: "Deleted.md")
        let remainingCount = try await index.fileCount()
        XCTAssertEqual(deletedCount, 0)
        XCTAssertEqual(remainingCount, 2)
    }
}
