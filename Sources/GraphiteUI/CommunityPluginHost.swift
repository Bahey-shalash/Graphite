import Foundation
import Observation
import WebKit
import GraphiteCore
import GraphiteApple
#if canImport(UIKit)
import UIKit
#endif

/// A command a community plugin added, as Graphite's command palette lists it.
struct CommunityPluginCommand: Identifiable, Equatable {
    /// Obsidian's identifier, `<plugin id>:<command id>`.
    let id: String
    /// Obsidian's name, `<plugin name>: <command name>`.
    let name: String
    /// Editor commands need a note open for editing.
    let needsEditor: Bool
    let pluginIdentifier: String?
}

/// A plugin's ribbon button, offered in the command palette (Obsidian mobile keeps the
/// ribbon in a menu too).
struct CommunityPluginRibbonAction: Identifiable, Equatable {
    let id: String
    let pluginIdentifier: String
    let title: String
}

/// A view a plugin opened (an `ItemView` in a leaf), shown on the plugin panel.
struct CommunityPluginView: Identifiable, Equatable {
    let id: String
    let title: String
}

/// What happened when Graphite tried to run a plugin.
enum CommunityPluginLoadState: Equatable {
    case notStarted
    case loading
    case loaded
    /// Graphite did not try: the reason says why (desktop only, needs a newer API…).
    case notLoadable(String)
    case failed(String)
}

/// A plugin's `Notice`, shown by Graphite.
struct CommunityPluginNotice: Identifiable, Equatable {
    let id: String
    var message: String
    let pluginName: String?
}

/// A plugin's `Menu`, waiting for the person to choose an item.
@MainActor
final class CommunityPluginMenuRequest: Identifiable {
    struct Item: Identifiable, Equatable {
        let id: Int
        let title: String
        let isDisabled: Bool
        let isWarning: Bool
        let isChecked: Bool
    }

    let id = UUID()
    let items: [Item]
    private var continuation: CheckedContinuation<Int?, Never>?

    init(items: [Item], continuation: CheckedContinuation<Int?, Never>) {
        self.items = items
        self.continuation = continuation
    }

    /// Answers the plugin once; later answers (a dismissal after a choice) are ignored.
    func finish(choosing position: Int?) {
        continuation?.resume(returning: position)
        continuation = nil
    }
}

/// Resumes a continuation once, whichever of several tasks finishes first.
@MainActor
private final class SingleResumption {
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

/// Runs the open vault's Obsidian community plugins. The plugins run in a web view, as on
/// Obsidian mobile, inside Graphite's runtime for the `obsidian` module
/// (`Resources/CommunityPluginRuntime`). Their JavaScript runs in WebKit's content process,
/// never on the app's main thread. Everything they do to the vault goes through
/// `CommunityPluginVaultBridge`; editor changes go through the note's session, so they can
/// be undone; their interface appears on the plugin panel.
///
/// Plugins run only after the person turns community plugins on for the vault (Obsidian's
/// restricted mode), and only those enabled in `.obsidian/community-plugins.json`.
@MainActor @Observable
final class CommunityPluginHost {
    // MARK: What the interface shows

    private(set) var vaultIdentifier: UUID?
    private(set) var inventory = CommunityPluginInventory(plugins: [], unreadableFolders: [])
    private(set) var enabledList = CommunityPluginList()
    private(set) var loadStates: [String: CommunityPluginLoadState] = [:]
    /// Features each plugin reached that Graphite lacks, in the order they were reached.
    private(set) var unsupportedFeatures: [String: [String]] = [:]
    /// Errors plugins hit after loading, newest last, a few per plugin.
    private(set) var runtimeProblems: [String: [String]] = [:]
    private(set) var pluginsWithSettings: Set<String> = []
    private(set) var commands: [CommunityPluginCommand] = []
    private(set) var ribbonActions: [CommunityPluginRibbonAction] = []
    private(set) var pluginViews: [CommunityPluginView] = []
    var notices: [CommunityPluginNotice] = []
    var pendingMenu: CommunityPluginMenuRequest?
    /// The plugin panel as a sheet over the workspace.
    var isPanelPresented = false
    private(set) var panelTitle = ""
    /// The plugin whose options another part of the interface should show (`app.setting.openTabById`).
    var requestedSettingsPlugin: String?
    private(set) var isRuntimeRunning = false

    // MARK: Ownership

