import XCTest
import SwiftUI
import WebKit
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

/// A community plugin running in WebKit inside the app, on the iPad and the Mac: loading,
/// commands that change the open note through its editor, `data.json`, the keychain, the
/// vault's own web storage, timers while no panel shows the plugin, and unloading when
/// another vault opens.
@MainActor
final class CommunityPluginHostTests: XCTestCase {
    private var window: HostedWindow?
    private var vaultDirectories: [URL] = []
    private var openedVaultIdentifiers: [UUID] = []
    private var workspace: WorkspaceModel?

    private static let pluginIdentifier = "graphite-host-test"

    /// A plugin with a command for each thing the tests check.
    private static let pluginSource = """
    'use strict';
    const { Plugin, EditorSuggest, ItemView } = require('obsidian');
    class CounterView extends ItemView {
        getViewType() { return 'graphite-counter'; }
        getDisplayText() { return 'Counter view'; }
        getIcon() { return 'clock'; }
        async onOpen() {
            let presses = 0;
            const button = this.contentEl.createEl('button', { cls: 'graphite-view-button', text: 'Pressed 0' });
            button.addEventListener('click', () => { presses += 1; button.setText('Pressed ' + presses); });
        }
    }
    class EmojiSuggest extends EditorSuggest {
        onTrigger(cursor, editor) {
            const match = /:(\\w*)$/.exec(editor.getLine(cursor.line).slice(0, cursor.ch));
            return match ? { start: { line: cursor.line, ch: cursor.ch - match[0].length }, end: cursor, query: match[1] } : null;
        }
        getSuggestions(context) { return ['smile', 'sun'].filter((name) => name.startsWith(context.query)); }
        renderSuggestion(name, element) { element.setText(name === 'smile' ? '😄 smile' : '☀️ sun'); }
        selectSuggestion(name) { this.context.editor.replaceRange(name === 'smile' ? '😄' : '☀️', this.context.start, this.context.end); this.close(); }
    }
    module.exports = class HostTestPlugin extends Plugin {
        async onload() {
            this.registerEditorSuggest(new EmojiSuggest(this.app));
            this.registerView('graphite-counter', (leaf) => new CounterView(leaf));
            this.addCommand({ id: 'open-tab-view', name: 'Open tab view', callback: async () => {
                await this.app.workspace.getLeaf('tab').setViewState({ type: 'graphite-counter', active: true });
            } });
            this.addCommand({ id: 'open-side-view', name: 'Open side view', callback: async () => {
                await this.app.workspace.getRightLeaf(false).setViewState({ type: 'graphite-counter', active: true });
            } });
            this.registerEvent(this.app.workspace.on('editor-change', (editor) => { this.changeCount = (this.changeCount || 0) + 1; window.lastHeardText = editor.getValue(); }));
            this.addCommand({ id: 'insert-text', name: 'Insert text', editorCallback: (editor) => editor.replaceSelection('inserted') });
            this.addCommand({ id: 'save-data', name: 'Save data', callback: () => this.saveData({ saved: true, list: [1, 2] }) });
            this.addCommand({ id: 'store-secret', name: 'Store secret', callback: () => this.app.secretStorage.setSecret('test-token', 'secret-value') });
            this.addCommand({ id: 'remember', name: 'Remember', callback: () => window.localStorage.setItem('graphite-host-test', 'remembered') });
            this.addCommand({ id: 'recall', name: 'Recall', callback: () => this.saveData({ recalled: window.localStorage.getItem('graphite-host-test') }) });
            this.addCommand({
                id: 'measure-interval', name: 'Measure interval', callback: () => {
                    let ticks = 0;
                    const interval = window.setInterval(() => { ticks += 1; }, 50);
                    window.setTimeout(() => { window.clearInterval(interval); this.saveData({ ticks, visibilityState: document.visibilityState }); }, 1000);
                },
            });
            this.registerMarkdownCodeBlockProcessor('graphite-count', (source, element) => {
                let count = Number(source.trim());
                const button = element.createEl('button', { cls: 'graphite-count', text: 'Count ' + count });
                button.addEventListener('click', () => { count += 1; button.setText('Count ' + count); });
                window.setTimeout(() => element.createDiv({ cls: 'graphite-later', text: 'Drawn later' }), 300);
            });
            this.registerEvent(this.app.workspace.on('file-menu', (menu, file, source) => {
                menu.addItem((item) => item.setTitle('Remember ' + file.name).onClick(() => this.saveData({ remembered: file.path, source })));
            }));
            this.registerEvent(this.app.workspace.on('editor-menu', (menu, editor) => {
                menu.addItem((item) => item.setTitle('Shout').onClick(() => editor.replaceSelection(editor.getSelection().toUpperCase())));
            }));
            this.registerMarkdownPostProcessor((element) => {
                for (const code of Array.from(element.querySelectorAll('code'))) {
                    if (code.textContent.startsWith('shout:')) code.replaceWith(createEl('strong', { cls: 'graphite-shout', text: code.textContent.slice(6).toUpperCase() }));
                }
            });
        }
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
        window?.closeAfterTest()
        window = nil
        for directory in vaultDirectories { try? FileManager.default.removeItem(at: directory) }
        vaultDirectories = []
        openedVaultIdentifiers = []
    }

    func testAPluginCommandChangesTheOpenNoteAndUndoTakesItBack() async throws {
        let (workspace, _, controller) = try await workspaceWithRunningPlugin(notes: ["Note.md": "Today: \nMore.\n"])
        let tab = try await openTab("Note.md", in: workspace)
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .source
        let editor = try await visibleEditor(in: controller, showing: session)
        editor.focus()
        editor.placeSelection(NSRange(location: 7, length: 0))
        try await waitUntil { session.selection.location == 7 }

        try await run("insert-text", in: workspace)
        try await waitUntil { session.text == "Today: inserted\nMore.\n" }
        XCTAssertTrue(editor.undoManager?.canUndo == true, "The plugin's change is an edit of the note's editor.")
        editor.undoManager?.undo()
        try await waitUntil { session.text == "Today: \nMore.\n" }
    }

    func testACommandRunWhileAnInsertionIsQueuedKeepsBoth() async throws {
        let (workspace, _, controller) = try await workspaceWithRunningPlugin(notes: ["Note.md": "Lecture.\n"])
        let tab = try await openTab("Note.md", in: workspace)
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .source
        let editor = try await visibleEditor(in: controller, showing: session)
        editor.focus()
        editor.placeSelection(NSRange(location: 0, length: 0))
        try await waitUntil { session.selection.location == 0 }

        session.insert("![[Recording.m4a]]\n", at: NSRange(location: 0, length: 0))
        XCTAssertNotNil(session.pendingInsertion)
        await workspace.communityPlugins.run(try command("insert-text", in: workspace))
        try await waitUntil { session.pendingInsertion == nil && session.text.contains("inserted") }
        XCTAssertTrue(session.text.contains("![[Recording.m4a]]\n"), "The queued insertion is kept: \(session.text)")
        XCTAssertTrue(session.text.hasSuffix("Lecture.\n"), session.text)
    }

    func testDataSecretsAndWebStorageStayWhereObsidianAndTheDeviceKeepThem() async throws {
        let (workspace, vault, _) = try await workspaceWithRunningPlugin(notes: ["Note.md": "Note.\n"])
        let host = workspace.communityPlugins
        let vaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        let dataFile = vault.appendingPathComponent(".obsidian/plugins/\(Self.pluginIdentifier)/data.json")

        try await run("save-data", in: workspace)
        try await waitUntil { FileManager.default.fileExists(atPath: dataFile.path) }
        XCTAssertEqual(try String(contentsOf: dataFile, encoding: .utf8), "{\n  \"saved\": true,\n  \"list\": [\n    1,\n    2\n  ]\n}",
                       "data.json is written as Obsidian writes it, JSON.stringify(data, null, 2).")
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent(".obsidian/community-plugins.json"), encoding: .utf8), "[\n  \"\(Self.pluginIdentifier)\"\n]")

        try await run("store-secret", in: workspace)
        try await waitUntil { (try? CommunityPluginSecretStore(vaultIdentifier: vaultIdentifier).secrets())?["test-token"] == "secret-value" }

        let webView = try XCTUnwrap(host.webView)
        XCTAssertEqual(webView.configuration.websiteDataStore.identifier, vaultIdentifier, "Each vault has its own web storage.")
        #if DEBUG
        XCTAssertTrue(webView.isInspectable, "Debug builds let Safari's Web Inspector show the runtime.")
        #endif
        try await run("remember", in: workspace)
        await host.restartPlugins()
        try await waitUntil(timeoutSeconds: 15) { host.loadStates[Self.pluginIdentifier] == .loaded }
        XCTAssertFalse(host.webView === webView, "The restart made a new web view.")
        XCTAssertEqual(host.webView?.configuration.websiteDataStore.identifier, vaultIdentifier)
        try await run("recall", in: workspace)
        try await waitUntil { (try? String(contentsOf: dataFile, encoding: .utf8))?.contains("\"recalled\": \"remembered\"") == true }
    }

    func testTimersRunAtFullRateWhileNoPanelShowsThePlugin() async throws {
        let (workspace, vault, _) = try await workspaceWithRunningPlugin(notes: ["Note.md": "Note.\n"])
        let host = workspace.communityPlugins
        try await waitUntil { host.webView?.window != nil }
        XCTAssertFalse(host.isPanelPresented)
        try await run("measure-interval", in: workspace)
        let dataFile = vault.appendingPathComponent(".obsidian/plugins/\(Self.pluginIdentifier)/data.json")
        try await waitUntil(timeoutSeconds: 5) { FileManager.default.fileExists(atPath: dataFile.path) }
        let measurement = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: dataFile)) as? [String: Any])
        XCTAssertEqual(measurement["visibilityState"] as? String, "visible")
        // 20 ticks of 50 ms fit in a second; a page outside the window gets about one.
        XCTAssertGreaterThanOrEqual(measurement["ticks"] as? Int ?? 0, 12, "\(measurement)")
    }

    func testPluginsUnloadWhenAnotherVaultOpens() async throws {
        let (workspace, _, _) = try await workspaceWithRunningPlugin(notes: ["Note.md": "Note.\n"])
        let host = workspace.communityPlugins
        XCTAssertFalse(host.commands.isEmpty)
        let secondVault = try makeVault(notes: ["Other.md": "Other.\n"], pluginEnabled: false)
        try await workspace.openFolderAsVault(secondVault)
        openedVaultIdentifiers.append(try XCTUnwrap(workspace.currentVaultIdentifier))
        XCTAssertFalse(host.isRuntimeRunning)
        XCTAssertNil(host.webView)
        XCTAssertTrue(host.commands.isEmpty)
        XCTAssertTrue(host.loadStates.isEmpty)
        XCTAssertFalse(host.isTurnedOnForVault, "Plugins are turned on per vault.")
    }

    func testAPluginsCodeBlockIsDrawnInTheReadingViewAndATapReachesThePlugin() async throws {
        let (workspace, _, controller) = try await workspaceWithRunningPlugin(notes: ["Count.md": "Before.\n\n```graphite-count\n3\n```\n\nAfter.\n"])
        let host = workspace.communityPlugins
        try await waitUntil { host.codeBlockLanguages == ["graphite-count"] }
        let tab = try await openTab("Count.md", in: workspace)
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .reading
        // The block's copy shows in a web view of its own, not the plugins' web view.
        try await waitUntil(timeoutSeconds: 15) { self.codeBlockWebViews(in: controller, host: host).count == 1 }
        let blockWebView = try XCTUnwrap(codeBlockWebViews(in: controller, host: host).first)
        try await waitUntil(timeoutSeconds: 10) { blockWebView.bounds.height > 10 }
        var shownHTML = try await codeBlockHTML(blockWebView)
        for _ in 0..<100 where !shownHTML.contains("Count 3") {
            try await Task.sleep(for: .milliseconds(50))
            shownHTML = try await codeBlockHTML(blockWebView)
        }
        XCTAssertTrue(shownHTML.contains("<button class=\"graphite-count\">Count 3</button>"), shownHTML)
        // What the plugin draws after answering reaches the copy too.
        for _ in 0..<100 where !shownHTML.contains("Drawn later") {
            try await Task.sleep(for: .milliseconds(50))
            shownHTML = try await codeBlockHTML(blockWebView)
        }
        XCTAssertTrue(shownHTML.contains("Drawn later"), shownHTML)
        XCTAssertFalse(blockWebView.configuration.defaultWebpagePreferences.allowsContentJavaScript, "The copy runs no script of its own.")

        // A tap in the copy is sent to the plugin's button, whose handler counts.
        _ = try await blockWebView.callAsyncJavaScript("document.querySelector('button.graphite-count').click()", arguments: [:], in: nil, contentWorld: .defaultClient)
        for _ in 0..<100 where !shownHTML.contains("Count 4") {
            try await Task.sleep(for: .milliseconds(50))
            shownHTML = try await codeBlockHTML(blockWebView)
        }
        let runtimeHTML = try await host.webView?.callAsyncJavaScript("return document.querySelector('.graphite-reading-blocks').innerHTML", arguments: [:], in: nil, contentWorld: .page) as? String
        XCTAssertTrue(shownHTML.contains("Count 4"), shownHTML + " | runtime: " + (runtimeHTML ?? "nil") + " | shown blocks: \(host.shownCodeBlocks.count)")

        // Leaving reading view releases the plugin's block.
        session.viewMode = .source
        try await waitUntil(timeoutSeconds: 5) { host.shownCodeBlocks.isEmpty }
    }

    func testASectionAPluginChangesIsShownAsThePluginDrewItAndTheRestStaysNative() async throws {
        let (workspace, _, controller) = try await workspaceWithRunningPlugin(notes: ["Shout.md": "Plain words.\n\nSay `shout:hello` here.\n\nMore plain words.\n"])
        let host = workspace.communityPlugins
        try await waitUntil { host.runsMarkdownPostProcessors }
        let tab = try await openTab("Shout.md", in: workspace)
        workspace.document(for: tab).markdownSession?.viewMode = .reading
        try await waitUntil(timeoutSeconds: 15) { self.codeBlockWebViews(in: controller, host: host).count == 1 }
        let sectionWebView = try XCTUnwrap(codeBlockWebViews(in: controller, host: host).first)
        var shownHTML = try await codeBlockHTML(sectionWebView)
        for _ in 0..<100 where !shownHTML.contains("HELLO") {
            try await Task.sleep(for: .milliseconds(50))
            shownHTML = try await codeBlockHTML(sectionWebView)
        }
        XCTAssertTrue(shownHTML.contains("<strong class=\"graphite-shout\">HELLO</strong>"), shownHTML)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(codeBlockWebViews(in: controller, host: host).count, 1, "Sections no plugin changes stay Graphite's own.")
    }

    func testPluginsItemsInFileAndEditorMenusRunThePluginsCode() async throws {
        let (workspace, vault, controller) = try await workspaceWithRunningPlugin(notes: ["Menu.md": "quiet words\n"])
        let host = workspace.communityPlugins
        try await waitUntil { host.hasFileMenuItems && host.hasEditorMenuItems }
        let fileMenu = try await XCTUnwrapAsync(await host.fileMenu(for: [try VaultPath("Menu.md")]))
        XCTAssertEqual(fileMenu.items.map(\.title), ["Remember Menu.md"])
        host.choose(try XCTUnwrap(fileMenu.items.first), in: fileMenu)
        let dataFile = vault.appendingPathComponent(".obsidian/plugins/\(Self.pluginIdentifier)/data.json")
        try await waitUntil { (try? String(contentsOf: dataFile, encoding: .utf8))?.contains("\"remembered\": \"Menu.md\"") == true }
        XCTAssertTrue(try String(contentsOf: dataFile, encoding: .utf8).contains("file-explorer-context-menu"))

        // The editor's menu works on the note as its editor holds it, selection included.
        let tab = try await openTab("Menu.md", in: workspace)
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .source
        let editor = try await visibleEditor(in: controller, showing: session)
        editor.focus()
        editor.placeSelection(NSRange(location: 0, length: 5))
        try await waitUntil { session.selection == NSRange(location: 0, length: 5) }
        let editorMenu = try await XCTUnwrapAsync(await host.editorMenu())
        XCTAssertEqual(editorMenu.items.map(\.title), ["Shout"])
        host.choose(try XCTUnwrap(editorMenu.items.first), in: editorMenu)
        try await waitUntil { session.text == "QUIET words\n" }
    }

    func testTypingReachesPluginsAndTheirSuggestionsAreInsertedByThem() async throws {
        let (workspace, _, controller) = try await workspaceWithRunningPlugin(notes: ["Typing.md": "Mood \n"])
        let host = workspace.communityPlugins
        try await waitUntil { host.hasEditorSuggestions && host.hasEditorChangeListeners }
        let tab = try await openTab("Typing.md", in: workspace)
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .source
        let editor = try await visibleEditor(in: controller, showing: session)
        // Suggestions show only while the note takes typing.
        editor.beginTyping()
        try await waitUntil { editor.hasKeyboardFocus }
        editor.placeSelection(NSRange(location: 5, length: 0))
        try await waitUntil { session.selection.location == 5 }
        // Typed one key at a time, as the keyboard sends them.
        for character in [":", "s", "m"] {
            editor.type(character)
            try await Task.sleep(for: .milliseconds(30))
        }
        try await waitUntil(timeoutSeconds: 5) { session.completion.items.map(\.title) == ["😄 smile"] }
        let heardText = try await host.webView?.callAsyncJavaScript("return window.lastHeardText", arguments: [:], in: nil, contentWorld: .page) as? String
        XCTAssertEqual(heardText, "Mood :sm\n", "The plugin heard the change as typed.")
        session.completion.accept()
        try await waitUntil { session.text == "Mood 😄\n" }
        XCTAssertTrue(editor.undoManager?.canUndo == true, "The plugin's insertion can be undone.")
    }

    func testPluginViewsOpenInATabOrTheSidebarAndCloseWithTheirTab() async throws {
        let (workspace, _, controller) = try await workspaceWithRunningPlugin(notes: ["Note.md": "Note.\n"])
        let host = workspace.communityPlugins
        try await run("open-side-view", in: workspace)
        try await waitUntil { host.sidebarViewRequest != nil && host.sidebarViews.map(\.title) == ["Counter view"] }
        XCTAssertEqual(host.sidebarViews.first?.icon, "clock")
        XCTAssertFalse(host.isPanelPresented, "Views no longer open on the plugin panel.")

        try await run("open-tab-view", in: workspace)
        try await waitUntil { workspace.document(for: workspace.layout.activeTab.id).pluginViewIdentifier != nil }
        let tabID = workspace.layout.activeTab.id
        let viewIdentifier = try XCTUnwrap(workspace.document(for: tabID).pluginViewIdentifier)
        XCTAssertEqual(host.pluginView(withIdentifier: viewIdentifier)?.placement, .tab)
        try await waitUntil(timeoutSeconds: 15) { self.codeBlockWebViews(in: controller, host: host).count == 1 }
        let viewWebView = try XCTUnwrap(codeBlockWebViews(in: controller, host: host).first)
        var shownHTML = ""
        for _ in 0..<100 where !shownHTML.contains("Pressed 0") {
            try await Task.sleep(for: .milliseconds(50))
            shownHTML = try await codeBlockHTML(viewWebView)
        }
        XCTAssertTrue(shownHTML.contains("Pressed 0"), shownHTML)
        #if os(iOS)
        XCTAssertTrue(viewWebView.scrollView.isScrollEnabled, "A view scrolls inside its tab.")
        #endif
        _ = try await viewWebView.callAsyncJavaScript("document.querySelector('button.graphite-view-button').click()", arguments: [:], in: nil, contentWorld: .defaultClient)
        for _ in 0..<100 where !shownHTML.contains("Pressed 1") {
            try await Task.sleep(for: .milliseconds(50))
            shownHTML = try await codeBlockHTML(viewWebView)
        }
        XCTAssertTrue(shownHTML.contains("Pressed 1"), "The tap reached the plugin's view: " + shownHTML)

        await workspace.closeTab(tabID)
        try await waitUntil { host.pluginView(withIdentifier: viewIdentifier) == nil }
        XCTAssertEqual(host.sidebarViews.count, 1, "The sidebar's view stays open.")
    }

    func testDataviewAndTasksQueriesAreDrawnInTheReadingView() async throws {
        let note = "# Queries\n\n```tasks\nnot done\npath includes Queries\n```\n\n```dataview\nTABLE rating, author FROM \"Books\" SORT rating DESC\n```\n\n- [ ] Write the report\n- [x] Book the room\n"
        let (workspace, _, controller) = try await workspaceWithBuiltPlugins(["dataview", "obsidian-tasks-plugin"], notes: [
            "Queries.md": note,
            "Books/Dune.md": "---\nrating: 5\nauthor: Frank Herbert\n---\nDesert.\n",
            "Books/Emma.md": "---\nrating: 4\nauthor: Jane Austen\n---\nMatches.\n",
        ])
        let host = workspace.communityPlugins
        try await waitUntil(timeoutSeconds: 10) { host.codeBlockLanguages.isSuperset(of: ["dataview", "tasks"]) }
        let tab = try await openTab("Queries.md", in: workspace)
        workspace.document(for: tab).markdownSession?.viewMode = .reading
        try await waitUntil(timeoutSeconds: 15) { self.codeBlockWebViews(in: controller, host: host).count >= 2 }
        var shownHTML = ""
        for _ in 0..<200 {
            var copies: [String] = []
            for webView in codeBlockWebViews(in: controller, host: host) { copies.append(try await codeBlockHTML(webView)) }
            shownHTML = copies.joined(separator: "\n")
            if shownHTML.contains("Frank Herbert") && shownHTML.contains("Write the report") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let runtimeHTML = try await host.webView?.callAsyncJavaScript("return document.querySelector('.graphite-reading-blocks').outerHTML", arguments: [:], in: nil, contentWorld: .page) as? String
        XCTAssertTrue(shownHTML.contains("Frank Herbert"), "Dataview's table: " + shownHTML + "\nRuntime: " + (runtimeHTML ?? "") + "\nProblems: \(host.runtimeProblems)")
        XCTAssertTrue(shownHTML.contains("Write the report"), "Tasks' list: " + shownHTML)
        XCTAssertFalse(shownHTML.contains("Book the room"), "Done tasks are not listed.")
    }

    // MARK: The directory sweep's plugins

    // Plugins the sweep of Obsidian's directory found working on the iPad (Docs/Community-plugins.md),
    // built from their sources at the commits the Node tests pin, each tried on its main feature.

    func testAdmonitionDrawsItsBlockAsACalloutInTheReadingView() async throws {
        let note = "Before.\n\n```ad-note\ntitle: Remember\nThe exam is on Friday.\n```\n\nAfter.\n"
        let (workspace, _, controller) = try await workspaceWithBuiltPlugins(["obsidian-admonition"], notes: ["Callout.md": note])
        let host = workspace.communityPlugins
        try await waitUntil { host.codeBlockLanguages.contains("ad-note") }
        let tab = try await openTab("Callout.md", in: workspace)
        workspace.document(for: tab).markdownSession?.viewMode = .reading
        try await waitUntil(timeoutSeconds: 15) { self.codeBlockWebViews(in: controller, host: host).count == 1 }
        let blockWebView = try XCTUnwrap(codeBlockWebViews(in: controller, host: host).first)
        let shownHTML = try await shownHTML(of: blockWebView, containing: "The exam is on Friday.")
        XCTAssertTrue(shownHTML.contains("callout") && shownHTML.contains("Remember"), shownHTML)
    }

    func testHighlightrWrapsTheSelectionInItsHighlight() async throws {
        let (workspace, _, controller) = try await workspaceWithBuiltPlugins(["highlightr-plugin"], notes: ["Words.md": "quiet words\n"])
        let tab = try await openTab("Words.md", in: workspace)
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .source
        let editor = try await visibleEditor(in: controller, showing: session)
        editor.focus()
        editor.placeSelection(NSRange(location: 0, length: 5))
        try await waitUntil { session.selection == NSRange(location: 0, length: 5) }
        try await run(pluginCommand: "highlightr-plugin:Yellow", in: workspace)
        try await waitUntil { session.text.hasPrefix("<mark") && session.text.contains(">quiet</mark> words") }
        editor.undoManager?.undo()
        try await waitUntil { session.text == "quiet words\n" }
    }

    func testListToTableConvertsTheSelectedListAndUndoTakesItBack() async throws {
        let (workspace, _, controller) = try await workspaceWithBuiltPlugins(["list-to-table"], notes: ["Fruits.md": "Fruits:\n- apple\n- pear\n"])
        let tab = try await openTab("Fruits.md", in: workspace)
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .source
        let editor = try await visibleEditor(in: controller, showing: session)
        editor.focus()
        editor.placeSelection(NSRange(location: 8, length: 15))
        try await waitUntil { session.selection == NSRange(location: 8, length: 15) }
        try await run(pluginCommand: "list-to-table:convert-list-to-table", in: workspace)
        try await waitUntil { session.text == "Fruits:\n|          |\n| -------- |\n| apple |\n| pear |\n" }
        editor.undoManager?.undo()
        try await waitUntil { session.text == "Fruits:\n- apple\n- pear\n" }
    }

    func testOmnisearchIndexesTheVaultAndFindsANoteByItsWords() async throws {
        let (workspace, _, _) = try await workspaceWithBuiltPlugins(["omnisearch"], notes: [
            "Physics.md": "Momentum is conserved in every collision.\n", "Chemistry.md": "Atoms share electrons.\n",
        ])
        let host = workspace.communityPlugins
        var foundPaths: [String] = []
        // It indexes the vault once layout is ready; its API (`globalThis.omnisearch`) searches the index.
        try await waitUntil("Omnisearch finds the note", timeoutSeconds: 10) {
            let answer = try await host.webView?.callAsyncJavaScript(
                "const results = globalThis.omnisearch ? await globalThis.omnisearch.search('momentum') : []; return results.map((result) => result.path)",
                arguments: [:], in: nil, contentWorld: .page)
            foundPaths = answer as? [String] ?? []
            return foundPaths == ["Physics.md"]
        }
        XCTAssertEqual(foundPaths, ["Physics.md"], "Problems: \(host.runtimeProblems)")
        try await run(pluginCommand: "omnisearch:show-modal", in: workspace)
        try await waitUntil("Omnisearch's search window on the plugin panel") { host.isPanelPresented }
    }

    func testNotebookNavigatorListsTheVaultsNotesInTheSidebar() async throws {
        let (workspace, _, _) = try await workspaceWithBuiltPlugins(["notebook-navigator"], notes: [
            "Lectures/Mechanics.md": "Forces.\n", "Lectures/Optics.md": "Light.\n",
        ])
        let host = workspace.communityPlugins
        try await waitUntil("its view in the sidebar", timeoutSeconds: 15) { host.sidebarViews.contains { view in view.title == "Notebook Navigator" } }
        var pageText = ""
        try await waitUntil("the navigator lists the vault's folder", timeoutSeconds: 10) {
            let answer = try await host.webView?.callAsyncJavaScript("return document.body.innerText", arguments: [:], in: nil, contentWorld: .page)
            pageText = answer as? String ?? ""
            return pageText.contains("Lectures")
        }
        XCTAssertTrue(pageText.contains("Lectures"), "The navigator lists the vault's folder: \(pageText.prefix(400))")
    }

    func testVaultRouterSweepsTheInboxByItsRules() async throws {
        let (workspace, vault, _) = try await workspaceWithBuiltPlugins(["vault-router"], notes: [
            "Inbox/Daily - Monday.md": "Today.\n",
            "Inbox/Standup.md": "---\ntags: [meeting]\nproject: Apollo\n---\nNotes.\n",
            "Inbox/Idea.md": "No rule for this one.\n",
        ])
        try await run(pluginCommand: "vault-router:route-inbox-now", in: workspace)
        let fileManager = FileManager.default
        try await waitUntil("the notes moved by their rules") {
            fileManager.fileExists(atPath: vault.appendingPathComponent("Journal/Daily/Daily - Monday.md").path)
                && fileManager.fileExists(atPath: vault.appendingPathComponent("Meetings/Apollo/Standup.md").path)
        }
        XCTAssertFalse(fileManager.fileExists(atPath: vault.appendingPathComponent("Inbox/Daily - Monday.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: vault.appendingPathComponent("Inbox/Idea.md").path), "A note no rule matches stays.")
    }

    func testMergeAndOpenTargetMergesANoteIntoAnotherAndOpensIt() async throws {
        let (workspace, vault, _) = try await workspaceWithBuiltPlugins(["merge-open-target"], notes: [
            "Draft.md": "Draft idea.\n", "Project.md": "# Project\n",
        ])
        let host = workspace.communityPlugins
        _ = try await openTab("Draft.md", in: workspace)
        try await run(pluginCommand: "merge-open-target:merge-current-file-into-another-and-open-target", in: workspace)
        try await clickInPluginPage(".suggestion-item", containing: "Project", host: host)
        try await clickInPluginPage(".modal button.mod-cta", containing: nil, host: host)
        try await waitUntil("Draft merged into Project") {
            (try? String(contentsOf: vault.appendingPathComponent("Project.md"), encoding: .utf8))?.contains("Draft idea.") == true
        }
        try await waitUntil("Draft in the trash") { !FileManager.default.fileExists(atPath: vault.appendingPathComponent("Draft.md").path) }
        try await waitUntil("Project open") { workspace.layout.tabID(showing: try VaultPath("Project.md")) != nil }
    }

    // MARK: Helpers

    private func XCTUnwrapAsync<Value>(_ value: Value?, file: StaticString = #filePath, line: UInt = #line) async throws -> Value {
        try XCTUnwrap(value, file: file, line: line)
    }

    private func codeBlockWebViews(in controller: HostedViewController, host: CommunityPluginHost) -> [WKWebView] {
        descendants(of: controller.view, matching: WKWebView.self).filter { webView in webView !== host.webView && webView.window != nil }
    }

    /// What a copy shows once it shows `text`, read again for up to five seconds.
    private func shownHTML(of webView: WKWebView, containing text: String) async throws -> String {
        var shownHTML = ""
        try await waitUntil("the copy shows \(text)", timeoutSeconds: 5) {
            shownHTML = try await self.codeBlockHTML(webView)
            return shownHTML.contains(text)
        }
        return shownHTML
    }

    /// Clicks, in the plugins' page, the first element matching `selector` whose text has
    /// `text`, once there is one: as a person does in a plugin's window on the plugin panel.
    private func clickInPluginPage(_ selector: String, containing text: String?, host: CommunityPluginHost) async throws {
        let script = """
        const element = Array.from(document.querySelectorAll(selector)).find((candidate) => text === null || candidate.textContent.includes(text));
        if (!element) return false;
        element.click();
        return true;
        """
        try await waitUntil("\(selector) with \(text ?? "any text") clicked in the plugins' page", timeoutSeconds: 5) {
            try await host.webView?.callAsyncJavaScript(script, arguments: ["selector": selector, "text": text as Any? ?? NSNull()],
                                                        in: nil, contentWorld: .page) as? Bool ?? false
        }
    }

    private func run(pluginCommand commandIdentifier: String, in workspace: WorkspaceModel) async throws {
        let commands = workspace.communityPlugins.commands
        let command = try XCTUnwrap(commands.first { command in command.id == commandIdentifier },
                                    "No command \(commandIdentifier); there are \(commands.map(\.id))")
        await workspace.communityPlugins.run(command)
    }

    private func codeBlockHTML(_ webView: WKWebView) async throws -> String {
        let html = try await webView.callAsyncJavaScript("const root = document.querySelector('.graphite-code-block-root'); return root ? root.innerHTML : ''", arguments: [:], in: nil, contentWorld: .defaultClient)
        return html as? String ?? ""
    }

    private func makeVault(notes: [String: String], pluginEnabled: Bool) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CommunityPluginHost-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        vaultDirectories.append(directory)
        for (name, text) in notes {
            let file = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
        }
        guard pluginEnabled else { return directory }
        let pluginFolder = directory.appendingPathComponent(".obsidian/plugins/\(Self.pluginIdentifier)")
        try FileManager.default.createDirectory(at: pluginFolder, withIntermediateDirectories: true)
        let manifest = "{\"id\": \"\(Self.pluginIdentifier)\", \"name\": \"Graphite Host Test\", \"version\": \"1.0.0\", \"minAppVersion\": \"1.0.0\", \"author\": \"Graphite\"}"
        try Data(manifest.utf8).write(to: pluginFolder.appendingPathComponent("manifest.json"))
        try Data(Self.pluginSource.utf8).write(to: pluginFolder.appendingPathComponent("main.js"))
        try Data("[\n  \"\(Self.pluginIdentifier)\"\n]".utf8).write(to: directory.appendingPathComponent(".obsidian/community-plugins.json"))
        return directory
    }

    /// A vault opened as the app opens one, in a window, with community plugins turned on
    /// and the test plugin running. The window comes first, as in the app: a first window
    /// shown after the plugin web view started stayed blank in a hosted test.
    private func workspaceWithRunningPlugin(notes: [String: String]) async throws -> (WorkspaceModel, URL, HostedViewController) {
        let vault = try makeVault(notes: notes, pluginEnabled: true)
        let workspace = WorkspaceModel()
        self.workspace = workspace
        try await workspace.openFolderAsVault(vault)
        openedVaultIdentifiers.append(try XCTUnwrap(workspace.currentVaultIdentifier))
        let controller = try host(workspace)
        let host = workspace.communityPlugins
        await host.reloadInventory() // opening lists nothing while plugins are off
        try await waitUntil { host.inventory.plugins.contains { plugin in plugin.id == Self.pluginIdentifier } }
        await host.setTurnedOnForVault(true)
        try await waitUntil(timeoutSeconds: 15) { host.loadStates[Self.pluginIdentifier] == .loaded }
        try await waitUntil { host.commands.contains { command in command.id == Self.pluginIdentifier + ":save-data" } }
        return (workspace, vault, controller)
    }

    /// The folder `npm run build-compatibility-plugins` builds real plugins into, in the Mac's
    /// checkout: the simulator's apps and an unsandboxed Mac test host can read it.
    private static let builtPluginsFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Tests/CommunityPluginRuntimeTests/compatibility/built")

    /// A vault with real plugins, built from their sources at the commits the Node tests pin,
    /// installed as Graphite installs them, turned on and loaded, in a window. Skipped when
    /// they are not built.
    private func workspaceWithBuiltPlugins(_ pluginIdentifiers: [String], notes: [String: String]) async throws
        -> (WorkspaceModel, URL, HostedViewController) {
        let builtFolders = pluginIdentifiers.map { plugin in Self.builtPluginsFolder.appendingPathComponent(plugin) }
        guard builtFolders.allSatisfy({ folder in FileManager.default.fileExists(atPath: folder.appendingPathComponent("main.js").path) }) else {
            throw XCTSkip("\(pluginIdentifiers.joined(separator: ", ")) not built (npm run build-compatibility-plugins).")
        }
        let vault = try makeVault(notes: notes, pluginEnabled: false)
        for (plugin, builtFolder) in zip(pluginIdentifiers, builtFolders) {
            let destination = vault.appendingPathComponent(".obsidian/plugins/" + plugin)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for file in ["main.js", "manifest.json", "styles.css"] where FileManager.default.fileExists(atPath: builtFolder.appendingPathComponent(file).path) {
                try FileManager.default.copyItem(at: builtFolder.appendingPathComponent(file), to: destination.appendingPathComponent(file))
            }
        }
        let enabledList = try JSONSerialization.data(withJSONObject: pluginIdentifiers, options: [.prettyPrinted])
        try enabledList.write(to: vault.appendingPathComponent(".obsidian/community-plugins.json"))
        let workspace = WorkspaceModel()
        self.workspace = workspace
        try await workspace.openFolderAsVault(vault)
        openedVaultIdentifiers.append(try XCTUnwrap(workspace.currentVaultIdentifier))
        let controller = try host(workspace)
        let host = workspace.communityPlugins
        await host.reloadInventory() // opening lists nothing while plugins are off
        try await waitUntil { Set(host.inventory.plugins.map(\.id)).isSuperset(of: pluginIdentifiers) }
        await host.setTurnedOnForVault(true)
        try await waitUntil("\(pluginIdentifiers) loaded", timeoutSeconds: 30) {
            pluginIdentifiers.allSatisfy { plugin in host.loadStates[plugin] == .loaded }
        }
        return (workspace, vault, controller)
    }

    private func command(_ commandIdentifier: String, in workspace: WorkspaceModel) throws -> CommunityPluginCommand {
        try XCTUnwrap(workspace.communityPlugins.commands.first { command in command.id == Self.pluginIdentifier + ":" + commandIdentifier })
    }

    private func run(_ commandIdentifier: String, in workspace: WorkspaceModel) async throws {
        await workspace.communityPlugins.run(try command(commandIdentifier, in: workspace))
    }

    private func openTab(_ name: String, in workspace: WorkspaceModel) async throws -> UUID {
        let path = try VaultPath(name)
        await workspace.open(path, placement: .currentTab)
        return try XCTUnwrap(workspace.layout.tabID(showing: path))
    }

    /// The workspace in a window, with the plugin panel, notices and the web view's parking place.
    private func host(_ workspace: WorkspaceModel) throws -> HostedViewController {
        let rootView = AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }.modifier(CommunityPluginPresentation(workspace: workspace) {}))
        #if os(iOS)
        let controller = UIHostingController(rootView: rootView)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        #else
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        window.setContentSize(Self.macWindowSize)
        window.showInvisibly()
        window.makeKey()
        #endif
        self.window = window
        return controller
    }

    #if os(macOS)
    /// An iPad Pro 11-inch's window in landscape, so both platforms lay the note out alike.
    private static let macWindowSize = NSSize(width: 1210, height: 834)
    #endif

    private func visibleEditor(in controller: HostedViewController, showing session: MarkdownSession) async throws -> HostedEditor {
        try await waitUntil { self.editors(in: controller).contains { editor in editor.shownText == session.text && editor.bounds.width > 0 } }
        return try XCTUnwrap(editors(in: controller).first { editor in editor.shownText == session.text },
                             "Editors show \(editors(in: controller).map(\.shownText)); the note is \(session.text)")
    }

    private func editors(in controller: HostedViewController) -> [HostedEditor] {
        descendants(of: controller.view, matching: HostedEditor.self).filter { editor in editor.window != nil }
    }

    private func descendants<View: HostedPlatformView>(of parent: HostedPlatformView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }

}

#if os(iOS)
private typealias HostedWindow = UIWindow
private typealias HostedViewController = UIHostingController<AnyView>
private typealias HostedPlatformView = UIView
private typealias HostedEditor = MarkdownTextView

private extension UIWindow {
    func closeAfterTest() {
        isHidden = true
        rootViewController = nil
    }
}

/// The editor operations the tests make, named once for the iPad's text view and the Mac's.
private extension MarkdownTextView {
    var shownText: String { text ?? "" }
    var hasKeyboardFocus: Bool { isFirstResponder }
    func focus() { becomeFirstResponder() }
    /// Takes typing, as a tap in the note does; suggestions show only then.
    func beginTyping() { beginEditing() }
    func placeSelection(_ range: NSRange) { selectedRange = range }
    /// One key typed, as the keyboard sends it.
    func type(_ text: String) { insertText(text) }
}
#else
private typealias HostedWindow = NSWindow
private typealias HostedViewController = NSHostingController<AnyView>
private typealias HostedPlatformView = NSView
private typealias HostedEditor = MarkdownMacTextView

private extension NSWindow {
    func closeAfterTest() {
        orderOut(nil)
        contentViewController = nil
    }
}

private extension MarkdownMacTextView {
    var shownText: String { string }
    var hasKeyboardFocus: Bool { window?.firstResponder === self }
    func focus() { window?.makeFirstResponder(self) }
    func beginTyping() { focus() }
    func placeSelection(_ range: NSRange) { setSelectedRange(range) }
    func type(_ text: String) { insertText(text, replacementRange: selectedRange()) }
}
#endif
