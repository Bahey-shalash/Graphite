import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

private extension CommunityPluginHost {
    /// Delivers a message as WebKit would hand it over.
    func deliver(_ message: [String: Any]) async -> Any { await answer(message) }
}

/// The messages `CommunityPluginHost` and the plugin runtime exchange, as the host spells them:
/// the message handler and entry point names, the operations in each direction, what the host
/// does for each message it receives, and how a failure is reported. The Node suite
/// (`host-message-contract.test.js`) writes out the same names for the runtime's side.
@MainActor
final class CommunityPluginHostMessageContractTests: XCTestCase {
    private let testBed = CommunityPluginHostTestBed()

    override func tearDown() async throws {
        await testBed.tearDown()
    }

    private static let idlePluginSource = """
    'use strict';
    const { Plugin } = require('obsidian');
    module.exports = class IdlePlugin extends Plugin { onload() {} };
    """

    /// The operations Graphite sends to the runtime.
    private static let operationsFromGraphite = [
        "appearance.changed", "appearance.styles", "basesView.open", "basesView.update", "codeBlock.event", "codeBlock.release",
        "codeBlock.render", "command.run", "editor.chooseSuggestion", "editor.closeSuggestions", "editor.drop", "editor.paste",
        "editor.update", "file.openInView", "menu.choose", "menu.dismiss", "menu.editor", "menu.file", "notice.tap", "plugin.load",
        "plugin.unload", "plugins.layoutReady", "protocol.open", "ribbon.run", "runtime.start", "runtime.stop", "settings.show",
        "surface.closed", "vault.changes", "vault.configuration", "view.attach", "view.close", "view.live", "view.resize",
        "view.restore", "view.show", "view.unlive", "views.saveFiles", "workspace.activeDocument",
    ]

    // MARK: Names

    func testThePluginsPageHasTheMessageHandlerGraphitePluginsAndTheEntryPointGraphiteCalls() async throws {
        let workspace = try await testBed.workspaceWithRunningPlugins([("idle-plugin", Self.idlePluginSource)])
        let host = workspace.communityPlugins

        let handlerKind = try await testBed.evaluate("return typeof window.webkit.messageHandlers.graphitePlugins.postMessage;", in: host) as? String
        XCTAssertEqual(handlerKind, "function")
        let otherHandlerKind = try await testBed.evaluate("return typeof window.webkit.messageHandlers.graphiteCodeBlock;", in: host) as? String
        XCTAssertEqual(otherHandlerKind, "undefined", "The copy pages' handler is not in the plugins' page.")
        let entryPointKind = try await testBed.evaluate("return typeof GraphitePluginRuntime.receive;", in: host) as? String
        XCTAssertEqual(entryPointKind, "function")
        XCTAssertNotNil(host.webView?.configuration.urlSchemeHandler(forURLScheme: "graphite-plugins"))
    }

    func testTheCopyPagesMessageHandlerIsGraphiteCodeBlock() {
        XCTAssertEqual(CommunityPluginCodeBlockPage.messageHandlerName, "graphiteCodeBlock")
        XCTAssertTrue(CommunityPluginCodeBlockPage.script.contains("window.webkit.messageHandlers.graphiteCodeBlock"), "The page's script posts to the handler the host registered.")
    }

    func testTheOperationsGraphiteSendsAreExactlyTheOnesTheRuntimeHandlesAndAnUnknownOneIsAnUnknownOperationFailure() async throws {
        let workspace = try await testBed.workspaceWithRunningPlugins([("idle-plugin", Self.idlePluginSource)])
        let host = workspace.communityPlugins

        let handledOperations = try await testBed.evaluate("return Object.keys(GraphitePluginRuntime.messageHandlers).sort();", in: host) as? [String]
        XCTAssertEqual(handledOperations, Self.operationsFromGraphite.sorted())
        XCTAssertEqual(Self.operationsFromGraphite.count, 39)

        let answer = try await testBed.evaluate("return await GraphitePluginRuntime.receive({ operation: 'no.such.operation' });", in: host) as? [String: Any]
        let failure = answer?["failure"] as? [String: Any]
        XCTAssertEqual(failure?["kind"] as? String, "unknownOperation")
    }

