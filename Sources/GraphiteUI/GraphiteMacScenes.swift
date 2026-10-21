#if os(macOS)
import SwiftUI
import AppKit
import GraphiteCore

/// The Mac's scenes: one main window, and Settings in a window of its own, opened with ⌘,
/// from the app menu as on every Mac. Both act on the same workspace, so a setting changed
/// there reaches the open vault at once.
public struct GraphiteMacScenes: Scene {
    @State private var workspace: WorkspaceModel
    private let launchMode: LaunchMode

    public init(processServices: ProcessServices, launchMode: LaunchMode) {
        let workspace = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        _workspace = State(initialValue: workspace)
        self.launchMode = launchMode
        GraphiteApplicationDelegate.workspaceToSave = workspace
    }

    /// For checks outside the app: the scenes of a workspace made elsewhere.
    init(workspace: WorkspaceModel) {
        _workspace = State(initialValue: workspace)
        launchMode = .normal
    }

    public var body: some Scene {
        // A single window. Each window builds its own workspace, which reopens the last
        // vault with its own index on the same cache file, recorder and autosave; two of
        // them would fail each other's index writes ("database is locked") and delete
        // each other's rows on rescan. A macOS WindowGroup also opens more windows from
        // the window tab bar even though the New Window menu item is replaced.
        Window("Graphite", id: GraphiteMacScenes.mainWindowIdentifier) { GraphiteRootView(reopeningLastVaultIn: workspace, launchMode: launchMode) }
            .defaultSize(width: 1200, height: 820)
            .commands {
                GraphiteCommands()
                GuideCommands()
            }
        // The Guide in a window of its own, beside the notes it explains.
        Window("Graphite Guide", id: GraphiteMacScenes.guideWindowIdentifier) {
            GuideView(showsDoneButton: false)
                .environment(\.accent, workspace.preferences.accentColor)
                .preferredColorScheme(workspace.preferences.appearanceMode.colorScheme)
        }
        .defaultSize(width: 1000, height: 720)
        .defaultPosition(.center)
        Settings {
            SettingsView(workspace: workspace) { workspace.isVaultManagerPresented = true }
                .defaultAppStorage(workspace.deviceDefaults)
                .environment(workspace.processServices.addOns)
                .tint(workspace.preferences.accentColor)
                .environment(\.accent, workspace.preferences.accentColor)
                .preferredColorScheme(workspace.preferences.appearanceMode.colorScheme)
        }
    }

    static let mainWindowIdentifier = "main"
    static let guideWindowIdentifier = "guide"
}

/// Help › Graphite Guide opens the Guide's window.
private struct GuideCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Graphite Guide") { openWindow(id: GraphiteMacScenes.guideWindowIdentifier) }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}

/// Saves what is open before Graphite quits. A note saves once typing has paused for most
/// of a second, so ⌘Q right after typing lost the last words: the window's teardown
/// cancelled the save that was waiting.
public final class GraphiteApplicationDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var workspaceToSave: WorkspaceModel?
    /// How long quitting waits for the saves. A save still running then keeps running and
    /// Graphite stays open, so what was typed is not lost to a file another app holds.
    private static let saveDeadline = Duration.seconds(5)

    @MainActor public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let workspace = Self.workspaceToSave else { return .terminateNow }
        let reply = TerminationReply(application: sender, workspace: workspace)
        Task { @MainActor in
            do {
                try await workspace.saveOpenDocuments()
                reply.finish(with: .succeeded)
            } catch { reply.finish(with: .failed(error)) }
        }
        reply.deadline = Task { @MainActor in
            do { try await Task.sleep(for: Self.saveDeadline) } catch { return }
            reply.finish(with: .timedOut)
        }
        return .terminateLater
    }

    /// Answers the application once, whichever of the saves and the deadline ends first.
    /// The application quits only when every save succeeded; otherwise it stays open and
    /// the workspace shows why.
    @MainActor private final class TerminationReply {
        private let application: NSApplication
        private let workspace: WorkspaceModel
        private var hasReplied = false
        var deadline: Task<Void, Never>?

        init(application: NSApplication, workspace: WorkspaceModel) {
            self.application = application
            self.workspace = workspace
        }

        func finish(with outcome: QuitSaveOutcome) {
            guard !hasReplied else { return }
            hasReplied = true
            deadline?.cancel()
            let decision = QuitSaveDecision(outcome: outcome)
            if let blockingReason = decision.blockingReason {
                workspace.errorMessage = blockingReason.presentedMessage
            }
            application.reply(toApplicationShouldTerminate: decision.allowsTermination)
        }
    }
}
#endif
