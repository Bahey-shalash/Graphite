#if os(macOS)
import SwiftUI

/// The Mac's scenes: one main window, and Settings in a window of its own, opened with ⌘,
/// from the app menu as on every Mac. Both act on the same workspace, so a setting changed
/// there reaches the open vault at once.
public struct GraphiteMacScenes: Scene {
    @State private var workspace: WorkspaceModel

    public init() {
        _workspace = State(initialValue: WorkspaceModel())
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
#endif
