#if os(iOS)
import XCTest
import SwiftUI
import WebKit
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

/// A community plugin running in WebKit inside the app: loading, commands that change the
/// open note through its editor, `data.json`, the keychain, the vault's own web storage,
/// timers while no panel shows the plugin, and unloading when another vault opens.
@MainActor
final class CommunityPluginHostTests: XCTestCase {
    private var window: UIWindow?
    private var vaultDirectories: [URL] = []
    private var openedVaultIdentifiers: [UUID] = []
    private var workspace: WorkspaceModel?

    private static let pluginIdentifier = "graphite-host-test"

    /// A plugin with a command for each thing the tests check.
    private static let pluginSource = """
    'use strict';
    const { Plugin } = require('obsidian');
    module.exports = class HostTestPlugin extends Plugin {
        async onload() {
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
        window?.isHidden = true
        window?.rootViewController = nil
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
        editor.becomeFirstResponder()
        editor.selectedRange = NSRange(location: 7, length: 0)
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
        editor.becomeFirstResponder()
        editor.selectedRange = NSRange(location: 0, length: 0)
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
        try await waitUntil { CommunityPluginSecretStore(vaultIdentifier: vaultIdentifier).secrets()["test-token"] == "secret-value" }

        let webView = try XCTUnwrap(host.webView)
        XCTAssertEqual(webView.configuration.websiteDataStore.identifier, vaultIdentifier, "Each vault has its own web storage.")
        #if DEBUG
        XCTAssertTrue(webView.isInspectable, "Debug builds let Safari's Web Inspector show the runtime.")
        #endif
        try await run("remember", in: workspace)
        await host.restartPlugins()
        try await waitUntil(seconds: 15) { host.loadStates[Self.pluginIdentifier] == .loaded }
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
        try await waitUntil(seconds: 5) { FileManager.default.fileExists(atPath: dataFile.path) }
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

    // MARK: Helpers

    private func makeVault(notes: [String: String], pluginEnabled: Bool) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CommunityPluginHost-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        vaultDirectories.append(directory)
        for (name, text) in notes { try Data(text.utf8).write(to: directory.appendingPathComponent(name)) }
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
    private func workspaceWithRunningPlugin(notes: [String: String]) async throws -> (WorkspaceModel, URL, UIHostingController<AnyView>) {
        let vault = try makeVault(notes: notes, pluginEnabled: true)
        let workspace = WorkspaceModel()
        self.workspace = workspace
        try await workspace.openFolderAsVault(vault)
        openedVaultIdentifiers.append(try XCTUnwrap(workspace.currentVaultIdentifier))
        let controller = try host(workspace)
        let host = workspace.communityPlugins
        try await waitUntil { host.inventory.plugins.contains { plugin in plugin.id == Self.pluginIdentifier } }
        await host.setTurnedOnForVault(true)
        try await waitUntil(seconds: 15) { host.loadStates[Self.pluginIdentifier] == .loaded }
        try await waitUntil { host.commands.contains { command in command.id == Self.pluginIdentifier + ":save-data" } }
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
    private func host(_ workspace: WorkspaceModel) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }.modifier(CommunityPluginPresentation(workspace: workspace) {})))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return controller
    }

    private func visibleEditor(in controller: UIViewController, showing session: MarkdownSession) async throws -> MarkdownTextView {
        try await waitUntil { self.editors(in: controller).contains { editor in editor.text == session.text && editor.bounds.width > 0 } }
        return try XCTUnwrap(editors(in: controller).first { editor in editor.text == session.text },
                             "Editors show \(editors(in: controller).map { editor in editor.text ?? "" }); the note is \(session.text)")
    }

    private func editors(in controller: UIViewController) -> [MarkdownTextView] {
        descendants(of: controller.view, matching: MarkdownTextView.self).filter { editor in editor.window != nil }
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }

    private func waitUntil(seconds: Double = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(condition(), "The plugin host did not reach the expected state.")
    }
}
#endif