    @ObservationIgnored private weak var workspace: WorkspaceModel?
    /// Observed, so a panel showing it follows a restart to the new one.
    private(set) var webView: WKWebView?
    /// The place in the window where the web view waits while no panel shows it.
    @ObservationIgnored weak var parkingView: CommunityPluginPlatformView?
    @ObservationIgnored private var schemeHandler: CommunityPluginSchemeHandler?
    @ObservationIgnored private let messageReceiver = CommunityPluginMessageReceiver()
    @ObservationIgnored private var bridge: CommunityPluginVaultBridge?
    @ObservationIgnored private var monitor: VaultMonitor?
    @ObservationIgnored private var secretStore: CommunityPluginSecretStore?
    /// Waiters for the runtime page to finish loading.
    @ObservationIgnored private var pageLoadWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var isPageLoaded = false
    @ObservationIgnored private var pageLoadFailure: String?
    /// The text each editor snapshot sent to the runtime was taken from, by identifier.
    @ObservationIgnored private var editorSnapshots: [String: (path: VaultPath, text: String)] = [:]
    @ObservationIgnored private var editorSnapshotOrder: [String] = []
    @ObservationIgnored private var pendingVaultChanges: Set<String> = []
    @ObservationIgnored private var vaultChangeTask: Task<Void, Never>?
    /// Set while a settings page shows the plugin panel inline, so a plugin's modal opens there.
    @ObservationIgnored var isPanelShownInline = false
    @ObservationIgnored private var appearance = "light"

    init() {
        messageReceiver.host = self
    }

    // MARK: Consent

    private static func consentKey(for vaultIdentifier: UUID) -> String { "GraphiteCommunityPluginsTurnedOn." + vaultIdentifier.uuidString }

    /// Whether the person turned community plugins on for this vault, on this device, as
    /// Obsidian keeps "Turn on community plugins" on each device.
    private(set) var isTurnedOnForVault = false

    func setTurnedOnForVault(_ isTurnedOn: Bool) async {
        guard let vaultIdentifier, let workspace else { return }
        UserDefaults.standard.set(isTurnedOn, forKey: Self.consentKey(for: vaultIdentifier))
        isTurnedOnForVault = isTurnedOn
        if isTurnedOn { await startIfNeeded(workspace) } else { await stopRuntime() }
    }

    /// Removes what Graphite kept on the device for a vault that left the vault list.
    static func forgetVault(_ vaultIdentifier: UUID) {
        UserDefaults.standard.removeObject(forKey: consentKey(for: vaultIdentifier))
        CommunityPluginSecretStore(vaultIdentifier: vaultIdentifier).removeAllSecrets()
        Task {
            // Removing a store before anything in the app has started WebKit crashes inside
            // WebKit (its main run loop is not set up yet); asking for the default store starts it.
            _ = WKWebsiteDataStore.default()
            try? await WKWebsiteDataStore.remove(forIdentifier: vaultIdentifier)
        }
    }

    // MARK: Vault lifecycle

    /// A vault opened: its plugins are listed, and run when the person has turned them on.
    func vaultDidOpen(_ workspace: WorkspaceModel) {
        self.workspace = workspace
        vaultIdentifier = workspace.currentVaultIdentifier
        isTurnedOnForVault = vaultIdentifier.map { identifier in UserDefaults.standard.bool(forKey: Self.consentKey(for: identifier)) } ?? false
        Task {
            await reloadInventory()
            await startIfNeeded(workspace)
        }
    }

    /// The vault is being left: plugins unload first, as when Obsidian closes a vault.
    func vaultWillClose() async {
        await stopRuntime()
        inventory = CommunityPluginInventory(plugins: [], unreadableFolders: [])
        enabledList = CommunityPluginList()
        loadStates = [:]
        unsupportedFeatures = [:]
        runtimeProblems = [:]
        vaultIdentifier = nil
        isTurnedOnForVault = false
    }

    /// Reads `.obsidian/plugins` and `community-plugins.json` again.
    func reloadInventory() async {
        guard let store = workspace?.store else { return }
        do {
            inventory = try await store.installedCommunityPlugins()
            enabledList = try await store.communityPluginList()
        } catch {
            workspace?.errorMessage = "Graphite could not read this vault's community plugins. " + error.localizedDescription
        }
        for plugin in inventory.plugins where loadStates[plugin.id] == nil {
            loadStates[plugin.id] = plugin.compatibility.canLoad ? .notStarted : .notLoadable(Self.describe(plugin.compatibility))
        }
    }

