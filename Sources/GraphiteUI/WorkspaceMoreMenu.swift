import SwiftUI

/// The workspace's own commands, which a regular-width window keeps in the More menu rather
/// than in the toolbar, so the toolbar holds the document's controls and the title has room:
/// finding a file, the command palette, and Focus. A compact width has the first two in its
/// bottom bar; all three are in the menu bar with their keyboard shortcuts.
struct WorkspaceMoreMenuActions {
    let showQuickSwitcher: () -> Void
    let showCommandPalette: () -> Void
    let toggleFocusMode: () -> Void
}

extension EnvironmentValues {
    /// Set by the window in regular widths; nil where the bottom bar has these commands.
    @Entry var workspaceMoreMenuActions: WorkspaceMoreMenuActions? = nil
}

/// The workspace's commands as the last section of a document's More menu.
struct WorkspaceMoreMenuItems: View {
    @Environment(\.workspaceMoreMenuActions) private var actions

    var body: some View {
        if let actions {
            Section {
                Button("Quick Switcher…", systemImage: "magnifyingglass") { actions.showQuickSwitcher() }
                Button("Command Palette…", systemImage: "command") { actions.showCommandPalette() }
                Button("Focus", systemImage: "arrow.up.left.and.arrow.down.right") { actions.toggleFocusMode() }
                    .help("Hide sidebars and tabs")
            }
        }
    }
}
