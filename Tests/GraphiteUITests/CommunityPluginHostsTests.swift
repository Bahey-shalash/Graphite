import XCTest
import GraphiteCore
@testable import GraphiteUI
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif

/// One plugin runtime per open vault, shared by the vault's windows and acting on the one in
/// front, so a plugin never runs twice on the same files (owner, 2026-10-21).
@MainActor
final class CommunityPluginHostsTests: XCTestCase {
    private var processServices: ProcessServices!

    override func setUp() async throws {
        processServices = try IsolatedWorkspaceDevice.make(for: self).makeServices()
    }

    private func window(on vault: URL) async throws -> WorkspaceModel {
        let window = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        try await window.openFolderAsVault(vault)
        return window
    }

    func testWindowsOnOneVaultShareOneHostThatActsOnTheWindowInFront() async throws {
        let vault = try TemporaryVault.make(prefix: "PluginVault", for: self).root.resolvingSymlinksInPath()
        let firstWindow = try await window(on: vault)
        let secondWindow = try await window(on: vault)

        XCTAssertIdentical(firstWindow.communityPlugins, secondWindow.communityPlugins)
        XCTAssertIdentical(secondWindow.communityPlugins.workspace, secondWindow, "The window that opened last is in front.")
        firstWindow.windowCameToFront()
        XCTAssertIdentical(firstWindow.communityPlugins.workspace, firstWindow)

        firstWindow.windowDidClose()
        try await waitUntil { secondWindow.communityPlugins.workspace === secondWindow }
        XCTAssertNotNil(secondWindow.communityPlugins.vaultIdentifier, "The vault's plugins stay with the window left on it.")

        secondWindow.windowDidClose()
        try await waitUntil { secondWindow.communityPlugins.vaultIdentifier == nil }
    }

    func testTwoVaultsInTwoWindowsHaveAHostEach() async throws {
        let firstWindow = try await window(on: try TemporaryVault.make(prefix: "FirstPluginVault", for: self).root.resolvingSymlinksInPath())
        let secondWindow = try await window(on: try TemporaryVault.make(prefix: "SecondPluginVault", for: self).root.resolvingSymlinksInPath())

        XCTAssertNotIdentical(firstWindow.communityPlugins, secondWindow.communityPlugins)
        XCTAssertIdentical(firstWindow.communityPlugins.workspace, firstWindow)
        XCTAssertIdentical(secondWindow.communityPlugins.workspace, secondWindow)
    }
}
