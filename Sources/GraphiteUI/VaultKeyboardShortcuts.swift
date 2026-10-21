import SwiftUI
import Observation
import GraphiteCore

extension ShortcutPlatform {
    /// The platform this build runs on. The iPhone shares the iPad's table; it shows no
    /// Keyboard Shortcuts page.
    static var current: ShortcutPlatform {
        #if os(macOS)
        .macOS
        #else
        .iPadOS
        #endif
    }
}

/// The open vault's keyboard shortcuts: Graphite's commands and its community plugins'
/// commands, with the changes in the vault's `.obsidian/hotkeys.json`. The tables the menu bar
/// and the editor look shortcuts up in are built once per change of the file or of the plugins'
/// commands, never per key press.
@MainActor
@Observable
final class VaultKeyboardShortcuts {
    /// The vault's `hotkeys.json` as last read. While it cannot be read, the defaults apply and
    /// nothing is written to it.
    private(set) var fileReading = VaultSettingsReading.read(HotkeyFile())
    /// The command whose new shortcut is being recorded; while there is one, the menu bar gives
    /// up its shortcuts so the keys reach the recorder.
    private(set) var recordingCommandIdentifier: String?
    let platform: ShortcutPlatform
    @ObservationIgnored private var builtInTableMemo: (file: HotkeyFile, table: KeyboardShortcutTable)?
    @ObservationIgnored private var tableMemo: (commands: [ShortcutCommandDefaults], file: HotkeyFile, table: KeyboardShortcutTable)?
    @ObservationIgnored private var editorTableMemo: (file: HotkeyFile, table: EditorKeyCommandTable)?

    init(platform: ShortcutPlatform = .current) {
        self.platform = platform
    }

    /// The shortcuts in use: the file's, or the defaults while it cannot be read.
    var file: HotkeyFile { fileReading.settings ?? HotkeyFile() }

    /// Graphite's commands on this platform and the plugins' commands, in the page's order.
    func shortcutCommands(pluginCommands: [CommunityPluginCommand]) -> [ShortcutCommandDefaults] {
        GraphiteCommand.available(on: platform).map(\.defaults)
            + pluginCommands.map { command in ShortcutCommandDefaults(identifier: command.id, defaultCombinations: command.defaultCombinations) }
    }

    /// The table for the vault's file and these plugin commands, built again only when either
    /// changed.
    func table(pluginCommands: [CommunityPluginCommand]) -> KeyboardShortcutTable {
        guard !pluginCommands.isEmpty else { return builtInTable }
        let commands = shortcutCommands(pluginCommands: pluginCommands)
        let file = file
        if let tableMemo, tableMemo.file == file, tableMemo.commands == commands { return tableMemo.table }
        let table = KeyboardShortcutTable(commands: commands, file: file)
        tableMemo = (commands, file, table)
        return table
    }

    /// The table of Graphite's own commands, which the menu bar and the editor read.
    var builtInTable: KeyboardShortcutTable {
        let file = file
        if let builtInTableMemo, builtInTableMemo.file == file { return builtInTableMemo.table }
        let table = KeyboardShortcutTable(commands: shortcutCommands(pluginCommands: []), file: file)
        builtInTableMemo = (file, table)
        return table
    }

    /// The editor's key commands in this vault.
    var editorKeyCommands: EditorKeyCommandTable {
        let file = file
        if let editorTableMemo, editorTableMemo.file == file { return editorTableMemo.table }
        let table = EditorKeyCommandTable(table: builtInTable, platform: platform)
        editorTableMemo = (file, table)
        return table
    }

    /// The shortcut a menu item of Graphite's own shows and answers; none while a shortcut is
    /// being recorded.
    func menuShortcut(for command: GraphiteCommand) -> KeyboardShortcut? {
        guard recordingCommandIdentifier == nil else { return nil }
        return builtInTable.combinations(for: command.identifier).lazy.compactMap(\.keyboardShortcut).first
    }

