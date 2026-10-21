import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// `CommunityPluginHost` running plugins in WebKit, against a vault folder on disk:
/// how views and loading survive the runtime stopping, starting and reloading.
@MainActor
final class CommunityPluginHostRuntimeTests: XCTestCase {
    private var openedVaultIdentifiers: [UUID] = []
    private var workspace: WorkspaceModel?

    private static let viewPluginIdentifier = "view-plugin"
    private static let viewType = "view-plugin-counter"

    /// A plugin with a view and a command that opens it in a tab.
    private static let viewPluginSource = """
    'use strict';
    const { Plugin, ItemView } = require('obsidian');
    class CounterView extends ItemView {
        getViewType() { return '\(viewType)'; }
        getDisplayText() { return 'Counter view'; }
        getIcon() { return 'clock'; }
        async onOpen() { this.contentEl.createEl('p', { text: 'Counter' }); }
    }
    module.exports = class ViewPlugin extends Plugin {
        async onload() {
            this.registerView('\(viewType)', (leaf) => new CounterView(leaf));
            this.addCommand({ id: 'open-view', name: 'Open view', callback: async () => {
                await this.app.workspace.getLeaf('tab').setViewState({ type: '\(viewType)', active: true });
            } });
            this.addCommand({ id: 'open-view-in-current-tab', name: 'Open view in current tab', callback: async () => {
                await this.app.workspace.getLeaf(false).setViewState({ type: '\(viewType)', active: true });
            } });
            this.addCommand({ id: 'open-side-view', name: 'Open side view', callback: async () => {
                await this.app.workspace.getRightLeaf(false).setViewState({ type: '\(viewType)', active: true });
            } });
        }
    };
    """

    private static let hangingPluginIdentifier = "a-hanging-plugin"

    /// A plugin whose `onload` never settles; its identifier sorts before the view plugin's.
    /// The promise stays referenced, as a pending request's would: WebKit fails an async call
    /// whose promise nothing refers to any more.
    private static let hangingPluginSource = """
    'use strict';
    const { Plugin } = require('obsidian');
    module.exports = class HangingPlugin extends Plugin {
        onload() { return new Promise((resolve) => { window.pendingOnload = resolve; }); }
    };
    """

    override func tearDown() async throws {
        if let workspace {
            await workspace.communityPlugins.vaultWillClose()
            for vaultIdentifier in openedVaultIdentifiers {
                workspace.vaultLibrary.remove(vaultIdentifier)
                CommunityPluginHost.forgetVault(vaultIdentifier)
            }
        }
        workspace = nil
        openedVaultIdentifiers = []
    }

    func testAPluginViewOpenInATabIsRestoredAfterPluginsReload() async throws {
        let workspace = try await workspaceWithRunningPlugins([(Self.viewPluginIdentifier, Self.viewPluginSource)])
        let host = workspace.communityPlugins
        try await runCommand("open-view", of: Self.viewPluginIdentifier, in: workspace)
        try await waitUntil("the plugin view shows in a tab") { workspace.tabDocuments.values.contains { document in document.pluginViewIdentifier != nil } }
        try await waitUntil("Graphite keeps what opens the view again") { workspace.tabDocuments.values.contains { document in document.restorablePluginView?.viewType == Self.viewType } }

        await host.restartPlugins()

        try await waitUntil("the plugin view shows in a tab again", timeoutSeconds: 5) {
            workspace.tabDocuments.values.contains { document in document.pluginViewIdentifier != nil }
        }
    }

    func testASidebarPluginViewIsRestoredAfterPluginsReload() async throws {
        let workspace = try await workspaceWithRunningPlugins([(Self.viewPluginIdentifier, Self.viewPluginSource)])
        let host = workspace.communityPlugins
        try await runCommand("open-side-view", of: Self.viewPluginIdentifier, in: workspace)
        try await waitUntil("the sidebar view is listed") { host.sidebarViews.contains { view in view.viewType == Self.viewType } }
        try await waitUntil("Graphite keeps what opens the sidebar view again") { workspace.restorableSidebarPluginViews.views.contains { view in view.viewType == Self.viewType } }

        await host.restartPlugins()

        try await waitUntil("the sidebar view is listed again", timeoutSeconds: 5) { host.sidebarViews.contains { view in view.viewType == Self.viewType } }
    }

    func testTurningPluginsOffKeepsTheOpenViewsInTheSavedLayout() async throws {
        let workspace = try await workspaceWithRunningPlugins([(Self.viewPluginIdentifier, Self.viewPluginSource)])
        let host = workspace.communityPlugins
        try await runCommand("open-view", of: Self.viewPluginIdentifier, in: workspace)
        try await runCommand("open-side-view", of: Self.viewPluginIdentifier, in: workspace)
        try await waitUntil("both views are kept for restoring") {
            workspace.tabDocuments.values.contains { document in document.restorablePluginView?.viewType == Self.viewType }
                && workspace.restorableSidebarPluginViews.views.contains { view in view.viewType == Self.viewType }
        }

        await host.setTurnedOnForVault(false)

        let saved = workspace.savedLayoutWithPluginViews()
        XCTAssertTrue(saved.groups.flatMap(\.tabs).contains { tab in tab.pluginView?.viewType == Self.viewType }, "The tab's plugin view stays in the saved layout.")
        XCTAssertEqual(saved.sidebarPluginViews?.map(\.viewType), [Self.viewType], "The sidebar's plugin view stays in the saved layout.")
    }

