import SwiftUI
import GraphiteCore

/// Settings › Keyboard Shortcuts, on the Mac and the iPad: Graphite's commands and the
/// community plugins' by group, each with its shortcuts, to record a new one, remove them or
/// reset them. Changes are stored in the vault's `.obsidian/hotkeys.json`, shared with Obsidian.
struct KeyboardShortcutsSettingsPage: View {
    let shortcuts: VaultKeyboardShortcuts
    let pluginCommands: [CommunityPluginCommand]
    let pluginName: (String) -> String?
    let isCorePluginEnabled: (CorePlugin) -> Bool
    /// Shortcuts set in the Mac's System Settings for menu items, by menu title.
    let systemSettingsShortcuts: [String: KeyCombination?]
    let change: (HotkeyChange) async -> Void

    @State private var query = ""
    @State private var pendingAssignment: PendingAssignment?
    @State private var refusal: Refusal?
    @State private var isConfirmingResetAll = false

    /// A shortcut that needs the person's go-ahead before it is given.
    private struct PendingAssignment {
        let combination: KeyCombination
        let commandIdentifier: String
        let warnings: [String]
    }

    private struct Refusal {
        let combination: KeyCombination
        let reason: String
    }

    private var table: KeyboardShortcutTable { shortcuts.table(pluginCommands: pluginCommands) }
    /// While the file cannot be read, nothing is changed, so it is never overwritten.
    private var canEdit: Bool { shortcuts.fileReading.settings != nil }

