import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// Vault folders on disk opened in a `WorkspaceModel`, for the tests of the workspace's
/// tabs. The workspaces it makes remember what they remember per vault in preferences and
/// folders of the bed's own (`IsolatedWorkspaceDevice`), which `tearDown()` removes.
@MainActor
final class WorkspaceModelTestBed {
    private var temporaryVaults: [TemporaryVault] = []
    private var device: IsolatedWorkspaceDevice?

    /// The device state of the workspaces this bed makes, made when first asked for.
    func isolatedDevice() throws -> IsolatedWorkspaceDevice {
        if let device { return device }
        let newDevice = try IsolatedWorkspaceDevice()
        device = newDevice
        return newDevice
    }

    func tearDown() {
        device?.remove()
        device = nil
        for temporaryVault in temporaryVaults { temporaryVault.remove() }
        temporaryVaults = []
    }

    /// A vault folder holding `files` (text by path), read through its resolved path as the
    /// workspace reads it.
    func makeVault(files: [String: String]) throws -> URL {
        let temporaryVault = try TemporaryVault(prefix: "WorkspaceTabsVault")
        temporaryVaults.append(temporaryVault)
        try temporaryVault.writeFiles(files)
        return temporaryVault.root
    }

    func openedWorkspace(files: [String: String]) async throws -> (workspace: WorkspaceModel, vault: URL) {
        let vault = try makeVault(files: files)
        let workspace = try isolatedDevice().makeWorkspace()
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