    /// Starts the runtime when plugins are turned on and at least one is enabled.
    private func startIfNeeded(_ workspace: WorkspaceModel) async {
        guard isTurnedOnForVault, !isRuntimeRunning, let store = workspace.store, let root = workspace.folderAccess?.root,
              let vaultIdentifier = workspace.currentVaultIdentifier else { return }
        let enabledPlugins = inventory.plugins.filter { plugin in enabledList.isEnabled(plugin.id) }
        guard !enabledPlugins.isEmpty else { return }
        isRuntimeRunning = true
        // The runtime's own presenter: it hears Graphite's saves and other apps' changes,
        // and coordinating the plugins' writes with it keeps them from coming back as changes.
        let vaultMonitor = VaultMonitor(root: root, onChange: { [weak self] changedLocation in
            Task { @MainActor in self?.vaultItemDidChange(changedLocation, root: root) }
        })
        monitor = vaultMonitor
        let pluginStore = VaultStore(root: store.root, filePresenter: vaultMonitor)
        bridge = CommunityPluginVaultBridge(store: pluginStore) { [weak workspace] in
            await MainActor.run { workspace?.vaultSettings.deletionMethod ?? .systemTrash }
        }
        secretStore = CommunityPluginSecretStore(vaultIdentifier: vaultIdentifier)
        let handler = CommunityPluginSchemeHandler(vaultRoot: root)
        schemeHandler = handler
        let configuration = WKWebViewConfiguration()
        // Each vault has its own storage, so a plugin's `localStorage` stays with its vault.
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: vaultIdentifier)
        configuration.setURLSchemeHandler(handler, forURLScheme: CommunityPluginSchemeHandler.scheme)
        configuration.userContentController.addScriptMessageHandler(messageReceiver, contentWorld: .page, name: "graphitePlugins")
        let pluginWebView = WKWebView(frame: .zero, configuration: configuration)
        pluginWebView.navigationDelegate = messageReceiver
        #if DEBUG
        pluginWebView.isInspectable = true
        #endif
        webView = pluginWebView
        parkWebViewIfDetached()
        isPageLoaded = false
        pageLoadFailure = nil
        guard let pageAddress = CommunityPluginSchemeHandler.runtimePageAddress else {
            await stopRuntime()
            return
        }
        pluginWebView.load(URLRequest(url: pageAddress))
        await waitForPageLoad()
        // A stop or another vault while waiting leaves this start behind.
        guard webView === pluginWebView else { return }
        guard isPageLoaded else {
            workspace.errorMessage = "Graphite could not start community plugins. " + (pageLoadFailure ?? "")
            await stopRuntime()
            return
        }
        await startRuntime(in: workspace)
        for plugin in enabledPlugins {
            guard webView === pluginWebView else { return }
            await load(plugin, isEnabledByPerson: false)
        }
        guard webView === pluginWebView else { return }
        _ = try? await send(["operation": "plugins.layoutReady"])
        activeDocumentDidChange()
    }

    private func waitForPageLoad() async {
        if isPageLoaded { return }
        await withCheckedContinuation { continuation in pageLoadWaiters.append(continuation) }
    }

    func runtimePageDidLoad(in loadedWebView: WKWebView) {
        guard loadedWebView === webView else { return }
        isPageLoaded = true
        for waiter in pageLoadWaiters { waiter.resume() }
        pageLoadWaiters = []
    }

    /// The runtime's page did not load; the start that waits for it gives up.
    func runtimePageDidFail(in failedWebView: WKWebView, error: Error) {
        guard failedWebView === webView, !isPageLoaded else { return }
        pageLoadFailure = error.localizedDescription
        for waiter in pageLoadWaiters { waiter.resume() }
        pageLoadWaiters = []
    }

    /// WebKit's content process ended (memory pressure): everything starts again.
    func runtimeProcessDidEnd(in endedWebView: WKWebView) {
        guard endedWebView === webView, let workspace, isRuntimeRunning else { return }
        for plugin in inventory.plugins where loadStates[plugin.id] == .loaded { loadStates[plugin.id] = .failed("The plugin stopped when iOS ended its web content process. Graphite restarted it.") }
        Task {
            await stopRuntime()
            await startIfNeeded(workspace)
        }
    }

    private func startRuntime(in workspace: WorkspaceModel) async {
        guard let vaultIdentifier = workspace.currentVaultIdentifier else { return }
        let vault: [String: Any] = [
            "name": workspace.title,
            "identifier": vaultIdentifier.uuidString,
            "configurationDirectory": ".obsidian",
            "configuration": await applicationConfiguration(),
            "corePlugins": corePluginDescriptions(workspace),
            "secrets": secretStore?.secrets() ?? [:],
        ]
        var device: [String: Any] = ["resourcePathPrefix": CommunityPluginSchemeHandler.resourcePathPrefix, "isPhone": false]
        #if canImport(UIKit)
        device["isPhone"] = UIDevice.current.userInterfaceIdiom == .phone
        #endif
        let message: [String: Any] = [
            "operation": "runtime.start",
            "vault": vault,
            "device": device,
            "appearance": appearance,
            "compatibleApiVersion": CommunityPluginCompatibility.providedApiVersion,
            "recentFiles": workspace.recentFiles.paths.prefix(50).map(\.rawValue),
        ]
        do { _ = try await send(message) } catch { workspace.errorMessage = "Graphite could not start community plugins. " + error.localizedDescription }
    }

    /// `.obsidian/app.json` as a JSON object, for `vault.getConfig`.
    private func applicationConfiguration() async -> [String: Any] {
        guard let store = workspace?.store, let path = try? VaultPath(".obsidian/app.json"),
              (try? await store.fileExists(path)) == true,
              let snapshot = try? await store.read(path, maximumBytes: 1_048_576),
              let configuration = try? JSONSerialization.jsonObject(with: snapshot.data) as? [String: Any] else { return [:] }
        return configuration
    }

