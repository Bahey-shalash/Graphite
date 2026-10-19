import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Vault folders on disk opened in a `WorkspaceModel`, for the tests of the workspace's
/// tabs. The workspace keeps what it remembers per vault in the standard preferences, which
/// it has no way to be given elsewhere, so what the tests leave there is removed at the end.
@MainActor
final class WorkspaceModelTestBed {
    private var temporaryDirectories: [URL] = []
    private var savedGraphitePreferences: [String: Any] = [:]
    private var vaultIdentifiersBeforeTest: Set<UUID> = []

    init() {
        savedGraphitePreferences = UserDefaults.standard.dictionaryRepresentation().filter { key, _ in key.hasPrefix("Graphite") }
        vaultIdentifiersBeforeTest = Set(VaultLibrary().vaults.map(\.id))
    }

    func tearDown() {
        for vault in VaultLibrary().vaults where !vaultIdentifiersBeforeTest.contains(vault.id) {
            VaultIndex.removeIndex(forVault: vault.id)
        }
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("Graphite") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        for (key, storedValue) in savedGraphitePreferences { UserDefaults.standard.set(storedValue, forKey: key) }
        for directory in temporaryDirectories {
            if let cacheURL = try? VaultIndex.cacheURL(for: directory) { try? FileManager.default.removeItem(at: cacheURL) }
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
    }

    /// A vault folder holding `files` (text by path), read through its resolved path as the
    /// workspace reads it.
    func makeVault(files: [String: String]) throws -> URL {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("WorkspaceTabsVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        temporaryDirectories.append(vault)
        for (path, contents) in files {
            let location = vault.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        return vault.resolvingSymlinksInPath()
    }

    func openedWorkspace(files: [String: String]) async throws -> (workspace: WorkspaceModel, vault: URL) {
        let vault = try makeVault(files: files)
        let workspace = WorkspaceModel()
        try await workspace.openFolderAsVault(vault)
        return (workspace, vault)
    }

    /// Opens a file and returns the tab showing it; the test fails when it did not open.
    @discardableResult
    func open(_ rawPath: String, in workspace: WorkspaceModel, placement: TabPlacement = .currentTab) async throws -> UUID {
        let tabID = await workspace.open(try VaultPath(rawPath), placement: placement)
        return try XCTUnwrap(tabID, "\(rawPath) did not open.")
    }

    func text(of path: String, in vault: URL) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(path), encoding: .utf8)
    }
}
