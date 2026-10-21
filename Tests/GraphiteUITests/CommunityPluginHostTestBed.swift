import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// A vault on disk with community plugins installed, opened in a `WorkspaceModel` whose
/// `CommunityPluginHost` runs them in a real web view: the setting the host's tests share.
@MainActor
final class CommunityPluginHostTestBed {
    typealias PluginSource = (identifier: String, source: String)

    private var temporaryVaults: [TemporaryVault] = []
    private var openedVaultIdentifiers: [UUID] = []
    private var workspace: WorkspaceModel?
    /// The preferences and folders of the workspaces this bed makes, made when first asked for.
    private var device: IsolatedWorkspaceDevice?

    private func isolatedDevice() throws -> IsolatedWorkspaceDevice {
        if let device { return device }
        let newDevice = try IsolatedWorkspaceDevice()
        device = newDevice
        return newDevice
    }

    /// The workspace opened last.
    func currentWorkspace() throws -> WorkspaceModel {
        try XCTUnwrap(workspace, "No vault was opened.")
    }

    /// Closes the plugins and forgets everything the test left on the device for its vaults.
    func tearDown() async {
        if let workspace {
            await workspace.communityPlugins.vaultWillClose()
            for vaultIdentifier in openedVaultIdentifiers {
                workspace.vaultLibrary.remove(vaultIdentifier)
                CommunityPluginHost.forgetVault(vaultIdentifier, defaults: workspace.deviceDefaults)
            }
        }
        workspace = nil
        device?.remove()
        device = nil
        for temporaryVault in temporaryVaults { temporaryVault.remove() }
        temporaryVaults = []
        openedVaultIdentifiers = []
    }

    /// A vault folder holding `Note.md`, with each of `plugins` installed and enabled.
    func makeVault(plugins: [PluginSource], files: [String: String] = ["Note.md": "Note.\n"]) throws -> URL {
        let temporaryVault = try TemporaryVault(prefix: "PluginHostVault")
        temporaryVaults.append(temporaryVault)
        let vault = temporaryVault.root
        try temporaryVault.createFolder(".obsidian")
        try temporaryVault.writeFiles(files)
        for plugin in plugins {
            let folder = vault.appendingPathComponent(".obsidian/plugins/\(plugin.identifier)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let manifest = "{\"id\": \"\(plugin.identifier)\", \"name\": \"\(plugin.identifier)\", \"version\": \"1.0.0\", \"minAppVersion\": \"1.0.0\", \"author\": \"Graphite\"}"
            try Data(manifest.utf8).write(to: folder.appendingPathComponent("manifest.json"))
            try Data(plugin.source.utf8).write(to: folder.appendingPathComponent("main.js"))
        }
        let enabledList = "[" + plugins.map { plugin in "\"\(plugin.identifier)\"" }.joined(separator: ", ") + "]"
        try Data(enabledList.utf8).write(to: vault.appendingPathComponent(".obsidian/community-plugins.json"))
        return vault
    }

    /// Opens `vault` in a workspace; community plugins stay off until the test turns them on.
    /// While they are off, opening the vault lists nothing, so the plugins are listed here as
    /// Settings › Community Plugins lists them.
    func openWorkspace(at vault: URL, expectedPluginCount: Int, in existingWorkspace: WorkspaceModel? = nil) async throws -> WorkspaceModel {
        let workspace = try existingWorkspace ?? isolatedDevice().makeWorkspace()
        self.workspace = workspace
        try await workspace.openFolderAsVault(vault)
        openedVaultIdentifiers.append(try XCTUnwrap(workspace.currentVaultIdentifier))
        let host = workspace.communityPlugins
        await host.reloadInventory()
        try await waitUntil("the plugins are listed") { host.inventory.plugins.count == expectedPluginCount }
        return workspace
    }

    /// Opens `vault` and returns at once, without listing its plugins.
    func openWorkspaceWithoutListingPlugins(at vault: URL) async throws -> WorkspaceModel {
        let workspace = try isolatedDevice().makeWorkspace()
        self.workspace = workspace
        try await workspace.openFolderAsVault(vault)
        openedVaultIdentifiers.append(try XCTUnwrap(workspace.currentVaultIdentifier))
        return workspace
    }

    /// A vault with `plugins` installed and enabled, opened, with community plugins still off.
    func workspaceWithPlugins(_ plugins: [PluginSource], files: [String: String] = ["Note.md": "Note.\n"]) async throws -> WorkspaceModel {
        try await openWorkspace(at: makeVault(plugins: plugins, files: files), expectedPluginCount: plugins.count)
    }

    /// The same, with the plugins turned on and loaded.
    func workspaceWithRunningPlugins(_ plugins: [PluginSource], files: [String: String] = ["Note.md": "Note.\n"]) async throws -> WorkspaceModel {
        let workspace = try await workspaceWithPlugins(plugins, files: files)
        let host = workspace.communityPlugins
        await host.setTurnedOnForVault(true)
        for plugin in plugins {
            try await waitUntil("\(plugin.identifier) loads", timeoutSeconds: 30) { host.loadStates[plugin.identifier] == .loaded }
        }
        return workspace
    }

    func runCommand(_ commandIdentifier: String, of pluginIdentifier: String, in workspace: WorkspaceModel) async throws {
        let host = workspace.communityPlugins
        try await waitUntil("the command is registered") { host.commands.contains { command in command.id == pluginIdentifier + ":" + commandIdentifier } }
        let command = try XCTUnwrap(host.commands.first { command in command.id == pluginIdentifier + ":" + commandIdentifier })
        await host.run(command)
    }

    /// The value of `script` run in the plugins' page, as a plugin's code would see it.
    func evaluate(_ script: String, in host: CommunityPluginHost) async throws -> Any? {
        let webView = try XCTUnwrap(host.webView, "The plugins are not running.")
        return try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
    }

}