    /// Obsidian's core plugins that community plugins look up (`app.internalPlugins`), with
    /// the settings Graphite shares with Obsidian.
    private func corePluginDescriptions(_ workspace: WorkspaceModel) -> [[String: Any]] {
        let dailyNotes = workspace.dailyNoteSettings
        let templates = workspace.templateSettings
        return [
            ["identifier": "daily-notes", "isEnabled": workspace.preferences.isEnabled(.dailyNotes),
             "options": ["format": dailyNotes.format, "folder": dailyNotes.folder, "template": dailyNotes.template]],
            ["identifier": "templates", "isEnabled": workspace.preferences.isEnabled(.templates),
             "options": ["folder": templates.folder, "dateFormat": templates.dateFormat, "timeFormat": templates.timeFormat]],
            ["identifier": "bookmarks", "isEnabled": workspace.preferences.isEnabled(.bookmarks), "options": [:] as [String: Any]],
            ["identifier": "graph", "isEnabled": workspace.preferences.isEnabled(.graph), "options": [:] as [String: Any]],
            ["identifier": "canvas", "isEnabled": workspace.preferences.isEnabled(.canvas), "options": [:] as [String: Any]],
            ["identifier": "bases", "isEnabled": workspace.preferences.isEnabled(.bases), "options": [:] as [String: Any]],
            ["identifier": "file-recovery", "isEnabled": workspace.preferences.isEnabled(.fileRecovery), "options": [:] as [String: Any]],
        ]
    }

