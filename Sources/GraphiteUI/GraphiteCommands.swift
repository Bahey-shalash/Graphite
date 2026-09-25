import SwiftUI
import GraphiteCore

/// What the menu bar's commands act on: the focused window's workspace and the parts of
/// the window only its view can show.
struct WorkspaceMenuActions {
    let workspace: WorkspaceModel
    let window: WindowActions
    let showCommandPalette: () -> Void
    let save: () -> Void
}

extension FocusedValues {
    @Entry var workspaceMenuActions: WorkspaceMenuActions?
}

/// Graphite's menus, with Obsidian's keyboard shortcuts. On iPad they appear in the menu
/// bar and when ⌘ is held; the editor adds its own editing shortcuts while a note is
/// being edited.
public struct GraphiteCommands: Commands {
    @FocusedValue(\.workspaceMenuActions) private var actions

    public init() {}

    private var workspace: WorkspaceModel? { actions?.workspace.store == nil ? nil : actions?.workspace }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Group { fileCommands }.disabled(workspace == nil)
        }
        CommandGroup(replacing: .saveItem) {
            // Saving is automatic; the shortcut is for people who save out of habit.
            Button("Save") { actions?.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(workspace == nil)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { actions?.window.showSettings() }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .textEditing) {
            Button("Search in All Files") { workspace?.searchFocusRequest += 1 }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(workspace == nil)
            if workspace?.preferences.isEnabled(.templates) == true {
                Button("Insert Template…") { actions?.window.showTemplatePicker() }
                    .disabled(workspace?.markdownSession == nil)
            }
        }
        CommandGroup(before: .sidebar) {
            viewCommands
        }
        CommandMenu("Go") {
            goCommands
        }
    }

    @ViewBuilder private var fileCommands: some View {
        Button("New Note") { actions?.window.create(.note) }
            .keyboardShortcut("n", modifiers: .command)
        Button("New Notebook") { actions?.window.create(.notebook) }
        if workspace?.preferences.isEnabled(.bases) == true {
            Button("New Base") { actions?.window.create(.base) }
        }
        Button("New Tab") { workspace?.openNewTab() }
            .keyboardShortcut("t", modifiers: .command)
        Divider()
        Button("Open Quick Switcher…") { actions?.window.showQuickSwitcher() }
            .keyboardShortcut("o", modifiers: .command)
        Divider()
        Button("Close Tab") {
            guard let workspace else { return }
            Task { await workspace.closeTab(workspace.layout.activeTab.id) }
        }
        .keyboardShortcut("w", modifiers: .command)
        Button("Reopen Closed Tab") {
            guard let workspace else { return }
            Task { await workspace.reopenClosedTab() }
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])
        .disabled(workspace?.layout.closedPaths.isEmpty ?? true)
    }

    @ViewBuilder private var viewCommands: some View {
        let note = workspace?.markdownSession
        Button(note?.viewMode == .reading ? "Edit Note" : "Read Note") {
            guard let workspace else { return }
            workspace.markdownSession?.toggleReadingView(editingMode: workspace.preferences.defaultEditingMode)
        }
        .keyboardShortcut("e", modifiers: .command)
        .disabled(note == nil)
        Button(note?.viewMode == .source ? "Use Live Preview" : "Use Source Mode") {
            guard let note else { return }
            note.viewMode = note.viewMode == .source ? .livePreview : .source
        }
        .disabled(note == nil || note?.viewMode == .reading)
        Divider()
        // ⌃⌘S is iPadOS's own Show Sidebar; giving it to this item too made the menu bar report a conflict.
        Button("Show or Hide Files") { actions?.window.toggleSidebar() }
        Button("Show or Hide Links") { actions?.window.toggleLinksInspector() }
            .disabled(note == nil)
        if workspace?.preferences.isEnabled(.graph) == true {
            Button("Graph View") { workspace?.isGraphPresented = true }
                .disabled(workspace?.store == nil)
        }
        Button(workspace?.layout.isSplit == true ? "Close This Side" : "Split Right") {
            guard let workspace else { return }
            if workspace.layout.isSplit { Task { await workspace.closeGroup(workspace.layout.focusedGroupID) } } else { workspace.splitRight() }
        }
        .disabled(workspace == nil)
        Divider()
        Button("Command Palette…") { actions?.showCommandPalette() }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(workspace == nil)
        Divider()
    }

    @ViewBuilder private var goCommands: some View {
        Button("Back") { Task { await workspace?.goBack() } }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(workspace?.history.canGoBack != true)
        Button("Forward") { Task { await workspace?.goForward() } }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(workspace?.history.canGoForward != true)
        Divider()
        Button("Next Tab") { workspace?.activateNeighborTab(forward: true) }
            .keyboardShortcut(.tab, modifiers: .control)
            .disabled((workspace?.layout.focusedGroup.tabs.count ?? 0) < 2)
        Button("Previous Tab") { workspace?.activateNeighborTab(forward: false) }
            .keyboardShortcut(.tab, modifiers: [.control, .shift])
            .disabled((workspace?.layout.focusedGroup.tabs.count ?? 0) < 2)
        Menu("Go to Tab") {
            ForEach(1...8, id: \.self) { number in
                Button("Tab \(number)") { workspace?.activateTab(atPosition: number - 1) }
                    .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
            }
            Button("Last Tab") { workspace?.activateTab(atPosition: Int.max) }
                .keyboardShortcut("9", modifiers: .command)
        }
        .disabled(workspace == nil)
        if workspace?.preferences.isEnabled(.dailyNotes) == true {
            Divider()
            Button("Today's Daily Note") { Task { await workspace?.openDailyNote() } }
            Button("Previous Daily Note") { Task { await workspace?.openAdjacentDailyNote(forward: false) } }
            Button("Next Daily Note") { Task { await workspace?.openAdjacentDailyNote(forward: true) } }
            Divider()
        }
        Button("Focus the Other Side") {
            guard let workspace, let other = workspace.layout.otherGroup(than: workspace.layout.focusedGroupID) else { return }
            workspace.focusGroup(other.id)
        }
        .disabled(workspace?.layout.isSplit != true)
    }
}
