import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// What `CommunityPluginHost` does, in which order, when it starts the plugins of a vault:
/// the page loads, the runtime starts with the vault's files, each enabled plugin loads in
/// name order, the layout is ready, the saved views open, and the focused note is announced.
@MainActor
final class CommunityPluginHostStartSequenceTests: XCTestCase {
    private let testBed = CommunityPluginHostTestBed()

    override func tearDown() async throws {
        await testBed.tearDown()
    }

    private static func recordingPluginSource(opensView: Bool) -> String {
        """
        'use strict';
        const { Plugin, ItemView } = require('obsidian');
        class RecordedView extends ItemView {
            getViewType() { return 'recorded-view'; }
            getDisplayText() { return 'Recorded'; }
            getIcon() { return 'clock'; }
            async onOpen() { window.startSequence.push('view.onOpen'); }
        }
        module.exports = class RecordingPlugin extends Plugin {
            async onload() {
                window.startSequence = window.startSequence || [];
                const identifier = this.manifest.id;
                window.startSequence.push('plugin.load:' + identifier + ':files=' + this.app.vault.getFiles().length + ':layoutReady=' + this.app.workspace.layoutReady);
                this.app.workspace.onLayoutReady(() => window.startSequence.push('layoutReady:' + identifier));
                this.registerEvent(this.app.workspace.on('file-open', (file) => window.startSequence.push('file-open:' + identifier + ':' + (file ? file.path : 'none'))));
                if (\(opensView ? "true" : "false")) {
                    this.registerView('recorded-view', (leaf) => new RecordedView(leaf));
                    this.addCommand({ id: 'open-side-view', name: 'Open side view', callback: async () => {
                        await this.app.workspace.getRightLeaf(false).setViewState({ type: 'recorded-view', active: true });
                    } });
                }
            }
        };
        """
    }

    func testPluginsLoadInNameOrderAfterTheVaultIsReadAndTheLayoutIsReadyBeforeTheViewsAndTheNoteAreAnnounced() async throws {
        let workspace = try await testBed.workspaceWithRunningPlugins([
            ("b-recorder", Self.recordingPluginSource(opensView: false)),
            ("a-recorder", Self.recordingPluginSource(opensView: true)),
        ])
        let host = workspace.communityPlugins
        await workspace.open(try VaultPath("Note.md"))
        try await testBed.runCommand("open-side-view", of: "a-recorder", in: workspace)
        try await waitUntil("Graphite keeps what opens the sidebar view again") { workspace.restorableSidebarPluginViews.views.contains { view in view.viewType == "recorded-view" } }

        await host.restartPlugins()

        let expectedSequence = [
            "plugin.load:a-recorder:files=1:layoutReady=false",
            "plugin.load:b-recorder:files=1:layoutReady=false",
            "layoutReady:a-recorder",
            "layoutReady:b-recorder",
            "view.onOpen",
            "file-open:a-recorder:Note.md",
            "file-open:b-recorder:Note.md",
        ]
        var sequence: [String] = []
        let deadline = Date.now.addingTimeInterval(20)
        while sequence != expectedSequence, Date.now < deadline {
            sequence = try await testBed.evaluate("return window.startSequence;", in: host) as? [String] ?? []
            await Task.yield()
        }
        XCTAssertEqual(sequence, expectedSequence)
        XCTAssertTrue(host.hasRestoredViews)
    }
}
