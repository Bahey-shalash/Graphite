import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// A file a community plugin shows in a view of its own opens in that view, once, in a tab.
@MainActor
final class WorkspaceModelPluginFileViewTests: XCTestCase {
    private let testBed = CommunityPluginHostTestBed()

    override func tearDown() async throws {
        await testBed.tearDown()
    }

    private static let sketchPluginSource = """
    'use strict';
    const { Plugin, TextFileView } = require('obsidian');
    class SketchView extends TextFileView {
        getViewType() { return 'sketch'; }
        getDisplayText() { return this.file ? this.file.basename : 'Sketch'; }
        setViewData(data) { this.data = data; this.contentEl.setText('Sketch: ' + data.trim()); }
        getViewData() { return this.data; }
        clear() {}
    }
    module.exports = class SketchPlugin extends Plugin {
        onload() {
            this.registerView('sketch', (leaf) => new SketchView(leaf));
            this.registerExtensions(['sketch'], 'sketch');
        }
    };
    """

    func testAFileWithAPluginsExtensionOpensInThePluginsViewAndOpeningItAgainActivatesThatTab() async throws {
        let workspace = try await testBed.workspaceWithRunningPlugins([("sketch-plugin", Self.sketchPluginSource)],
                                                                      files: ["Note.md": "Note.\n", "Drawing.sketch": "lines\n"])
        let host = workspace.communityPlugins
        try await waitUntil("the plugin's extension is known") { host.pluginFileExtensions["sketch"] != nil }
        let sketchPath = try VaultPath("Drawing.sketch")
        XCTAssertTrue(host.mayShowInPluginView(sketchPath))
        XCTAssertFalse(host.mayShowInPluginView(try VaultPath("Note.md")), "Notes stay Graphite's unless a plugin takes them over.")

        let firstTabID = await workspace.open(sketchPath)

        let tabID = try XCTUnwrap(firstTabID)
        let viewIdentifier = try XCTUnwrap(workspace.tabDocuments[tabID]?.pluginViewIdentifier, "The file opens in the plugin's view.")
        XCTAssertEqual(host.pluginView(withIdentifier: viewIdentifier)?.filePath, "Drawing.sketch")
        XCTAssertNil(workspace.tabDocuments[tabID]?.markdownSession)
        let tabCount = workspace.layout.allTabs.count

        _ = await workspace.open(try VaultPath("Note.md"), placement: .newTab)
        let reopenedTabID = await workspace.open(sketchPath)

        XCTAssertEqual(reopenedTabID, tabID, "The file is open in one tab.")
        XCTAssertEqual(workspace.layout.allTabs.count, tabCount + 1)
        XCTAssertEqual(workspace.layout.activeTab.id, tabID)
    }
}