    func testAViewOpenedInTheCurrentTabTakesTheNoteTabsPlaceAfterTheNoteIsSaved() async throws {
        let workspace = try await workspaceWithRunningPlugins([(Self.viewPluginIdentifier, Self.viewPluginSource)])
        let notePath = try VaultPath("Note.md")
        let openedTabID = await workspace.open(notePath)
        let noteTabID = try XCTUnwrap(openedTabID)
        let session = try XCTUnwrap(workspace.openMarkdownSession(at: notePath))
        session.text = "Note.\nTyped.\n"
        let tabCount = workspace.layout.allTabs.count

        try await runCommand("open-view-in-current-tab", of: Self.viewPluginIdentifier, in: workspace)

        try await waitUntil("the plugin view shows in the active tab") {
            workspace.layout.activeTab.path == nil && workspace.tabDocuments[workspace.layout.activeTab.id]?.pluginViewIdentifier != nil
        }
        XCTAssertEqual(workspace.layout.allTabs.count, tabCount, "The view takes the note's tab; no tab is added.")
        XCTAssertNil(workspace.layout.tab(withID: noteTabID), "The note's tab is replaced.")
        let savedText = try String(contentsOf: try XCTUnwrap(workspace.folderAccess).root.appendingPathComponent("Note.md"), encoding: .utf8)
        XCTAssertEqual(savedText, "Note.\nTyped.\n", "The note's unsaved work is saved before its tab goes.")
    }

    func testAPluginWhoseOnloadNeverSettlesDoesNotStopTheLaterPluginsFromLoading() async throws {
        let workspace = try await workspaceWithPlugins([(Self.hangingPluginIdentifier, Self.hangingPluginSource), (Self.viewPluginIdentifier, Self.viewPluginSource)])
        let host = workspace.communityPlugins
        host.pluginLoadTimeout = .seconds(1)

        let turningOn = Task { @MainActor in await host.setTurnedOnForVault(true) }
        try await waitUntil("the plugin after the hanging one loads", timeoutSeconds: 20) { host.loadStates[Self.viewPluginIdentifier] == .loaded }
        try await waitUntil("saved plugin views are restored", timeoutSeconds: 5) { host.hasRestoredViews }

        guard case .failed = host.loadStates[Self.hangingPluginIdentifier] else {
            return XCTFail("The plugin that never finished loading is reported as failed, not \(String(describing: host.loadStates[Self.hangingPluginIdentifier])).")
        }
        await turningOn.value
    }

    func testTurningPluginsOnAgainWhileTheyStopStartsThemAgain() async throws {
        let workspace = try await workspaceWithRunningPlugins([(Self.viewPluginIdentifier, Self.viewPluginSource)])
        let host = workspace.communityPlugins

        let turningOff = Task { @MainActor in await host.setTurnedOnForVault(false) }
        await Task.yield()
        try XCTSkipUnless(host.runtimePhase.isStopping, "The plugins stopped before the test could turn them on again.")
        await host.setTurnedOnForVault(true)
        await turningOff.value

        try await waitUntil("the plugin loads again", timeoutSeconds: 20) { host.loadStates[Self.viewPluginIdentifier] == .loaded }
        XCTAssertEqual(host.runtimePhase, .running)
    }

    // MARK: Helpers

    private func workspaceWithRunningPlugins(_ plugins: [(identifier: String, source: String)]) async throws -> WorkspaceModel {
        let workspace = try await workspaceWithPlugins(plugins)
        let host = workspace.communityPlugins
        await host.setTurnedOnForVault(true)
        for plugin in plugins {
            try await waitUntil("\(plugin.identifier) loads", timeoutSeconds: 30) { host.loadStates[plugin.identifier] == .loaded }
        }
        return workspace
    }

    /// A vault with `plugins` installed and enabled, opened, with community plugins still off.
    private func workspaceWithPlugins(_ plugins: [(identifier: String, source: String)]) async throws -> WorkspaceModel {
        let vault = try TemporaryVault.make(prefix: "PluginRuntimeVault", for: self).root
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        try Data("Note.\n".utf8).write(to: vault.appendingPathComponent("Note.md"))
        for plugin in plugins {
            let folder = vault.appendingPathComponent(".obsidian/plugins/\(plugin.identifier)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let manifest = "{\"id\": \"\(plugin.identifier)\", \"name\": \"\(plugin.identifier)\", \"version\": \"1.0.0\", \"minAppVersion\": \"1.0.0\", \"author\": \"Graphite\"}"
            try Data(manifest.utf8).write(to: folder.appendingPathComponent("manifest.json"))
            try Data(plugin.source.utf8).write(to: folder.appendingPathComponent("main.js"))
        }
        let enabledList = "[" + plugins.map { plugin in "\"\(plugin.identifier)\"" }.joined(separator: ", ") + "]"
        try Data(enabledList.utf8).write(to: vault.appendingPathComponent(".obsidian/community-plugins.json"))
        let workspace = WorkspaceModel()
        self.workspace = workspace
        try await workspace.openFolderAsVault(vault)
        openedVaultIdentifiers.append(try XCTUnwrap(workspace.currentVaultIdentifier))
        let host = workspace.communityPlugins
        await host.reloadInventory() // opening lists nothing while plugins are off, as Settings lists them
        try await waitUntil("the plugins are listed") { host.inventory.plugins.count == plugins.count }
        return workspace
    }

    private func runCommand(_ commandIdentifier: String, of pluginIdentifier: String, in workspace: WorkspaceModel) async throws {
        let host = workspace.communityPlugins
        try await waitUntil("the command is registered") { host.commands.contains { command in command.id == pluginIdentifier + ":" + commandIdentifier } }
        let command = try XCTUnwrap(host.commands.first { command in command.id == pluginIdentifier + ":" + commandIdentifier })
        await host.run(command)
    }
}