    // MARK: What the host does for each message the runtime sends

    func testEachNotificationTheRuntimeSendsChangesTheStateTheInterfaceShows() async throws {
        let host = CommunityPluginHost()

        _ = await host.deliver(["operation": "commands.changed", "commands": [
            ["commandIdentifier": "p:c", "name": "P: C", "needsEditor": true, "pluginIdentifier": "p", "icon": NSNull()] as [String: Any],
        ]])
        XCTAssertEqual(host.commands, [CommunityPluginCommand(id: "p:c", name: "P: C", needsEditor: true, pluginIdentifier: "p")])

        _ = await host.deliver(["operation": "ribbon.changed", "items": [["ribbonIdentifier": "r1", "pluginIdentifier": "p", "title": "Go"]]])
        XCTAssertEqual(host.ribbonActions, [CommunityPluginRibbonAction(id: "r1", pluginIdentifier: "p", title: "Go")])

        _ = await host.deliver(["operation": "views.changed", "views": [
            ["leafIdentifier": "leaf-1", "title": "T", "viewType": "vt", "icon": "clock", "placement": "sidebar", "isLive": true, "filePath": "A.md", "state": "{}"] as [String: Any],
        ]])
        XCTAssertEqual(host.pluginViews, [CommunityPluginView(id: "leaf-1", title: "T", viewType: "vt", icon: "clock", placement: .sidebar, isLive: true, filePath: "A.md", state: "{}")])

        _ = await host.deliver(["operation": "view.reveal", "leafIdentifier": "leaf-1"])
        XCTAssertEqual(host.sidebarViewRequest?.viewIdentifier, "leaf-1", "A sidebar view is revealed in the sidebar.")

        _ = await host.deliver(["operation": "codeBlocks.changed", "languages": ["dataview"], "owners": ["dataview": "p"]])
        XCTAssertEqual(host.codeBlockLanguages, ["dataview"])
        XCTAssertEqual(host.codeBlockLanguageOwners, ["dataview": "p"])

        _ = await host.deliver(["operation": "editor.listenersChanged", "hasEditorSuggestions": true, "hasEditorChangeListeners": true, "hasPasteListeners": true, "hasDropListeners": true])
        XCTAssertTrue(host.hasEditorSuggestions && host.hasEditorChangeListeners && host.hasPasteListeners && host.hasDropListeners)

        _ = await host.deliver(["operation": "fileViews.changed", "extensions": ["sketch": "sketch-view"], "takesOverNotes": true])
        XCTAssertEqual(host.pluginFileExtensions, ["sketch": "sketch-view"])
        XCTAssertTrue(host.pluginsTakeOverNotes)

        _ = await host.deliver(["operation": "basesViews.changed", "views": [["viewType": "calendar", "name": "Calendar"]]])
        XCTAssertEqual(host.pluginBasesViews, ["calendar": "Calendar"])

        _ = await host.deliver(["operation": "menus.changed", "hasFileMenuItems": true, "hasEditorMenuItems": true])
        XCTAssertTrue(host.hasFileMenuItems && host.hasEditorMenuItems)

        _ = await host.deliver(["operation": "postProcessors.changed", "pluginIdentifiers": ["p"]])
        XCTAssertEqual(host.postProcessingPluginIdentifiers, ["p"])

        _ = await host.deliver(["operation": "styles.changed", "styles": "a { color: red; }", "bodyClasses": "x y", "bodyStyle": "--a: 1;"])
        XCTAssertEqual(host.pluginStyleSheets, "a { color: red; }")
        XCTAssertEqual(host.pluginBodyClasses, "x y")
        XCTAssertEqual(host.pluginBodyStyle, "--a: 1;")

        _ = await host.deliver(["operation": "plugin.settingTabChanged", "pluginIdentifier": "p", "hasSettingTab": true])
        XCTAssertEqual(host.pluginsWithSettings, ["p"])

        for _ in 0..<2 { _ = await host.deliver(["operation": "plugin.unsupportedFeature", "pluginIdentifier": "p", "featureName": "Feature"]) }
        XCTAssertEqual(host.unsupportedFeatures, ["p": ["Feature"]], "A feature is recorded once for a plugin.")

        _ = await host.deliver(["operation": "plugin.failure", "pluginIdentifier": "p", "message": "boom"])
        XCTAssertEqual(host.runtimeProblems, ["p": ["boom"]])

        _ = await host.deliver(["operation": "settings.open", "pluginIdentifier": "p"])
        XCTAssertEqual(host.requestedSettingsPlugin, "p")

        _ = await host.deliver(["operation": "surface.present", "title": "Panel"])
        XCTAssertEqual(host.panelTitle, "Panel")
        XCTAssertTrue(host.isPanelPresented)
        _ = await host.deliver(["operation": "surface.dismiss"])
        XCTAssertFalse(host.isPanelPresented)
    }

