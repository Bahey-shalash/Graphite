import Foundation
import GraphiteCore

/// One command's row on the Keyboard Shortcuts page.
struct KeyboardShortcutRow: Identifiable, Equatable {
    /// The command's identifier.
    let id: String
    let title: String
    let combinations: [KeyCombination]
    /// Whether the vault changed the command's shortcuts, so Reset can give back the defaults.
    let isChanged: Bool
    /// The titles of the other commands that use one of its shortcuts.
    let sharedWithTitles: [String]
    /// What the system does with its shortcuts, for those the system gives a meaning.
    let systemShortcuts: [SystemKeyboardShortcut]
    /// On the Mac, the shortcut System Settings gives its menu item in place of the vault's;
    /// `.some(nil)` when System Settings takes the menu item's shortcut away.
    let systemSettingsOverride: KeyCombination??
}

/// A group of rows: one of Graphite's groups, or one community plugin's commands.
struct KeyboardShortcutSection: Identifiable, Equatable {
    let id: String
    let title: String
    let rows: [KeyboardShortcutRow]
}

/// The Keyboard Shortcuts page's sections, built when the page shows them from the vault's
/// table; never kept.
struct KeyboardShortcutsPageContent {
    let table: KeyboardShortcutTable
    let platform: ShortcutPlatform
    let pluginCommands: [CommunityPluginCommand]
    /// A plugin's name by its identifier.
    let pluginName: (String) -> String?
    let isCorePluginEnabled: (CorePlugin) -> Bool
    /// Shortcuts set for menu items in the Mac's System Settings, by menu title.
    let systemSettingsShortcuts: [String: KeyCombination?]

    /// The sections whose rows match `query`, by title or by shortcut (symbols or words).
    func sections(matching query: String) -> [KeyboardShortcutSection] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        return allSections().compactMap { section in
            let rows = trimmedQuery.isEmpty ? section.rows : section.rows.filter { row in Self.row(row, matches: trimmedQuery) }
            return rows.isEmpty ? nil : KeyboardShortcutSection(id: section.id, title: section.title, rows: rows)
        }
    }

    static func row(_ row: KeyboardShortcutRow, matches query: String) -> Bool {
        if row.title.localizedStandardContains(query) { return true }
        let compactQuery = query.replacingOccurrences(of: " ", with: "")
        return row.combinations.contains { combination in
            combination.symbols.localizedCaseInsensitiveContains(compactQuery) || combination.spokenName.localizedStandardContains(query)
        }
    }

    private func allSections() -> [KeyboardShortcutSection] {
        let systemShortcuts = SystemKeyboardShortcuts(platform: platform)
        let titles = commandTitles()
        let builtInCommands = GraphiteCommand.available(on: platform).filter { command in command.corePlugin.map(isCorePluginEnabled) ?? true }
        var sections = ShortcutCommandGroup.allCases.compactMap { group -> KeyboardShortcutSection? in
            let rows = builtInCommands.filter { command in command.group == group }.map { command in
                makeRow(identifier: command.identifier, title: command.title, menuTitles: command.macMenuTitles, titles: titles,
                        systemShortcuts: systemShortcuts)
            }
            return rows.isEmpty ? nil : KeyboardShortcutSection(id: "group:" + group.title, title: group.title, rows: rows)
        }
        let commandsByPlugin = Dictionary(grouping: pluginCommands) { command in command.pluginIdentifier ?? "" }
        for pluginIdentifier in commandsByPlugin.keys.sorted() {
            let rows = (commandsByPlugin[pluginIdentifier] ?? []).map { command in
                makeRow(identifier: command.id, title: command.name, menuTitles: [], titles: titles, systemShortcuts: systemShortcuts)
            }
            sections.append(KeyboardShortcutSection(id: "plugin:" + pluginIdentifier, title: pluginName(pluginIdentifier) ?? pluginIdentifier, rows: rows))
        }
        return sections
    }

    private func commandTitles() -> [String: String] {
        var titles = Dictionary(GraphiteCommand.allCases.map { command in (command.identifier, command.title) }, uniquingKeysWith: { first, _ in first })
        for command in pluginCommands where titles[command.id] == nil { titles[command.id] = command.name }
        return titles
    }

    private func makeRow(identifier: String, title: String, menuTitles: [String], titles: [String: String],
                         systemShortcuts: SystemKeyboardShortcuts) -> KeyboardShortcutRow {
        let combinations = table.combinations(for: identifier)
        let override = platform == .macOS ? menuTitles.lazy.compactMap { menuTitle in systemSettingsShortcuts[menuTitle] }.first : nil
        return KeyboardShortcutRow(
            id: identifier, title: title, combinations: combinations, isChanged: table.isChanged(identifier),
            sharedWithTitles: table.commandIdentifiersSharingShortcuts(with: identifier).map { other in titles[other] ?? other },
            systemShortcuts: combinations.compactMap(systemShortcuts.shortcut(matching:)),
            systemSettingsOverride: override)
    }
}

extension SystemKeyboardShortcut.Purpose {
    /// What the system does with the shortcut, after "used by the system to" or "other apps
    /// use it to".
    var action: String {
        switch self {
        case .switchApplications: "switch apps"
        case .switchApplicationsBackwards: "switch apps backwards"
        case .spotlight: "open Spotlight"
        case .finderSearch: "search in a Finder window"
        case .previousInputSource: "switch to the previous input source"
        case .nextInputSource: "switch to the next input source"
        case .screenshot: "take a screenshot"
        case .screenshotOfPart: "take a screenshot of part of the screen"
        case .screenshotOptions: "show the screenshot options"
        case .lockScreen: "lock the screen"
        case .showOrHideDock: "show or hide the Dock"
        case .forceQuit: "force apps to quit"
        case .missionControl: "open Mission Control"
        case .applicationWindows: "show the app’s windows"
        case .previousSpace: "move to the space on the left"
        case .nextSpace: "move to the space on the right"
        case .homeScreen: "go to the Home Screen"
        case .quit: "quit"
        case .hide: "hide the app"
        case .hideOthers: "hide other apps"
        case .minimize: "minimize the window"
        case .cycleWindows: "move between windows"
        case .copy: "copy"
        case .paste: "paste"
        case .cut: "cut"
        case .undo: "undo"
        case .redo: "redo"
        case .selectAll: "select all"
        case .settings: "open Settings"
        }
    }
}

extension SystemKeyboardShortcut {
    /// The note a row shows for the shortcut.
    var note: String {
        switch kind {
        case .reserved: "\(combination.symbols) is used by the system to \(purpose.action), so it never reaches Graphite."
        case .standard: "Other apps use \(combination.symbols) to \(purpose.action)."
        }
    }
}
