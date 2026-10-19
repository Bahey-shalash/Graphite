import XCTest
import GraphiteCore
@testable import GraphiteUI

/// `CommunityPluginHost` telling plugins about typing in the focused note: the changes reach
/// plugins in order, the suggestions of the latest change are the ones shown, and a note too
/// long to send at every keystroke is not sent.
@MainActor
final class CommunityPluginHostTypingTests: XCTestCase {
    private let testBed = CommunityPluginHostTestBed()

    override func tearDown() async throws {
        await testBed.tearDown()
    }

    /// Suggests the first line of the note followed by "!". The answer for the line "one" waits
    /// until the test releases it, and every question and answer is recorded in order.
    private static let suggestingPluginSource = """
    'use strict';
    const { Plugin, EditorSuggest } = require('obsidian');
    class FirstLineSuggest extends EditorSuggest {
        onTrigger(cursor, editor) {
            const line = editor.getLine(0);
            return { start: { line: 0, ch: 0 }, end: { line: 0, ch: line.length }, query: line };
        }
        async getSuggestions(context) {
            window.suggestionLog.push('asked:' + context.query);
            if (context.query === 'one') await new Promise((resolve) => { window.releaseFirstAnswer = resolve; });
            window.suggestionLog.push('answered:' + context.query);
            return [context.query + '!'];
        }
        renderSuggestion(value, element) { element.setText(value); }
        selectSuggestion(value) {}
    }
    module.exports = class SuggestingPlugin extends Plugin {
        onload() {
            window.suggestionLog = [];
            this.registerEditorSuggest(new FirstLineSuggest(this.app));
        }
    };
    """

    private static let listeningPluginSource = """
    'use strict';
    const { Plugin } = require('obsidian');
    module.exports = class ListeningPlugin extends Plugin {
        onload() { this.registerEvent(this.app.workspace.on('editor-change', () => {})); }
    };
    """

    func testSuggestionsReturnOnlyForTheLatestChangeAndThePluginIsAskedInTheOrderTheChangesWereMade() async throws {
        let workspace = try await testBed.workspaceWithRunningPlugins([("suggesting-plugin", Self.suggestingPluginSource)])
        let host = workspace.communityPlugins
        try await testBed.waitUntil("the plugin's suggestions are known") { host.hasEditorSuggestions }
        await workspace.open(try VaultPath("Note.md"))
        let session = try XCTUnwrap(workspace.markdownSession)

        session.text = "one"
        let firstRevision = try XCTUnwrap(host.editorDidChange(in: session))
        session.text = "two"
        let secondRevision = try XCTUnwrap(host.editorDidChange(in: session))
        XCTAssertEqual(secondRevision, firstRevision + 1)

        try await waitForLog(containing: "asked:one", in: host)
        let logWhileFirstWaits = try await suggestionLog(in: host)
        XCTAssertEqual(logWhileFirstWaits, ["asked:one"], "The second change is sent after the first one's answer.")

        _ = try await testBed.evaluate("window.releaseFirstAnswer(); return null;", in: host)
        let latestItems = await host.suggestionItems(forRevision: secondRevision)
        let staleItems = await host.suggestionItems(forRevision: firstRevision)

        XCTAssertEqual(latestItems.map(\.title), ["two!"])
        XCTAssertEqual(staleItems.map(\.title), [], "Once a newer change was sent, an older change's suggestions are dropped.")
        let finalLog = try await suggestionLog(in: host)
        XCTAssertEqual(finalLog, ["asked:one", "answered:one", "asked:two", "answered:two"])
    }

    func testANoteLongerThan512KiUTF16UnitsIsNotSentToPlugins() async throws {
        let workspace = try await testBed.workspaceWithRunningPlugins([("listening-plugin", Self.listeningPluginSource)])
        let host = workspace.communityPlugins
        try await testBed.waitUntil("the plugin's listener is known") { host.hasEditorChangeListeners }
        await workspace.open(try VaultPath("Note.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        XCTAssertEqual(CommunityPluginHost.maximumTypingNoteLength, 524_288)

        // An emoji is two UTF-16 units, so these fill the limit exactly.
        session.text = String(repeating: "😀", count: 262_144)
        let revisionBefore = host.lastTypingRevision
        _ = host.editorDidChange(in: session)
        XCTAssertEqual(host.lastTypingRevision, revisionBefore + 1, "A note of exactly the limit is sent.")
        await host.typingRequest?.answer.value

        session.text += "x"
        _ = host.editorDidChange(in: session)
        XCTAssertEqual(host.lastTypingRevision, revisionBefore + 1, "One unit more is not sent, and takes no revision.")
    }

    // MARK: Helpers

    private func suggestionLog(in host: CommunityPluginHost) async throws -> [String] {
        try await testBed.evaluate("return window.suggestionLog;", in: host) as? [String] ?? []
    }

    private func waitForLog(containing entry: String, in host: CommunityPluginHost) async throws {
        let deadline = Date.now.addingTimeInterval(10)
        while Date.now < deadline {
            if try await suggestionLog(in: host).contains(entry) { return }
            await Task.yield()
        }
        XCTFail("The plugin was never asked: \(entry).")
    }
}