    func testNoticesAreShownUpdatedAndHiddenByIdentifier() async throws {
        let host = CommunityPluginHost()

        _ = await host.deliver(["operation": "notice.show", "noticeIdentifier": "n1", "message": "Hi", "actions": ["Open"], "durationMilliseconds": 0])
        XCTAssertEqual(host.notices, [CommunityPluginNotice(id: "n1", message: "Hi", pluginName: nil, actions: ["Open"])])
        _ = await host.deliver(["operation": "notice.update", "noticeIdentifier": "n1", "message": "Hello"])
        XCTAssertEqual(host.notices.map(\.message), ["Hello"])
        _ = await host.deliver(["operation": "notice.hide", "noticeIdentifier": "n1"])
        XCTAssertEqual(host.notices, [])

        _ = await host.deliver(["operation": "plugin.writeConflict", "pluginIdentifier": "p", "path": "A.md"])
        XCTAssertEqual(host.notices.count, 1, "A refused plugin write shows a notice.")
    }

    func testTheOperationsTheRuntimeAsksAnswersForAreAnsweredWithTheirNamedFields() async throws {
        let host = CommunityPluginHost()

        let rendered = await host.deliver(["operation": "markdown.render", "markdown": "# Title"]) as? [String: Any]
        XCTAssertEqual(Set((rendered ?? [:]).keys), ["html"])
        XCTAssertTrue((rendered?["html"] as? String)?.contains("<h1>Title</h1>") == true)

        let clipboard = await host.deliver(["operation": "clipboard.readText"]) as? [String: Any]
        XCTAssertEqual(Set((clipboard ?? [:]).keys), ["text"])

        let menuAnswer = Task { @MainActor () -> Int? in
            let answer = await host.deliver(["operation": "menu.show", "items": [["position": 0, "title": "A"] as [String: Any], ["position": 1, "title": "B"] as [String: Any]]]) as? [String: Any]
            return answer?["chosenPosition"] as? Int
        }
        try await waitUntil("the menu is waiting for a choice") { host.pendingMenu != nil }
        XCTAssertEqual(host.pendingMenu?.items.map(\.title), ["A", "B"])
        host.pendingMenu?.finish(choosing: 1)
        let chosenPosition = await menuAnswer.value
        XCTAssertEqual(chosenPosition, 1)
    }

