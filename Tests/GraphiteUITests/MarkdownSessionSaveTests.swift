import XCTest
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class MarkdownSessionSaveTests: XCTestCase {
    /// Autosave, navigation, ⌘S and leaving the app can each start a save while another
    /// is running. The later saves used to spin on the main actor forever, freezing the app.
    func testOverlappingSavesAllFinishAndWriteTheLatestText() async throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let notePath = try VaultPath("Note.md")
        try Data("start".utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })

        for editNumber in 1...20 {
            session.text = "edit \(editNumber)"
            let overlappingSaves = (0..<3).map { _ in Task { @MainActor in try await session.save() } }
            for save in overlappingSaves { try await save.value }
            XCTAssertFalse(session.isSaving)
            XCTAssertFalse(session.hasUnsavedChanges)
        }
        let savedText = String(data: try Data(contentsOf: vault.appendingPathComponent("Note.md")), encoding: .utf8)
        XCTAssertEqual(savedText, "edit 20")
    }
}