    var body: some View {
        let content = KeyboardShortcutsPageContent(table: table, platform: shortcuts.platform, pluginCommands: pluginCommands, pluginName: pluginName,
                                                   isCorePluginEnabled: isCorePluginEnabled, systemSettingsShortcuts: systemSettingsShortcuts)
        Form {
            if let reason = shortcuts.fileReading.unreadableReason { unreadableFileSection(reason) }
            ForEach(content.sections(matching: query)) { section in
                Section(section.title) {
                    ForEach(section.rows) { row in rowView(row) }
                }
            }
            resetAllSection
        }
        .searchable(text: $query, prompt: "Search by name or shortcut")
        .navigationTitle("Keyboard Shortcuts")
        .onDisappear { shortcuts.endRecording() }
        .confirmationDialog(pendingAssignment.map { pending in "Use \(pending.combination.symbols)?" } ?? "",
                            isPresented: Binding(get: { pendingAssignment != nil }, set: { isPresented in if !isPresented { pendingAssignment = nil } }),
                            titleVisibility: .visible, presenting: pendingAssignment) { pending in
            Button("Use \(pending.combination.symbols)") { apply(.assign(pending.combination, commandIdentifier: pending.commandIdentifier)) }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.warnings.joined(separator: " "))
        }
        .alert(refusal.map { refusal in "\(refusal.combination.symbols) can’t be used" } ?? "",
               isPresented: Binding(get: { refusal != nil }, set: { isPresented in if !isPresented { refusal = nil } }), presenting: refusal) { _ in
            Button("OK", role: .cancel) {}
        } message: { refusal in
            Text(refusal.reason)
        }
    }

    private func rowView(_ row: KeyboardShortcutRow) -> some View {
        KeyboardShortcutRowView(row: row, isRecording: shortcuts.recordingCommandIdentifier == row.id, canEdit: canEdit,
                                record: { shortcuts.beginRecording(commandIdentifier: row.id) },
                                finishRecording: { recording in finishRecording(recording, for: row.id) },
                                remove: { apply(.remove(commandIdentifier: row.id)) },
                                reset: { apply(.reset(commandIdentifier: row.id)) })
    }

    private func unreadableFileSection(_ reason: String) -> some View {
        Section {
            Label {
                Text("The default shortcuts are in use, and nothing can be changed here until the file can be read. Graphite leaves it as it is. " + reason)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }

    private var resetAllSection: some View {
        Section {
            Button("Reset All", role: .destructive) { isConfirmingResetAll = true }
                .disabled(!canEdit || !table.commands.contains { command in table.isChanged(command.identifier) })
                .confirmationDialog("Give every command its default shortcuts?", isPresented: $isConfirmingResetAll, titleVisibility: .visible) {
                    Button("Reset All", role: .destructive) { apply(.resetAll) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Shortcuts this vault sets for commands Graphite doesn’t have are kept for Obsidian.")
                }
        } footer: {
            Text(footer).formFooterAlignment()
        }
    }

    private var footer: String {
        let storage = "Shortcuts belong to this vault: only the changes are stored, in .obsidian/hotkeys.json, which Obsidian shares. "
        let system = "Shortcuts are checked against the system’s defaults; a change made to the system’s own shortcuts in System Settings is not seen here."
        guard shortcuts.platform == .macOS else { return storage + system }
        return storage + system + " A shortcut set in System Settings › Keyboard › Keyboard Shortcuts › App Shortcuts for one of "
            + "Graphite’s menu items takes the place of the vault’s and is shown on its row."
    }

    private func finishRecording(_ recording: ShortcutRecording, for commandIdentifier: String) {
        shortcuts.endRecording()
        guard case .recorded(let combination) = recording else { return }
        switch table.check(combination, for: commandIdentifier, systemShortcuts: SystemKeyboardShortcuts(platform: shortcuts.platform)) {
        case .refused(.needsModifier):
            refusal = Refusal(combination: combination, reason: "A shortcut needs ⌘, ⌃ or ⌥, or a function key, so typing is never taken over.")
        case .refused(.takenBySystem(let systemShortcut)):
            refusal = Refusal(combination: combination, reason: systemShortcut.note)
        case .allowed(let warnings) where warnings.isEmpty:
            apply(.assign(combination, commandIdentifier: commandIdentifier))
        case .allowed(let warnings):
            pendingAssignment = PendingAssignment(combination: combination, commandIdentifier: commandIdentifier, warnings: warnings.map(describe))
        }
    }

    private func describe(_ warning: ShortcutAssignmentWarning) -> String {
        switch warning {
        case .standardInEveryApplication(let systemShortcut): return systemShortcut.note
        case .usedByCommands(let identifiers):
            let titles = identifiers.map { identifier in
                GraphiteCommand(rawValue: identifier)?.title ?? pluginCommands.first { command in command.id == identifier }?.name ?? identifier
            }
            return "It is now the shortcut of “\(titles.joined(separator: "”, “"))”, which will lose it."
        }
    }

    private func apply(_ hotkeyChange: HotkeyChange) {
        Task { await change(hotkeyChange) }
    }
}

/// One command: its title, its shortcuts and what they clash with, and its buttons.
private struct KeyboardShortcutRowView: View {
    let row: KeyboardShortcutRow
    let isRecording: Bool
    let canEdit: Bool
    let record: () -> Void
    let finishRecording: (ShortcutRecording) -> Void
    let remove: () -> Void
    let reset: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                notes.font(.caption)
            }
            Spacer(minLength: 8)
            shortcutText
            buttons
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var shortcutText: some View {
        if isRecording {
            Text("Press keys…").foregroundStyle(.tint)
                .background { ShortcutRecorderView(finish: finishRecording) }
        } else if row.combinations.isEmpty {
            Text("None").foregroundStyle(.secondary)
        } else {
            Text(row.combinations.map(\.symbols).joined(separator: "  "))
                .monospaced()
                .accessibilityLabel(row.combinations.map(\.spokenName).joined(separator: ", "))
        }
    }

    @ViewBuilder private var notes: some View {
        if !row.sharedWithTitles.isEmpty {
            Label("Also the shortcut of “\(row.sharedWithTitles.joined(separator: "”, “"))”", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        ForEach(row.systemShortcuts, id: \.self) { systemShortcut in
            Label(systemShortcut.note, systemImage: systemShortcut.kind == .reserved ? "nosign" : "info.circle")
                .foregroundStyle(systemShortcut.kind == .reserved ? Color.red : Color.secondary)
        }
        if let override = row.systemSettingsOverride {
            Label(override.map { combination in "Set in System Settings: \(combination.symbols)" } ?? "Removed in System Settings", systemImage: "gearshape")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var buttons: some View {
        HStack(spacing: 4) {
            if isRecording {
                Button("Cancel", systemImage: "xmark.circle") { finishRecording(.cancelled) }
            } else {
                Button("Record Shortcut", systemImage: "record.circle", action: record)
            }
            Button("Remove Shortcut", systemImage: "minus.circle", action: remove)
                .disabled(row.combinations.isEmpty || isRecording)
            if row.isChanged {
                Button("Reset to Default", systemImage: "arrow.uturn.backward.circle", action: reset)
                    .disabled(isRecording)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .disabled(!canEdit)
        .font(.callout)
    }
}