    func testTheHostReportsAFailureAsAKindAndAMessageForEachWayAMessageIsRefused() async throws {
        let host = CommunityPluginHost()

        let notADictionary = await failureKind(of: "not a dictionary", from: host)
        XCTAssertEqual(notADictionary, "invalidData")
        let operationNotText = await failureKind(of: ["operation": 5], from: host)
        XCTAssertEqual(operationNotText, "invalidData")
        let withDate = await failureKind(of: ["operation": "any.operation", "when": Date.now] as [String: Any], from: host)
        XCTAssertEqual(withDate, "invalidData", "A date cannot be JSON.")
        let vaultOperationWithoutVault = await failureKind(of: ["operation": "vault.read", "path": "A.md", "encoding": "text"] as [String: Any], from: host)
        XCTAssertEqual(vaultOperationWithoutVault, "unavailable", "No vault is open.")
        let openFileWithoutPath = await failureKind(of: ["operation": "workspace.openFile"], from: host)
        XCTAssertEqual(openFileWithoutPath, "invalidPath")
        let renameWithoutPath = await failureKind(of: ["operation": "workspace.renameFile"], from: host)
        XCTAssertEqual(renameWithoutPath, "invalidPath")
        let openLinkWithoutText = await failureKind(of: ["operation": "workspace.openLinkText"], from: host)
        XCTAssertEqual(openLinkWithoutText, "invalidData")
        let applyWithoutChange = await failureKind(of: ["operation": "editor.apply"], from: host)
        XCTAssertEqual(applyWithoutChange, "invalidData")
        let requestWithoutAddress = await failureKind(of: ["operation": "network.request"], from: host)
        XCTAssertEqual(requestWithoutAddress, "invalidData")
        let requestForAFile = await failureKind(of: ["operation": "network.request", "url": "file:///etc/passwd", "method": "GET", "headers": [String: String]()] as [String: Any], from: host)
        XCTAssertEqual(requestForAFile, "network")

        let unknown = await host.deliver(["operation": "no.such.operation"]) as? [String: Any]
        XCTAssertEqual(unknown?.isEmpty, true, "An operation the host does not know is answered with an empty answer.")
    }

    func testTheOperationsThatNeedAnOpenVaultActOnTheVaultTheWorkspaceHolds() async throws {
        let workspace = try await testBed.workspaceWithRunningPlugins([("idle-plugin", Self.idlePluginSource)], files: ["Note.md": "Note.\n", "Other.md": "Other.\n"])
        let host = workspace.communityPlugins

        let stat = await host.deliver(["operation": "vault.stat", "path": "Note.md"]) as? String
        let statObject = jsonObject(fromText: stat)
        XCTAssertEqual((statObject?["stat"] as? [String: Any])?["isFolder"] as? Bool, false)
        let unknownVaultOperation = await jsonFailureKind(of: ["operation": "vault.nonsense"], from: host)
        XCTAssertEqual(unknownVaultOperation, "unknownOperation")

        _ = await host.deliver(["operation": "workspace.openFile", "path": "Other.md"])
        XCTAssertEqual(workspace.selection?.rawValue, "Other.md")
        _ = await host.deliver(["operation": "workspace.openLinkText", "linktext": "Note", "sourcePath": "Other.md"])
        XCTAssertEqual(workspace.selection?.rawValue, "Note.md")

        let session = try XCTUnwrap(workspace.markdownSession)
        let description = try XCTUnwrap(host.activeDocumentDescription(includingEditor: true) as? [String: Any])
        let snapshot = try XCTUnwrap(description["editorSnapshot"] as? [String: Any])
        let applied = await host.deliver(["operation": "editor.apply", "path": "Note.md", "snapshotIdentifier": snapshot["snapshotIdentifier"] as? String ?? "", "text": "Changed.\n", "selectionAnchor": 0, "selectionHead": 0]) as? [String: Any]
        XCTAssertEqual(session.text, "Changed.\n")
        XCTAssertEqual((applied?["snapshot"] as? [String: Any])?["text"] as? String, "Changed.\n", "The answer carries the note as it is now.")

        let staleChange = await host.deliver(["operation": "editor.apply", "path": "Note.md", "snapshotIdentifier": "a-snapshot-the-host-never-made", "text": "Lost.\n", "selectionAnchor": 0, "selectionHead": 0]) as? [String: Any]
        let staleFailure = staleChange?["failure"] as? [String: Any]
        XCTAssertEqual(staleFailure?["kind"] as? String, "conflict", "A change based on a note the host did not send is refused.")
        XCTAssertEqual((staleChange?["snapshot"] as? [String: Any])?["text"] as? String, "Changed.\n", "The refusal brings the note as it is now.")
        XCTAssertEqual(session.text, "Changed.\n")
        XCTAssertEqual(host.notices.count, 1, "The person is told the plugin's change was not applied.")
    }

