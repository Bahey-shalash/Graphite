import XCTest
import WebKit
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// The web view `CommunityPluginHost` runs plugins in, built for real from a vault with one
/// enabled plugin: its own website data store per vault, and exactly one way for the page to
/// reach Graphite, the `graphitePlugins` script message handler.
///
/// Turning plugins on records the vault's consent in the standard defaults under a key made
/// from the vault's random identifier; `CommunityPluginHost.forgetVault` removes it again.
@MainActor
final class CommunityPluginHostWebViewConfigurationTests: XCTestCase {
    private var vault: URL!
    private var workspace: WorkspaceModel?
    private var openedVaultIdentifier: UUID?

    private static let pluginSource = """
    'use strict';
    const { Plugin } = require('obsidian');
    module.exports = class IdlePlugin extends Plugin { onload() {} };
    """

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("PluginWebViewVault-\(UUID().uuidString)").resolvingSymlinksInPath()
        let pluginFolder = vault.appendingPathComponent(".obsidian/plugins/idle-plugin")
        try FileManager.default.createDirectory(at: pluginFolder, withIntermediateDirectories: true)
        let manifest = #"{"id": "idle-plugin", "name": "Idle", "version": "1.0.0", "minAppVersion": "1.0.0", "author": "Graphite"}"#
        try Data(manifest.utf8).write(to: pluginFolder.appendingPathComponent("manifest.json"))
        try Data(Self.pluginSource.utf8).write(to: pluginFolder.appendingPathComponent("main.js"))
        try Data(#"["idle-plugin"]"#.utf8).write(to: vault.appendingPathComponent(".obsidian/community-plugins.json"))
    }

    override func tearDown() async throws {
        if let workspace {
            await workspace.communityPlugins.vaultWillClose()
            if let openedVaultIdentifier {
                workspace.vaultLibrary.remove(openedVaultIdentifier)
                CommunityPluginHost.forgetVault(openedVaultIdentifier)
            }
        }
        workspace = nil
        try? FileManager.default.removeItem(at: vault)
    }

    private func runningHost() async throws -> (host: CommunityPluginHost, webView: WKWebView, vaultIdentifier: UUID) {
        let workspace = WorkspaceModel()
        self.workspace = workspace
        try await workspace.openFolderAsVault(vault)
        let vaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        openedVaultIdentifier = vaultIdentifier
        let host = workspace.communityPlugins
        await host.reloadInventory() // opening lists nothing while plugins are off
        try await waitUntil("the plugin is listed") { host.inventory.plugins.count == 1 }
        await host.setTurnedOnForVault(true)
        try await waitUntil("the plugin loads", timeoutSeconds: 30) { host.loadStates["idle-plugin"] == .loaded }
        return (host, try XCTUnwrap(host.webView), vaultIdentifier)
    }

    func testThePluginPageHasItsOwnPersistentWebsiteDataStoreNamedByTheVault() async throws {
        let running = try await runningHost()
        let dataStore = running.webView.configuration.websiteDataStore
        XCTAssertEqual(dataStore.identifier, running.vaultIdentifier)
        XCTAssertTrue(dataStore.isPersistent)
        XCTAssertNotEqual(dataStore.identifier, WKWebsiteDataStore.default().identifier, "The vault does not share the app's default store.")
    }

    /// WebKit gives a page no list of its handlers (`Object.keys` of `messageHandlers` is empty),
    /// so the one handler is found by name, and the names Graphite uses elsewhere are checked absent.
    func testThePluginPageSeesTheGraphitePluginsScriptMessageHandlerAndNoOtherGraphiteHandler() async throws {
        let running = try await runningHost()
        let script = """
        const handlers = window.webkit.messageHandlers;
        const names = ['graphitePlugins', blockHandlerName, 'graphite', 'graphiteApp', 'plugins', 'native'];
        return names.map((name) => [name, typeof handlers[name] === 'object' && typeof handlers[name].postMessage === 'function']);
        """
        let answer = try await running.webView.callAsyncJavaScript(script, arguments: ["blockHandlerName": CommunityPluginCodeBlockPage.messageHandlerName], in: nil, contentWorld: .page)
        let presence = try XCTUnwrap(answer as? [[Any]]).reduce(into: [String: Bool]()) { result, pair in
            if let name = pair.first as? String, let isPresent = pair.last as? Bool { result[name] = isPresent }
        }
        XCTAssertEqual(presence, ["graphitePlugins": true, CommunityPluginCodeBlockPage.messageHandlerName: false, "graphite": false, "graphiteApp": false, "plugins": false, "native": false])
    }

    func testThePluginPageIsTheRuntimePageLoadedThroughTheGraphitePluginsScheme() async throws {
        let running = try await runningHost()
        let address = try await running.webView.callAsyncJavaScript("return window.location.href;", arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(address as? String, CommunityPluginSchemeHandler.runtimePageAddress?.absoluteString)
        XCTAssertNotNil(running.webView.configuration.urlSchemeHandler(forURLScheme: CommunityPluginSchemeHandler.scheme))
    }
}
