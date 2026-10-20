import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// The plugin views open in tabs and in the sidebar when a vault is left: Graphite keeps what
/// opens them again in the vault's saved layout and opens them once the plugins have loaded
/// when the vault is opened again.
@MainActor
final class CommunityPluginHostSavedViewsTests: XCTestCase {
    private let testBed = CommunityPluginHostTestBed()

    override func tearDown() async throws {
        await testBed.tearDown()
    }

    private static let viewType = "saved-counter"

    private static let viewPluginSource = """
    'use strict';
    const { Plugin, ItemView } = require('obsidian');
    class CounterView extends ItemView {
        getViewType() { return '\(viewType)'; }
        getDisplayText() { return 'Counter view'; }
        getIcon() { return 'clock'; }
        getState() { return { clicks: 3 }; }
        async onOpen() { this.contentEl.createEl('p', { text: 'Counter' }); }
    }
    module.exports = class SavedViewPlugin extends Plugin {
        async onload() {
            this.registerView('\(viewType)', (leaf) => new CounterView(leaf));
            this.addCommand({ id: 'open-view', name: 'Open view', callback: async () => {
                await this.app.workspace.getLeaf('tab').setViewState({ type: '\(viewType)', active: true });
            } });
            this.addCommand({ id: 'open-side-view', name: 'Open side view', callback: async () => {
                await this.app.workspace.getRightLeaf(false).setViewState({ type: '\(viewType)', active: true });
            } });
        }
    };
    """

    func testPluginViewsInATabAndInTheSidebarAreKeptInTheSavedLayoutWhenTheVaultIsLeftAndOpenAgainWhenItIsOpenedAgain() async throws {
        let plugins = [(identifier: "saved-view-plugin", source: Self.viewPluginSource)]
        let firstVault = try testBed.makeVault(plugins: plugins)
        let workspace = try await testBed.openWorkspace(at: firstVault, expectedPluginCount: 1)
        let host = workspace.communityPlugins
        await host.setTurnedOnForVault(true)
        try await waitUntil("the plugin loads", timeoutSeconds: 30) { host.loadStates["saved-view-plugin"] == .loaded }
        try await testBed.runCommand("open-view", of: "saved-view-plugin", in: workspace)
        try await testBed.runCommand("open-side-view", of: "saved-view-plugin", in: workspace)
        try await waitUntil("both views are kept for restoring") {
            workspace.tabDocuments.values.contains { document in document.restorablePluginView?.viewType == Self.viewType }
                && workspace.restorableSidebarPluginViews.views.contains { view in view.viewType == Self.viewType }
        }
        let firstVaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)

        let secondVault = try testBed.makeVault(plugins: [])
        _ = try await testBed.openWorkspace(at: secondVault, expectedPluginCount: 0, in: workspace)

        XCTAssertNotEqual(workspace.currentVaultIdentifier, firstVaultIdentifier)
        let storedLayout = try XCTUnwrap(workspace.deviceDefaults.data(forKey: WorkspaceModel.tabLayoutKey(for: firstVaultIdentifier)), "The left vault's layout stays saved.")
        let saved = try JSONDecoder().decode(SavedTabLayout.self, from: storedLayout)
        let savedTabView = saved.groups.flatMap(\.tabs).compactMap(\.pluginView).first
        XCTAssertEqual(savedTabView?.viewType, Self.viewType)
        XCTAssertEqual(savedTabView?.state, "{\"clicks\":3}", "The state the view gave is saved as JSON text.")
        XCTAssertEqual(saved.sidebarPluginViews?.map(\.viewType), [Self.viewType])

        try await workspace.openFolderAsVault(firstVault)

        XCTAssertEqual(workspace.currentVaultIdentifier, firstVaultIdentifier)
        try await waitUntil("the plugin view shows in a tab again", timeoutSeconds: 30) {
            workspace.tabDocuments.values.contains { document in document.pluginViewIdentifier != nil }
        }
        try await waitUntil("the sidebar view is listed again", timeoutSeconds: 30) {
            workspace.communityPlugins.sidebarViews.contains { view in view.viewType == Self.viewType }
        }
    }
}