    // MARK: Links

    func testAnObsidianLinkReachesThePluginsHandlerWithTheParameterNamesAsWritten() async throws {
        let source = """
        'use strict';
        const { Plugin } = require('obsidian');
        module.exports = class LinkPlugin extends Plugin {
            onload() {
                window.receivedLinks = [];
                this.registerObsidianProtocolHandler('advanced-uri', (parameters) => { window.receivedLinks.push(parameters); });
            }
        };
        """
        let workspace = try await testBed.workspaceWithRunningPlugins([("link-plugin", source)])
        let host = workspace.communityPlugins

        let isHandled = await host.openPluginLink(action: "advanced-uri", parameters: ["vault": "V", "Key": "1"])
        let isUnknownHandled = await host.openPluginLink(action: "unregistered", parameters: [:])

        XCTAssertTrue(isHandled)
        XCTAssertFalse(isUnknownHandled)
        let received = try await testBed.evaluate("return window.receivedLinks;", in: host) as? [[String: String]]
        XCTAssertEqual(received, [["action": "advanced-uri", "vault": "V", "Key": "1"]])
    }

    // MARK: Unsupported features

    func testAFeatureGraphiteLacksIsReportedOncePerPluginAndNamesThePluginWhoseCodeReachedIt() async throws {
        let source = """
        'use strict';
        const { Plugin } = require('obsidian');
        module.exports = class ReachingPlugin extends Plugin {
            onload() {
                this.addCommand({ id: 'reach', name: 'Reach', callback: () => {
                    for (let attempt = 0; attempt < 2; attempt += 1) {
                        try { this.app.workspace.duplicateLeaf(); } catch (error) { window.reachError = error.name; }
                    }
                } });
            }
        };
        """
        let workspace = try await testBed.workspaceWithRunningPlugins([("reaching-plugin", source)])
        let host = workspace.communityPlugins

        try await testBed.runCommand("reach", of: "reaching-plugin", in: workspace)
        try await waitUntil("the report arrives") { host.unsupportedFeatures["reaching-plugin"] != nil }

        XCTAssertEqual(host.unsupportedFeatures, ["reaching-plugin": ["Workspace.duplicateLeaf"]], "WebKit loads the plugin from a blob address, which names the plugin too.")
        let errorName = try await testBed.evaluate("return window.reachError;", in: host) as? String
        XCTAssertEqual(errorName, "UnsupportedFeatureError")
    }

    // MARK: Helpers

    /// The kind of the failure the host answers a message with, if it does.
    private func failureKind(of body: Any, from host: CommunityPluginHost) async -> String? {
        let answer = await host.answer(body)
        return ((answer as? [String: Any])?["failure"] as? [String: Any])?["kind"] as? String
    }

    /// The same for a vault operation, which the host answers as JSON text.
    private func jsonFailureKind(of body: [String: Any], from host: CommunityPluginHost) async -> String? {
        let answer = await host.answer(body) as? String
        return (jsonObject(fromText: answer)?["failure"] as? [String: Any])?["kind"] as? String
    }

    private func jsonObject(fromText text: String?) -> [String: Any]? {
        text.flatMap { text in try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] }
    }
}
