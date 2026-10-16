#if os(macOS)
import SwiftUI
import AppKit

/// The Mac's scenes: one main window, and Settings in a window of its own, opened with ⌘,
/// from the app menu as on every Mac. Both act on the same workspace, so a setting changed
/// there reaches the open vault at once.
public struct GraphiteMacScenes: Scene {
    @State private var workspace: WorkspaceModel

    public init() {
        let workspace = WorkspaceModel()
        _workspace = State(initialValue: workspace)
        GraphiteApplicationDelegate.workspaceToSave = workspace
    }

    /// For checks outside the app: the scenes of a workspace made elsewhere.
    init(workspace: WorkspaceModel) {
        _workspace = State(initialValue: workspace)
    }

    public var body: some Scene {
        // A single window. Each window builds its own workspace, which reopens the last
        // vault with its own index on the same cache file, recorder and autosave; two of
        // them would fail each other's index writes ("database is locked") and delete
        // each other's rows on rescan. A macOS WindowGroup also opens more windows from
        // the window tab bar even though the New Window menu item is replaced.
        Window("Graphite", id: GraphiteMacScenes.mainWindowIdentifier) { GraphiteRootView(reopeningLastVaultIn: workspace) }
            .defaultSize(width: 1200, height: 820)
            .commands { GraphiteCommands() }
        Settings {
            SettingsView(workspace: workspace) { workspace.isVaultManagerPresented = true }
                .tint(workspace.preferences.accentColor)
                .environment(\.accent, workspace.preferences.accentColor)
                .preferredColorScheme(workspace.preferences.appearanceMode.colorScheme)
        }
    }

    static let mainWindowIdentifier = "main"
}

/// Saves what is open before Graphite quits. A note saves once typing has paused for most
/// of a second, so ⌘Q right after typing lost the last words: the window's teardown
/// cancelled the save that was waiting.
public final class GraphiteApplicationDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var workspaceToSave: WorkspaceModel?
    /// How long quitting waits for the saves, so a file another app holds cannot keep
    /// Graphite from quitting.
    private static let saveDeadline = Duration.seconds(5)

    @MainActor public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let workspace = Self.workspaceToSave else { return .terminateNow }
        let reply = TerminationReply(application: sender)
        Task { @MainActor in
            try? await workspace.saveOpenDocuments()
            reply.allowTermination()
        }
        Task { @MainActor in
            try? await Task.sleep(for: Self.saveDeadline)
            reply.allowTermination()
        }
        return .terminateLater
    }

    /// Answers the application once, whichever of the saves and the deadline ends first.
    @MainActor private final class TerminationReply {
        private let application: NSApplication
        private var hasReplied = false

        init(application: NSApplication) { self.application = application }

        func allowTermination() {
            guard !hasReplied else { return }
            hasReplied = true
            application.reply(toApplicationShouldTerminate: true)
        }
    }
}
#endif
