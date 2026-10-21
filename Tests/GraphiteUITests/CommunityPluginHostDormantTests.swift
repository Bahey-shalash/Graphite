import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// While community plugins are off for a vault, opening it costs nothing: no plugin's main.js
/// is read or scanned, and no runtime starts. Turning plugins on lists and loads them.
@MainActor
final class CommunityPluginHostDormantTests: XCTestCase {
    private let testBed = CommunityPluginHostTestBed()
    private static let pluginSource = """
        'use strict';
        const { Plugin } = require('obsidian');
        module.exports = class QuietPlugin extends Plugin { async onload() {} };
        """

    override func tearDown() async throws {
        await testBed.tearDown()
    }

    func testOpeningAVaultWithPluginsOffReadsNoPluginAndStartsNothing() async throws {
        let vault = try testBed.makeVault(plugins: [("quiet", Self.pluginSource)])
        let workspace = try await testBed.openWorkspaceWithoutListingPlugins(at: vault)
        // Opening returns with nothing scheduled for the plugins while they are off, so what the
        // host holds now is what it holds for as long as they stay off.
        let host = workspace.communityPlugins

        XCTAssertFalse(host.isTurnedOnForVault)
        XCTAssertTrue(host.inventory.plugins.isEmpty, "The plugin folder is not read while plugins are off.")
        XCTAssertTrue(host.loadStates.isEmpty)
        XCTAssertNil(host.webView, "No web view exists while plugins are off.")

        await host.setTurnedOnForVault(true)

        XCTAssertEqual(host.inventory.plugins.map(\.id), ["quiet"], "Turning plugins on lists them.")
        try await waitUntil("the plugin loads", timeoutSeconds: 30) { host.loadStates["quiet"] == .loaded }
    }
}
