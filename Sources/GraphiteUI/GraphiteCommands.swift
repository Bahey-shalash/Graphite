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
    /// Export to PDF and Print for the focused window's note in front (`NotePDFExportPresentation`).
    @FocusedValue(\.notePDFExport) private var notePDFExport
    /// The shortcuts of the Mac's one workspace, which the menus keep while the Settings
    /// window, which has no workspace actions, is in front.
    private let keyboardShortcutsOutsideFocus: VaultKeyboardShortcuts?

    public init() {
        keyboardShortcutsOutsideFocus = nil
    }

    init(keyboardShortcutsOutsideFocus: VaultKeyboardShortcuts) {
        self.keyboardShortcutsOutsideFocus = keyboardShortcutsOutsideFocus
    }

    private var workspace: WorkspaceModel? { actions?.workspace.store == nil ? nil : actions?.workspace }

    /// The vault's shortcuts, or the defaults before a window has a workspace.
    private var keyboardShortcuts: VaultKeyboardShortcuts? { actions?.workspace.keyboardShortcuts ?? keyboardShortcutsOutsideFocus }

    /// The shortcut a menu item shows and answers, from the vault's shortcuts.
    private func shortcut(_ command: GraphiteCommand) -> KeyboardShortcut? {
        guard let keyboardShortcuts else { return Self.defaultShortcuts.combinations(for: command.identifier).lazy.compactMap(\.keyboardShortcut).first }
        return keyboardShortcuts.menuShortcut(for: command)
    }

    private static let defaultShortcuts = KeyboardShortcutTable(commands: GraphiteCommand.available(on: .current).map(\.defaults), file: HotkeyFile())

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Group { fileCommands }.disabled(workspace == nil)
        }
        CommandGroup(replacing: .saveItem) {
            // Saving is automatic; the shortcut is for people who save out of habit.
            Button("Save") { actions?.save() }
                .keyboardShortcut(shortcut(.save))
                .disabled(workspace == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("Export as PDF…") { notePDFExport?.start(nil, .save) }
                .keyboardShortcut(shortcut(.exportToPDF))
                .disabled(notePDFExport == nil || workspace?.markdownSession == nil)
            Button("Print…") { notePDFExport?.start(nil, .print) }
                .keyboardShortcut(shortcut(.printNote))
                .disabled(notePDFExport == nil || workspace?.markdownSession == nil)
        }
        #if canImport(UIKit)
        // The Mac's Settings scene puts "Settings…" and ⌘, in the app menu itself.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { actions?.window.showSettings() }
                .keyboardShortcut(shortcut(.openSettings))
        }
        #endif
        CommandGroup(after: .textEditing) {
            Button("Search in All Files") { workspace?.searchFocusRequest += 1 }
                .keyboardShortcut(shortcut(.searchAllFiles))
                .disabled(workspace == nil)
            if workspace?.preferences.isEnabled(.templates) == true {
                Button("Insert Template…") { actions?.window.showTemplatePicker() }
                    .keyboardShortcut(shortcut(.insertTemplate))
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
            .keyboardShortcut(shortcut(.newNote))
        Button("New Notebook") { actions?.window.create(.notebook) }
            .keyboardShortcut(shortcut(.newNotebook))
        if workspace?.preferences.isEnabled(.bases) == true {
            Button("New Base") { actions?.window.create(.base) }
                .keyboardShortcut(shortcut(.newBase))
        }
        if workspace?.preferences.isEnabled(.canvas) == true {
            Button("New Canvas") { actions?.window.create(.canvas) }
                .keyboardShortcut(shortcut(.newCanvas))
        }
        Button("New Tab") { workspace?.openNewTab() }
            .keyboardShortcut(shortcut(.newTab))
        Divider()
        Button("Open Quick Switcher…") { actions?.window.showQuickSwitcher() }
            .keyboardShortcut(shortcut(.quickSwitcher))
        Divider()
        Button("Close Tab") {
            guard let workspace else { return }
            Task { await workspace.closeTab(workspace.layout.activeTab.id) }
        }
        .keyboardShortcut(shortcut(.closeTab))
        Button("Reopen Closed Tab") {
            guard let workspace else { return }
            Task { await workspace.reopenClosedTab() }
        }
        .keyboardShortcut(shortcut(.reopenClosedTab))
        .disabled(workspace?.layout.closedPaths.isEmpty ?? true)
    }

    /// The core plugins' views of the vault, and of the note in front.
    @ViewBuilder private func graphAndMapCommands(note: MarkdownSession?) -> some View {
        if let workspace, workspace.preferences.isEnabled(.graph) {
            Button("Graph View") { workspace.showGraph() }
                .keyboardShortcut(shortcut(.openGraph))
                .disabled(workspace.store == nil)
            Button("Local Graph") { actions?.window.showLinksInspector(.graph, deviceDefaults: workspace.deviceDefaults) }
                .keyboardShortcut(shortcut(.openLocalGraph))
                .disabled(note == nil)
        }
        if workspace?.preferences.isEnabled(.map) == true {
            Button("Map View") { workspace?.isMapPresented = true }
                .keyboardShortcut(shortcut(.openMap))
                .disabled(workspace?.store == nil)
        }
    }

    @ViewBuilder private var viewCommands: some View {
        let note = workspace?.markdownSession
        Button(note?.viewMode == .reading ? "Edit Note" : "Read Note") {
            guard let workspace else { return }
            workspace.markdownSession?.toggleReadingView(editingMode: workspace.preferences.defaultEditingMode)
        }
        .keyboardShortcut(shortcut(.toggleReadingView))
        .disabled(note == nil)
        Button(note?.viewMode == .source ? "Use Live Preview" : "Use Source Mode") {
            guard let note else { return }
            note.viewMode = note.viewMode == .source ? .livePreview : .source
        }
        .keyboardShortcut(shortcut(.toggleSourceMode))
        .disabled(note == nil || note?.viewMode == .reading)
        Divider()
        // ⌃⌘S is iPadOS's own Show Sidebar; giving it to this item too made the menu bar report a conflict.
        Button("Show or Hide Files") { actions?.window.toggleSidebar() }
            .keyboardShortcut(shortcut(.toggleLeftSidebar))
        Button("Show or Hide Links") { actions?.window.toggleLinksInspector() }
            .keyboardShortcut(shortcut(.toggleRightSidebar))
            .disabled(note == nil)
        graphAndMapCommands(note: note)
        Button(workspace?.layout.isSplit == true ? "Close This Side" : "Split Right") {
            guard let workspace else { return }
            if workspace.layout.isSplit { Task { await workspace.closeGroup(workspace.layout.focusedGroupID) } } else { workspace.splitRight() }
        }
        .keyboardShortcut(shortcut(workspace?.layout.isSplit == true ? .closeThisSide : .splitRight))
        .disabled(workspace == nil)
        Divider()
        Button("Command Palette…") { actions?.showCommandPalette() }
            .keyboardShortcut(shortcut(.commandPalette))
            .disabled(workspace == nil)
        commandsWithShortcuts
        Divider()
        // Settings › Appearance › Font › Quick Font Size Adjustment, as in Obsidian; the size
        // is the vault's, so the commands are there only while a vault is open.
        if let workspace, workspace.adjustsNoteFontSizeQuickly {
            Button("Make Text Bigger") { workspace.adjustNoteBaseFontSize(bySteps: 1) }
                .keyboardShortcut(shortcut(.increaseFontSize))
                .disabled(workspace.noteBaseFontSize >= NoteFontSize.adjustableRange.upperBound)
            Button("Make Text Smaller") { workspace.adjustNoteBaseFontSize(bySteps: -1) }
                .keyboardShortcut(shortcut(.decreaseFontSize))
                .disabled(workspace.noteBaseFontSize <= NoteFontSize.adjustableRange.lowerBound)
            Button("Default Text Size") { workspace.resetNoteBaseFontSize() }
                .keyboardShortcut(shortcut(.resetFontSize))
                .disabled(workspace.noteBaseFontSize == NoteFontSize.defaultSize)
            Divider()
        }
    }

    @ViewBuilder private var goCommands: some View {
        Button("Back") { Task { await workspace?.goBack() } }
            .keyboardShortcut(shortcut(.goBack))
            .disabled(workspace?.history.canGoBack != true)
        Button("Forward") { Task { await workspace?.goForward() } }
            .keyboardShortcut(shortcut(.goForward))
            .disabled(workspace?.history.canGoForward != true)
        Divider()
        Button("Next Tab") { workspace?.activateNeighborTab(forward: true) }
            .keyboardShortcut(shortcut(.nextTab))
            .disabled((workspace?.layout.focusedGroup.tabs.count ?? 0) < 2)
        Button("Previous Tab") { workspace?.activateNeighborTab(forward: false) }
            .keyboardShortcut(shortcut(.previousTab))
            .disabled((workspace?.layout.focusedGroup.tabs.count ?? 0) < 2)
        Menu("Go to Tab") {
            ForEach(1...8, id: \.self) { number in
                Button("Tab \(number)") { workspace?.activateTab(atPosition: number - 1) }
                    .keyboardShortcut(GraphiteCommand.goToTab(number).flatMap(shortcut))
            }
            Button("Last Tab") { workspace?.activateTab(atPosition: Int.max) }
                .keyboardShortcut(shortcut(.goToLastTab))
        }
        .disabled(workspace == nil)
        if workspace?.preferences.isEnabled(.dailyNotes) == true {
            Divider()
            Button("Today's Daily Note") { Task { await workspace?.openDailyNote() } }
                .keyboardShortcut(shortcut(.todaysDailyNote))
            Button("Previous Daily Note") { Task { await workspace?.openAdjacentDailyNote(forward: false) } }
                .keyboardShortcut(shortcut(.previousDailyNote))
            Button("Next Daily Note") { Task { await workspace?.openAdjacentDailyNote(forward: true) } }
                .keyboardShortcut(shortcut(.nextDailyNote))
            Divider()
        }
        Button("Focus the Other Side") {
            guard let workspace, let other = workspace.layout.otherGroup(than: workspace.layout.focusedGroupID) else { return }
            workspace.focusGroup(other.id)
        }
        .keyboardShortcut(shortcut(.focusOtherSide))
        .disabled(workspace?.layout.isSplit != true)
    }

    /// The command palette's commands that have a shortcut and no menu item of their own, and
    /// the community plugins' commands with a shortcut: a menu item is what makes a shortcut
    /// work. Nothing is built while no such command has one.
    @ViewBuilder private var commandsWithShortcuts: some View {
        if let workspace, let actions, let keyboardShortcuts, keyboardShortcuts.recordingCommandIdentifier == nil {
            let table = keyboardShortcuts.table(pluginCommands: workspace.communityPlugins.commands)
            if Self.hasCommandWithShortcut(in: table, pluginCommands: workspace.communityPlugins.commands) {
                let commands = WorkspaceCommandList.commands(for: workspace, window: actions.window).filter { command in
                    command.shortcutCombination != nil && Self.needsMenuItem(command.shortcutCommandIdentifier)
                }
                if !commands.isEmpty {
                    Menu("Commands with Shortcuts") {
                        ForEach(commands) { command in
                            Button(command.title, action: command.run).keyboardShortcut(command.shortcutCombination?.keyboardShortcut)
                        }
                    }
                }
            }
        }
    }

    /// Whether a command the palette lists has a shortcut only a menu item can make work.
    private static func needsMenuItem(_ commandIdentifier: String?) -> Bool {
        guard let commandIdentifier else { return false }
        guard let command = GraphiteCommand(rawValue: commandIdentifier) else { return true }
        if case .commandsMenu = command.binding { return true }
        return false
    }

    private static func hasCommandWithShortcut(in table: KeyboardShortcutTable, pluginCommands: [CommunityPluginCommand]) -> Bool {
        pluginCommands.contains { command in !table.combinations(for: command.id).isEmpty }
            || GraphiteCommand.allCases.contains { command in needsMenuItem(command.identifier) && !table.combinations(for: command.identifier).isEmpty }
    }
}