    /// Shows the file as the vault holds it now.
    func show(_ reading: VaultSettingsReading<HotkeyFile>) {
        if reading != fileReading { fileReading = reading }
    }

    func beginRecording(commandIdentifier: String) {
        recordingCommandIdentifier = commandIdentifier
    }

    func endRecording() {
        recordingCommandIdentifier = nil
    }

    /// Makes the change in the vault's file as it is now, then shows the result. Refused while
    /// the file cannot be read, so a damaged file is never overwritten.
    func apply(_ change: HotkeyChange, pluginCommands: [CommunityPluginCommand], in store: VaultStore) async throws {
        if let reason = fileReading.unreadableReason { throw GraphiteError.unavailable(reason) }
        let commands = shortcutCommands(pluginCommands: pluginCommands)
        let updated = try await store.updateHotkeys { file in KeyboardShortcutTable(commands: commands, file: file).file(after: change) }
        fileReading = .read(updated)
    }

    /// Reads the vault's file: its changes, or why it cannot be read.
    static func reading(from store: VaultStore) async -> VaultSettingsReading<HotkeyFile> {
        do {
            return .read(try await store.hotkeys())
        } catch let problem as HotkeyFileProblem {
            return .unreadable(reason: problem.explanation)
        } catch let problem as GraphiteError {
            return .unreadable(reason: problem.errorDescription ?? HotkeyFileProblem.unreadableExplanation)
        } catch {
            return .unreadable(reason: HotkeyFileProblem.unreadableExplanation)
        }
    }
}

extension HotkeyFileProblem {
    /// Why the file could not be read when the file system gave no reason Graphite words.
    static let unreadableExplanation = "“\(HotkeyFile.configurationPath)” could not be read."

    var explanation: String {
        switch self {
        case .notJSON: "“\(HotkeyFile.configurationPath)” is not in a form Graphite can read."
        case .notAnObject: "“\(HotkeyFile.configurationPath)” does not list shortcuts by command."
        }
    }
}

/// The note editor's shortcuts in one vault: each key combination to the editing command it
/// runs, on the platform's editor.
struct EditorKeyCommandTable: Equatable {
    struct Entry: Equatable {
        let command: GraphiteCommand
        let combination: KeyCombination
    }

    /// Every editor shortcut, in the catalogue's order.
    let entries: [Entry]
    private let commandsByCombination: [KeyCombination: GraphiteCommand]

    init(table: KeyboardShortcutTable, platform: ShortcutPlatform) {
        var entries: [Entry] = []
        var commandsByCombination: [KeyCombination: GraphiteCommand] = [:]
        for command in GraphiteCommand.available(on: platform) {
            guard case .editor = command.binding else { continue }
            for combination in table.combinations(for: command.identifier) where commandsByCombination[combination] == nil {
                entries.append(Entry(command: command, combination: combination))
                commandsByCombination[combination] = command
            }
        }
        self.entries = entries
        self.commandsByCombination = commandsByCombination
    }

    /// The defaults, for an editor with no vault's shortcuts.
    static let defaults = EditorKeyCommandTable(table: KeyboardShortcutTable(commands: GraphiteCommand.allCases.map(\.defaults), file: HotkeyFile()),
                                                platform: .current)

    func command(matching combination: KeyCombination) -> GraphiteCommand? {
        commandsByCombination[combination]
    }

    func isBound(_ command: GraphiteCommand, to combination: KeyCombination) -> Bool {
        commandsByCombination[combination] == command
    }
}

extension GraphiteCommand {
    /// The editing command a shortcut of the editor runs.
    var editorCommand: EditorCommand? {
        if case .editor(let editorCommand) = binding { return editorCommand }
        return nil
    }

    /// The commands that follow the link at the cursor, which exist only while it is on one, so
    /// Return keeps its meaning elsewhere.
    var followsLink: Bool {
        if case .followLink? = editorCommand { return true }
        return false
    }
}