    private func stopRuntime() async {
        guard isRuntimeRunning else { return }
        // Plugins unload in their `onunload`; a plugin that never returns cannot hold up
        // leaving the vault for more than a moment.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumption = SingleResumption(continuation)
            Task { _ = try? await send(["operation": "runtime.stop"]); resumption.resume() }
            Task { try? await Task.sleep(for: .seconds(2)); resumption.resume() }
        }
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        schemeHandler = nil
        monitor?.stop()
        monitor = nil
        bridge = nil
        vaultChangeTask?.cancel()
        pendingVaultChanges = []
        editorSnapshots = [:]
        editorSnapshotOrder = []
        isPageLoaded = false
        for waiter in pageLoadWaiters { waiter.resume() }
        pageLoadWaiters = []
        commands = []
        ribbonActions = []
        pluginViews = []
        pluginsWithSettings = []
        isPanelPresented = false
        pendingMenu?.finish(choosing: nil)
        pendingMenu = nil
        isRuntimeRunning = false
        for (pluginIdentifier, state) in loadStates where state == .loaded || state == .loading { loadStates[pluginIdentifier] = .notStarted }
    }

    // MARK: Plugins

    private func load(_ plugin: InstalledCommunityPlugin, isEnabledByPerson: Bool) async {
        guard plugin.compatibility.canLoad else {
            loadStates[plugin.id] = .notLoadable(Self.describe(plugin.compatibility))
            return
        }
        guard let store = workspace?.store else { return }
        loadStates[plugin.id] = .loading
        do {
            let package = try await store.communityPluginPackage(for: plugin)
            var manifest = (try? JSONSerialization.jsonObject(with: plugin.manifest.manifestData) as? [String: Any]) ?? [:]
            manifest["dir"] = plugin.folder.rawValue
            guard isRuntimeRunning else { return }
            let answer = try await send([
                "operation": "plugin.load",
                "manifest": manifest,
                "mainSource": package.mainScript,
                "styles": package.styles,
                "isEnabledByPerson": isEnabledByPerson,
            ])
            if answer["isLoaded"] as? Bool == true {
                loadStates[plugin.id] = .loaded
            } else {
                loadStates[plugin.id] = .failed(answer["errorMessage"] as? String ?? "The plugin did not load.")
            }
        } catch {
            // A runtime stopped meanwhile does not leave failures behind for the next one.
            if isRuntimeRunning { loadStates[plugin.id] = .failed(error.localizedDescription) }
        }
    }

    /// Turns a plugin on or off in `community-plugins.json`, and loads or unloads it.
    func setEnabled(_ plugin: InstalledCommunityPlugin, _ isEnabled: Bool) async {
        guard let store = workspace?.store, let workspace else { return }
        let pluginIdentifier = plugin.id
        do {
            enabledList = try await store.updateCommunityPluginList { @Sendable list in list.setEnabled(pluginIdentifier, isEnabled) }
        } catch {
            workspace.errorMessage = error.localizedDescription
            return
        }
        if isEnabled {
            if isRuntimeRunning { await load(plugin, isEnabledByPerson: true) } else { await startIfNeeded(workspace) }
        } else {
            if isRuntimeRunning { _ = try? await send(["operation": "plugin.unload", "pluginIdentifier": plugin.id]) }
            loadStates[plugin.id] = plugin.compatibility.canLoad ? .notStarted : .notLoadable(Self.describe(plugin.compatibility))
            unsupportedFeatures[plugin.id] = nil
            runtimeProblems[plugin.id] = nil
        }
    }

    /// Loads every enabled plugin again from disk, as after an update.
    func restartPlugins() async {
        guard let workspace else { return }
        await stopRuntime()
        loadStates = [:]
        unsupportedFeatures = [:]
        runtimeProblems = [:]
        await reloadInventory()
        await startIfNeeded(workspace)
    }

    /// Moves a plugin's folder out of the vault the way the vault deletes files.
    func uninstall(_ plugin: InstalledCommunityPlugin) async {
        guard let workspace, let store = workspace.store else { return }
        if enabledList.isEnabled(plugin.id) { await setEnabled(plugin, false) }
        do {
            _ = try await store.delete(plugin.folder, method: workspace.vaultSettings.deletionMethod)
            loadStates[plugin.id] = nil
            await reloadInventory()
        } catch {
            workspace.errorMessage = error.localizedDescription
        }
    }

    static func describe(_ compatibility: CommunityPluginCompatibility) -> String {
        compatibility.blockers.map { blocker in
            switch blocker {
            case .desktopOnly: "This plugin is for Obsidian's desktop app only; it needs Node.js or Electron, which iPad and iPhone apps do not have."
            case .needsNewerApi(let required): "This plugin needs Obsidian \(required) or newer. Graphite provides the plugin API of Obsidian \(CommunityPluginCompatibility.providedApiVersion)."
            case .missingMainScript: "The plugin's folder has no main.js."
            }
        }.joined(separator: " ")
    }

    // MARK: Commands, ribbon actions and views

    /// Runs a plugin's command for the focused document, as Obsidian's palette does.
    func run(_ command: CommunityPluginCommand) async {
        guard isRuntimeRunning else { return }
        do {
            let answer = try await send(["operation": "command.run", "commandIdentifier": command.id, "activeDocument": activeDocumentDescription(includingEditor: true)])
            switch answer["outcome"] as? String {
            case "unavailable": showNotice("“\(command.name)” is not available here.", pluginIdentifier: command.pluginIdentifier)
            case "failed": showNotice("“\(command.name)” failed: \(answer["message"] as? String ?? "")", pluginIdentifier: command.pluginIdentifier)
            default: break
            }
        } catch {
            showNotice(error.localizedDescription, pluginIdentifier: command.pluginIdentifier)
        }
    }

    func run(_ ribbonAction: CommunityPluginRibbonAction) async {
        guard isRuntimeRunning else { return }
        _ = try? await send(["operation": "workspace.activeDocument", "activeDocument": activeDocumentDescription(includingEditor: true)])
        _ = try? await send(["operation": "ribbon.run", "ribbonIdentifier": ribbonAction.id])
    }

    func show(_ pluginView: CommunityPluginView) async {
        _ = try? await send(["operation": "view.show", "leafIdentifier": pluginView.id])
    }

    /// Draws a plugin's settings tab on the plugin panel. False when it has none.
    func showSettings(of pluginIdentifier: String) async -> Bool {
        guard isRuntimeRunning, let answer = try? await send(["operation": "settings.show", "pluginIdentifier": pluginIdentifier]) else { return false }
        return answer["hasSettingTab"] as? Bool == true
    }

    /// Returns the web view to the window's parking place when no panel shows it.
    func parkWebViewIfDetached() {
        CommunityPluginWebViewPlacement.parkIfDetached(webView, in: parkingView)
    }

    /// The panel was closed by the person (a swipe, Done, or leaving a settings page).
    func panelDidClose() {
        isPanelPresented = false
        guard isRuntimeRunning else { return }
        Task { _ = try? await send(["operation": "surface.closed"]) }
    }

    // MARK: The focused document

    /// Tells plugins which file is focused (`file-open`, `getActiveFile`, the active
    /// `MarkdownView`), with the note's text for its editor.
    func activeDocumentDidChange() {
        guard isRuntimeRunning else { return }
        let description = activeDocumentDescription(includingEditor: true)
        Task { _ = try? await send(["operation": "workspace.activeDocument", "activeDocument": description, "recentFiles": workspace?.recentFiles.paths.prefix(50).map(\.rawValue) ?? []]) }
    }

    func appearanceDidChange(isDark: Bool) {
        appearance = isDark ? "dark" : "light"
        guard isRuntimeRunning else { return }
        Task { _ = try? await send(["operation": "appearance.changed", "appearance": appearance]) }
    }

    private func activeDocumentDescription(includingEditor: Bool) -> Any {
        guard let workspace, let path = workspace.selection else { return NSNull() }
        guard let session = workspace.markdownSession, session.path == path else { return ["path": path.rawValue, "mode": "file"] }
        var description: [String: Any] = ["path": path.rawValue, "mode": session.viewMode == .reading ? "reading" : (session.viewMode == .source ? "source" : "livePreview")]
        if includingEditor { description["editorSnapshot"] = editorSnapshot(of: session) }
        return description
    }

    /// The note's text and selection for the runtime's `Editor`, remembered under an
    /// identifier so the change that comes back can be checked against it.
    private func editorSnapshot(of session: MarkdownSession) -> [String: Any] {
        let snapshotIdentifier = UUID().uuidString
        editorSnapshots[snapshotIdentifier] = (session.path, session.text)
        editorSnapshotOrder.append(snapshotIdentifier)
        // A few recent snapshots are enough: an asynchronous command's edit arrives soon.
        while editorSnapshotOrder.count > 8 { editorSnapshots[editorSnapshotOrder.removeFirst()] = nil }
        return [
            "path": session.path.rawValue,
            "snapshotIdentifier": snapshotIdentifier,
            "text": session.text,
            "selectionAnchor": session.selection.location,
            "selectionHead": session.selection.location + session.selection.length,
            "isReadOnly": session.viewMode == .reading,
        ]
    }

    /// A plugin changed the note in its editor: the change is applied through the note's
    /// session as one undoable edit, but only while the note still has the text the
    /// plugin saw. The answer carries the note as it is now, for the plugin's next change.
    private func applyEditorChange(_ message: [String: Any]) async -> [String: Any] {
        guard let workspace, let pathText = message["path"] as? String, let path = try? VaultPath(pathText),
              let snapshotIdentifier = message["snapshotIdentifier"] as? String, let changedText = message["text"] as? String else {
            return Self.failure("invalidData", "The plugin's change named no note.")
        }
        guard let session = workspace.openMarkdownSession(at: path) else {
            return Self.failure("conflict", "“\(path.name)” is no longer open, so the plugin's change was not applied.")
        }
        // Insertions the editor has not applied yet are waited for, so the comparison sees the
        // note as the person sees it.
        for _ in 0..<20 where session.pendingInsertion != nil { try? await Task.sleep(for: .milliseconds(10)) }
        guard let snapshot = editorSnapshots[snapshotIdentifier], snapshot.path == path, session.text == snapshot.text else {
            let pluginName = (message["pluginIdentifier"] as? String).flatMap(pluginName(of:)) ?? "A plugin"
            showNotice("\(pluginName) did not change “\(path.stem)”: the note changed while it was working.", pluginIdentifier: message["pluginIdentifier"] as? String)
            var failure = Self.failure("conflict", "The note changed while the plugin was working.")
            failure["snapshot"] = editorSnapshot(of: session)
            return failure
        }
        guard session.viewMode != .reading else { return Self.failure("readOnly", "The note is shown in reading view.") }
        let anchor = message["selectionAnchor"] as? Int ?? 0
        let head = message["selectionHead"] as? Int ?? anchor
        if let edit = CommunityPluginEditorChange.edit(from: snapshot.text, to: changedText, selectionAnchor: anchor, selectionHead: head) {
            let previousProblem = session.errorMessage
            session.apply(edit)
            // The session refuses an edit that a queued insertion overlaps, and says so.
            if let problem = session.errorMessage, problem != previousProblem {
                var failure = Self.failure("conflict", problem)
                failure["snapshot"] = editorSnapshot(of: session)
                return failure
            }
        }
        editorSnapshots[snapshotIdentifier] = (path, changedText)
        return ["snapshot": [
            "path": path.rawValue, "snapshotIdentifier": snapshotIdentifier, "text": changedText,
            "selectionAnchor": anchor, "selectionHead": head, "isReadOnly": false,
        ] as [String: Any]]
    }

    // MARK: Vault changes

    private func vaultItemDidChange(_ changedLocation: URL?, root: URL) {
        guard let changedLocation else { return }
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let components = changedLocation.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard components.count > rootComponents.count, Array(components.prefix(rootComponents.count)) == rootComponents else { return }
        pendingVaultChanges.insert(components.dropFirst(rootComponents.count).joined(separator: "/"))
        vaultChangeTask?.cancel()
        vaultChangeTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, isRuntimeRunning else { return }
            let changedPaths = pendingVaultChanges
            pendingVaultChanges = []
            let changes = changedPaths.sorted().map { path -> [String: Any] in ["path": path, "isReloadNeeded": true] }
            _ = try? await send(["operation": "vault.changes", "changes": changes])
            if changedPaths.contains(where: { path in path == ".obsidian/app.json" }) {
                _ = try? await send(["operation": "vault.configuration", "configuration": await applicationConfiguration()])
            }
        }
    }

    // MARK: Talking to the runtime

    /// Sends a message to the runtime and returns its answer; a failure it reports throws.
    @discardableResult
    private func send(_ message: [String: Any]) async throws -> [String: Any] {
        guard let webView else { throw GraphiteError.unavailable("Community plugins are not running.") }
        let answer = try await webView.callAsyncJavaScript("return await GraphitePluginRuntime.receive(message);", arguments: ["message": message], in: nil, contentWorld: .page)
        let dictionary = answer as? [String: Any] ?? [:]
        if let failure = dictionary["failure"] as? [String: Any] {
            throw GraphiteError.unavailable(failure["message"] as? String ?? "The plugin runtime failed.")
        }
        return dictionary
    }

    /// Answers a message from the runtime.
    func answer(_ body: Any) async -> Any {
        guard let message = body as? [String: Any], let operation = message["operation"] as? String else {
            return Self.failure("invalidData", "Graphite could not read the plugin runtime's message.")
        }
        // A message WebKit made from a plugin's values can hold dates or infinite numbers,
        // which JSON cannot; JSONSerialization would raise an exception nothing catches.
        guard JSONSerialization.isValidJSONObject(message) else {
            return Self.failure("invalidData", "The plugin sent a value Graphite cannot read, such as a date object.")
        }
        if CommunityPluginVaultBridge.handles(operation) {
            guard let bridge, let messageData = try? JSONSerialization.data(withJSONObject: message) else { return Self.failure("unavailable", "Community plugins are not running.") }
            let answerData = await bridge.respond(to: messageData)
            // Answered as JSON text, which the runtime parses in WebKit's process: a note or a
            // listing of the vault is not decoded on the app's main thread.
            return String(decoding: answerData, as: UTF8.self)
        }
        return await answerHostOperation(operation, message)
    }

    private func answerHostOperation(_ operation: String, _ message: [String: Any]) async -> Any {
        switch operation {
        case "editor.apply":
            return await applyEditorChange(message)
        case "network.request":
            guard let messageData = try? JSONSerialization.data(withJSONObject: message),
                  let request = try? JSONDecoder().decode(CommunityPluginNetworkRequest.self, from: messageData) else { return Self.failure("invalidData", "The plugin's request could not be read.") }
            do { return try await request.perform().jsonObject } catch { return Self.failure("network", error.localizedDescription) }
        case "markdown.render":
            do { return ["html": try CommunityPluginMarkdownRendering.html(for: message["markdown"] as? String ?? "")] }
            catch { return Self.failure("tooLarge", error.localizedDescription) }
        case "workspace.openFile":
            guard let pathText = message["path"] as? String, let path = try? VaultPath(pathText) else { return Self.failure("invalidPath", "The plugin named no file to open.") }
            await workspace?.open(path, placement: message["placement"] as? String == "newTab" ? .newTab : .currentTab)
            return [:] as [String: Any]
        case "workspace.openLinkText":
            guard let workspace, let linktext = message["linktext"] as? String else { return Self.failure("invalidData", "The plugin named no link to open.") }
            let source = (message["sourcePath"] as? String).flatMap { sourcePath in try? VaultPath(sourcePath) } ?? workspace.selection ?? .root
            await workspace.follow(linktext, from: source, placement: message["placement"] as? String == "newTab" ? .newTab : .currentTab)
            return [:] as [String: Any]
        case "workspace.renameFile":
            return await renameFileUpdatingLinks(message)
        case "menu.show":
            let chosenPosition: Any = await showMenu(message["items"] as? [[String: Any]] ?? []) ?? NSNull()
            return ["chosenPosition": chosenPosition] as [String: Any]
        default:
            receiveNotification(operation, message)
            return [:] as [String: Any]
        }
    }

    /// Obsidian's `fileManager.renameFile`: the move rewrites links as the vault's setting
    /// says, asking first when "Automatically update internal links" is off.
    private func renameFileUpdatingLinks(_ message: [String: Any]) async -> Any {
        guard let workspace, let source = (message["path"] as? String).flatMap({ path in try? VaultPath(path) }),
              let destination = (message["destinationPath"] as? String).flatMap({ path in try? VaultPath(path) }),
              let root = workspace.folderAccess?.root else { return Self.failure("invalidPath", "The plugin named no file to rename.") }
        func hasMoved() -> Bool {
            (try? destination.url(in: root)).map { location in FileManager.default.fileExists(atPath: location.path) } == true
        }
        await workspace.move(source, to: destination)
        // The person may be asked whether to update links, or the move may wait behind
        // another; the plugin waits for the answer and the move it starts.
        while workspace.pendingMove?.path == source || workspace.pendingMove?.queuedMoves.requests.contains(where: { request in request.path == source }) == true {
            try? await Task.sleep(for: .milliseconds(200))
        }
        let deadline = ContinuousClock.now + .seconds(10)
        while !hasMoved(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        return hasMoved() ? ["stat": NSNull()] as [String: Any] : Self.failure("cancelled", "“\(source.name)” was not renamed.")
    }

    private func receiveNotification(_ operation: String, _ message: [String: Any]) {
        let pluginIdentifier = message["pluginIdentifier"] as? String
        switch operation {
        case "commands.changed":
            commands = (message["commands"] as? [[String: Any]] ?? []).compactMap { command in
                guard let identifier = command["commandIdentifier"] as? String, let name = command["name"] as? String else { return nil }
                return CommunityPluginCommand(id: identifier, name: name, needsEditor: command["needsEditor"] as? Bool == true, pluginIdentifier: command["pluginIdentifier"] as? String)
            }
        case "ribbon.changed":
            ribbonActions = (message["items"] as? [[String: Any]] ?? []).compactMap { item in
                guard let identifier = item["ribbonIdentifier"] as? String, let owner = item["pluginIdentifier"] as? String else { return nil }
                return CommunityPluginRibbonAction(id: identifier, pluginIdentifier: owner, title: item["title"] as? String ?? "")
            }
        case "views.changed":
            pluginViews = (message["views"] as? [[String: Any]] ?? []).compactMap { view in
                guard let identifier = view["leafIdentifier"] as? String else { return nil }
                return CommunityPluginView(id: identifier, title: view["title"] as? String ?? "")
            }
        case "plugin.settingTabChanged":
            if let pluginIdentifier {
                if message["hasSettingTab"] as? Bool == true { pluginsWithSettings.insert(pluginIdentifier) } else { pluginsWithSettings.remove(pluginIdentifier) }
            }
        case "plugin.unsupportedFeature":
            guard let featureName = message["featureName"] as? String else { return }
            let owner = pluginIdentifier ?? "unknown"
            if !(unsupportedFeatures[owner] ?? []).contains(featureName) { unsupportedFeatures[owner, default: []].append(featureName) }
        case "plugin.failure":
            guard let problem = message["message"] as? String else { return }
            let owner = pluginIdentifier ?? "unknown"
            runtimeProblems[owner, default: []].append(problem)
            if (runtimeProblems[owner]?.count ?? 0) > 5 { runtimeProblems[owner]?.removeFirst() }
        case "plugin.writeConflict":
            let pluginName = pluginIdentifier.flatMap(pluginName(of:)) ?? "A plugin"
            showNotice("\(pluginName) did not overwrite “\(message["path"] as? String ?? "")”: the file changed after it read it.", pluginIdentifier: pluginIdentifier)
        case "notice.show":
            guard let noticeIdentifier = message["noticeIdentifier"] as? String else { return }
            let notice = CommunityPluginNotice(id: noticeIdentifier, message: message["message"] as? String ?? "", pluginName: pluginIdentifier.flatMap(pluginName(of:)))
            notices.append(notice)
            if notices.count > 4 { notices.removeFirst() }
            let duration = message["durationMilliseconds"] as? Int ?? 4500
            if duration > 0 { scheduleNoticeRemoval(noticeIdentifier, afterMilliseconds: duration) }
        case "notice.update":
            if let noticeIdentifier = message["noticeIdentifier"] as? String, let position = notices.firstIndex(where: { notice in notice.id == noticeIdentifier }) {
                notices[position].message = message["message"] as? String ?? ""
            }
        case "notice.hide":
            notices.removeAll { notice in notice.id == message["noticeIdentifier"] as? String }
        case "surface.present":
            panelTitle = message["title"] as? String ?? ""
            if !isPanelShownInline { isPanelPresented = true }
        case "surface.dismiss":
            if !isPanelShownInline { isPanelPresented = false }
        case "settings.open":
            requestedSettingsPlugin = message["pluginIdentifier"] as? String ?? ""
        case "plugins.setEnabled":
            guard let identifier = message["pluginIdentifier"] as? String, let plugin = inventory.plugins.first(where: { plugin in plugin.id == identifier }) else { return }
            let isEnabled = message["isEnabled"] as? Bool == true
            Task { await setEnabled(plugin, isEnabled) }
        case "secrets.set":
            guard let secretIdentifier = message["secretIdentifier"] as? String else { return }
            do { try secretStore?.setSecret(message["secret"] as? String ?? "", forIdentifier: secretIdentifier) }
            catch { showNotice(error.localizedDescription, pluginIdentifier: pluginIdentifier) }
        default:
            break
        }
    }

    // MARK: Notices and menus

    func showNotice(_ message: String, pluginIdentifier: String?) {
        let pluginName = pluginIdentifier.flatMap(pluginName(of:))
        // A plugin that keeps failing the same way (retried writes) shows its problem once.
        guard !notices.contains(where: { notice in notice.message == message && notice.pluginName == pluginName }) else { return }
        let noticeIdentifier = "graphite-" + UUID().uuidString
        notices.append(CommunityPluginNotice(id: noticeIdentifier, message: message, pluginName: pluginName))
        if notices.count > 4 { notices.removeFirst() }
        scheduleNoticeRemoval(noticeIdentifier, afterMilliseconds: 6000)
    }

    private func scheduleNoticeRemoval(_ noticeIdentifier: String, afterMilliseconds milliseconds: Int) {
        Task {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            notices.removeAll { notice in notice.id == noticeIdentifier }
        }
    }

    private func showMenu(_ items: [[String: Any]]) async -> Int? {
        pendingMenu?.finish(choosing: nil)
        let menuItems = items.compactMap { item -> CommunityPluginMenuRequest.Item? in
            guard let position = item["position"] as? Int else { return nil }
            return CommunityPluginMenuRequest.Item(id: position, title: item["title"] as? String ?? "", isDisabled: item["isDisabled"] as? Bool == true,
                                                   isWarning: item["isWarning"] as? Bool == true, isChecked: item["isChecked"] as? Bool == true)
        }
        guard !menuItems.isEmpty else { return nil }
        return await withCheckedContinuation { continuation in
            pendingMenu = CommunityPluginMenuRequest(items: menuItems, continuation: continuation)
        }
    }

    func pluginName(of pluginIdentifier: String) -> String? {
        inventory.plugins.first { plugin in plugin.id == pluginIdentifier }?.manifest.name
    }

    private static func failure(_ kind: String, _ message: String) -> [String: Any] {
        ["failure": ["kind": kind, "message": message]]
    }
}
