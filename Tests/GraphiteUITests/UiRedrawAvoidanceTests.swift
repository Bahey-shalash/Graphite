import Foundation
import XCTest
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

/// Values the whole window observes stay the same while nothing changed, so a redraw of the
/// root view, as opening a note causes, does not redraw every view that reads them. With
/// 24,712 files at a vault's root these redraws cost the Mac over a second per note.
@MainActor
final class UiRedrawAvoidanceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories { try? FileManager.default.removeItem(at: directory) }
        temporaryDirectories = []
        try await super.tearDown()
    }

    /// SwiftUI compares colors by their platform color object; an accent made again on each
    /// read counted as a new environment value every time.
    func testTheAccentReadTwiceIsTheSameColor() throws {
        let suiteName = "UiRedrawAvoidanceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = GraphitePreferences(defaults: defaults)

        XCTAssertEqual(preferences.accentColor, preferences.accentColor)
    }

    /// Obsidian, running beside Graphite, changes `.obsidian` files every few seconds, and each
    /// change refreshes the vault's root. Its files were asked about again each time, up to
    /// 5,000 of a 24,712-file root through the file provider; now only new files are.
    func testRefreshingAnUnchangedFolderDoesNotAskAboutItsFilesAgain() async throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("RedrawVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        temporaryDirectories.append(vault)
        for name in ["Alpha.md", "Beta.md"] { try Data("# \(name)\n".utf8).write(to: vault.appendingPathComponent(name)) }
        let store = try TestConflictVersionStore()
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.conflictVersionStore = store

        await workspace.refreshDirectory()
        try await waitForConflictChecks(of: workspace)
        XCTAssertEqual(store.pathsAskedAbout.count, 2)

        await workspace.refreshDirectory()
        try await waitForConflictChecks(of: workspace)
        XCTAssertEqual(store.pathsAskedAbout.count, 2, "An unchanged listing asks about nothing again.")

        try Data("# Gamma\n".utf8).write(to: vault.appendingPathComponent("Gamma.md"))
        await workspace.refreshDirectory()
        try await waitForConflictChecks(of: workspace)
        XCTAssertEqual(store.pathsAskedAbout.count, 3, "Only the new file is asked about.")
        XCTAssertEqual(workspace.rootEntries.map(\.path.rawValue), ["Alpha.md", "Beta.md", "Gamma.md"])
    }

    private func waitForConflictChecks(of workspace: WorkspaceModel) async throws {
        let deadline = Date.now.addingTimeInterval(10)
        while workspace.conflictCheckTask != nil || !workspace.pendingConflictChecks.isEmpty {
            guard Date.now < deadline else { return XCTFail("Conflict checks did not finish") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
