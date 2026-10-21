import Foundation

/// A command that can have keyboard shortcuts: its stable identifier (Obsidian's command
/// identifier where one matches) and the shortcuts it has until a vault changes them.
public struct ShortcutCommandDefaults: Hashable, Sendable {
    public let identifier: String
    public let defaultCombinations: [KeyCombination]

    public init(identifier: String, defaultCombinations: [KeyCombination]) {
        self.identifier = identifier
        self.defaultCombinations = defaultCombinations
    }
}

/// A change the person makes on the Keyboard Shortcuts page.
public enum HotkeyChange: Equatable, Sendable {
    /// Gives the command this shortcut in place of the ones it had; other commands that used it
    /// lose it.
    case assign(KeyCombination, commandIdentifier: String)
    /// Leaves the command without shortcuts.
    case remove(commandIdentifier: String)
    /// Gives the command its default shortcuts again.
    case reset(commandIdentifier: String)
    /// Gives every listed command its defaults again. Entries for other commands, such as
    /// Obsidian's that Graphite does not have, are kept.
    case resetAll
}

/// Why a shortcut cannot be given to a command.
public enum ShortcutRefusal: Equatable, Sendable {
    /// It holds none of ⌘, ⌃ and ⌥ and is not a function key, so it would take over typing.
    case needsModifier
    /// The system keeps it for itself; it never reaches Graphite.
    case takenBySystem(SystemKeyboardShortcut)
}

/// What the person is warned about before a shortcut is given to a command.
public enum ShortcutAssignmentWarning: Equatable, Sendable {
    /// Every app uses it for the same thing (⌘Q, ⌘C).
    case standardInEveryApplication(SystemKeyboardShortcut)
    /// Other commands use it; they lose it when the person goes on.
    case usedByCommands([String])
}

/// Whether a shortcut can be given to a command, and what the person must be told first.
public enum ShortcutAssignmentCheck: Equatable, Sendable {
    case refused(ShortcutRefusal)
    case allowed(warnings: [ShortcutAssignmentWarning])
}

/// The shortcuts in effect in one vault: each command's defaults, with the changes in the
/// vault's `hotkeys.json`. Built once per change of the file or of the commands, so a key press
/// finds its command with one lookup.
public struct KeyboardShortcutTable: Sendable {
    /// The commands, in the order given; a repeated identifier keeps its first place.
    public let commands: [ShortcutCommandDefaults]
    /// The file the table was built from.
    public let file: HotkeyFile
    private let combinationsByCommand: [String: [KeyCombination]]
    private let changedCommandIdentifiers: Set<String>
    private let commandIdentifiersByCombination: [KeyCombination: [String]]

    public init(commands: [ShortcutCommandDefaults], file: HotkeyFile) {
        var seenIdentifiers: Set<String> = []
        let uniqueCommands = commands.filter { command in seenIdentifiers.insert(command.identifier).inserted }
        var combinationsByCommand: [String: [KeyCombination]] = [:]
        var changedCommandIdentifiers: Set<String> = []
        var commandIdentifiersByCombination: [KeyCombination: [String]] = [:]
        for command in uniqueCommands {
            let assigned = file.assignedCombinations(for: command.identifier)
            if assigned != nil { changedCommandIdentifiers.insert(command.identifier) }
            let combinations = assigned ?? command.defaultCombinations
            combinationsByCommand[command.identifier] = combinations
            for combination in Set(combinations) {
                if case .unknown = combination.key { continue }
                commandIdentifiersByCombination[combination, default: []].append(command.identifier)
            }
        }
        self.commands = uniqueCommands
        self.file = file
        self.combinationsByCommand = combinationsByCommand
        self.changedCommandIdentifiers = changedCommandIdentifiers
        self.commandIdentifiersByCombination = commandIdentifiersByCombination
    }

    /// The command's shortcuts in this vault; none for a command the table does not list.
    public func combinations(for commandIdentifier: String) -> [KeyCombination] {
        combinationsByCommand[commandIdentifier] ?? []
    }

    /// Whether the vault changed the command's shortcuts from its defaults.
    public func isChanged(_ commandIdentifier: String) -> Bool {
        changedCommandIdentifiers.contains(commandIdentifier)
    }

    /// The commands that use the combination, in the table's order.
    public func commandIdentifiers(using combination: KeyCombination) -> [String] {
        commandIdentifiersByCombination[combination] ?? []
    }

    /// The other commands that use one of this command's shortcuts.
    public func commandIdentifiersSharingShortcuts(with commandIdentifier: String) -> [String] {
        let sharing = Set(combinations(for: commandIdentifier).flatMap(commandIdentifiers(using:))).subtracting([commandIdentifier])
        return commands.map(\.identifier).filter(sharing.contains)
    }

    /// Whether `combination` can be given to the command on a platform whose system keeps
    /// `systemShortcuts`, and what the person must be told first.
    public func check(_ combination: KeyCombination, for commandIdentifier: String, systemShortcuts: SystemKeyboardShortcuts) -> ShortcutAssignmentCheck {
        guard combination.isRecordable else { return .refused(.needsModifier) }
        let systemShortcut = systemShortcuts.shortcut(matching: combination)
        if let systemShortcut, systemShortcut.kind == .reserved { return .refused(.takenBySystem(systemShortcut)) }
        var warnings: [ShortcutAssignmentWarning] = []
        if let systemShortcut { warnings.append(.standardInEveryApplication(systemShortcut)) }
        let otherCommands = commandIdentifiers(using: combination).filter { identifier in identifier != commandIdentifier }
        if !otherCommands.isEmpty { warnings.append(.usedByCommands(otherCommands)) }
        return .allowed(warnings: warnings)
    }

    /// The file with `change` made on the shortcuts this table shows. Only the entries of the
    /// commands the change touches are written; a command left with its defaults has no entry.
    public func file(after change: HotkeyChange) -> HotkeyFile {
        var changedFile = file
        switch change {
        case .assign(let combination, let commandIdentifier):
            for otherIdentifier in commandIdentifiers(using: combination) where otherIdentifier != commandIdentifier {
                let remaining = combinations(for: otherIdentifier).filter { otherCombination in otherCombination != combination }
                setCombinations(remaining, for: otherIdentifier, in: &changedFile)
            }
            setCombinations([combination], for: commandIdentifier, in: &changedFile)
        case .remove(let commandIdentifier):
            setCombinations([], for: commandIdentifier, in: &changedFile)
        case .reset(let commandIdentifier):
            changedFile.assign(nil, to: commandIdentifier)
        case .resetAll:
            for command in commands { changedFile.assign(nil, to: command.identifier) }
        }
        return changedFile
    }

    private func setCombinations(_ combinations: [KeyCombination], for commandIdentifier: String, in file: inout HotkeyFile) {
        let defaults = commands.first { command in command.identifier == commandIdentifier }?.defaultCombinations ?? []
        file.assign(combinations == defaults ? nil : combinations, to: commandIdentifier)
    }
}
