import Foundation

/// The system Graphite runs on, for its own keyboard shortcuts.
public enum ShortcutPlatform: Sendable {
    case macOS, iPadOS
}

/// A shortcut the system or every app gives a meaning.
public struct SystemKeyboardShortcut: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// The system takes it; it never reaches Graphite.
        case reserved
        /// Every app uses it for the same thing; Graphite may use it after a warning.
        case standard
    }

    /// What the shortcut does everywhere else.
    public enum Purpose: Hashable, Sendable, CaseIterable {
        case switchApplications, switchApplicationsBackwards, spotlight, finderSearch, previousInputSource, nextInputSource
        case screenshot, screenshotOfPart, screenshotOptions, lockScreen, showOrHideDock, forceQuit
        case missionControl, applicationWindows, previousSpace, nextSpace, homeScreen
        case quit, hide, hideOthers, minimize, cycleWindows
        case copy, paste, cut, undo, redo, selectAll, settings
    }

    public let combination: KeyCombination
    public let kind: Kind
    public let purpose: Purpose
}

/// The shortcuts a platform's system keeps or gives a meaning in every app. The table holds the
/// system's defaults, from Apple's lists "Mac keyboard shortcuts" (support.apple.com/102650)
/// and "Learn iPad keyboard shortcuts" (support.apple.com/102393), checked against macOS 27 and
/// iPadOS 27. Shortcuts with the Globe key are left out: Graphite cannot record that key.
/// A sandboxed app cannot read the changes a person made to the system's shortcuts, so a
/// system shortcut turned off in System Settings is still in the table.
public struct SystemKeyboardShortcuts: Sendable {
    public let platform: ShortcutPlatform
    public let shortcuts: [SystemKeyboardShortcut]
    private let shortcutsByCombination: [KeyCombination: SystemKeyboardShortcut]

    public init(platform: ShortcutPlatform) {
        self.platform = platform
        shortcuts = switch platform {
        case .macOS: Self.macOSShortcuts
        case .iPadOS: Self.iPadOSShortcuts
        }
        shortcutsByCombination = Dictionary(shortcuts.map { shortcut in (shortcut.combination, shortcut) }, uniquingKeysWith: { first, _ in first })
    }

    /// The system's meaning of the combination, or nil when it has none.
    public func shortcut(matching combination: KeyCombination) -> SystemKeyboardShortcut? {
        shortcutsByCombination[combination]
    }

    private static func reserved(_ modifiers: KeyCombination.Modifiers, _ key: ShortcutKey,
                                 _ purpose: SystemKeyboardShortcut.Purpose) -> SystemKeyboardShortcut {
        SystemKeyboardShortcut(combination: KeyCombination(modifiers, key), kind: .reserved, purpose: purpose)
    }

    private static func standard(_ modifiers: KeyCombination.Modifiers, _ key: ShortcutKey,
                                 _ purpose: SystemKeyboardShortcut.Purpose) -> SystemKeyboardShortcut {
        SystemKeyboardShortcut(combination: KeyCombination(modifiers, key), kind: .standard, purpose: purpose)
    }

    /// The editing shortcuts both systems give every app.
    private static let editingShortcuts: [SystemKeyboardShortcut] = [
        standard(.command, .character("C"), .copy),
        standard(.command, .character("V"), .paste),
        standard(.command, .character("X"), .cut),
        standard(.command, .character("Z"), .undo),
        standard([.command, .shift], .character("Z"), .redo),
        standard(.command, .character("A"), .selectAll),
        standard(.command, .character(","), .settings),
    ]

    private static let macOSShortcuts: [SystemKeyboardShortcut] = [
        reserved(.command, .named(.tab), .switchApplications),
        reserved([.command, .shift], .named(.tab), .switchApplicationsBackwards),
        reserved(.command, .named(.space), .spotlight),
        reserved([.command, .option], .named(.space), .finderSearch),
        reserved(.control, .named(.space), .previousInputSource),
        reserved([.control, .option], .named(.space), .nextInputSource),
        reserved([.command, .shift], .character("3"), .screenshot),
        reserved([.command, .shift], .character("4"), .screenshotOfPart),
        reserved([.command, .shift], .character("5"), .screenshotOptions),
        reserved([.command, .control], .character("Q"), .lockScreen),
        reserved([.command, .option], .character("D"), .showOrHideDock),
        reserved([.command, .option], .named(.escape), .forceQuit),
        reserved(.control, .named(.arrowUp), .missionControl),
        reserved(.control, .named(.arrowDown), .applicationWindows),
        reserved(.control, .named(.arrowLeft), .previousSpace),
        reserved(.control, .named(.arrowRight), .nextSpace),
        standard(.command, .character("Q"), .quit),
        standard(.command, .character("H"), .hide),
        standard([.command, .option], .character("H"), .hideOthers),
        standard(.command, .character("M"), .minimize),
        standard(.command, .character("`"), .cycleWindows),
    ] + editingShortcuts

    private static let iPadOSShortcuts: [SystemKeyboardShortcut] = [
        reserved(.command, .named(.tab), .switchApplications),
        reserved([.command, .shift], .named(.tab), .switchApplicationsBackwards),
        reserved(.command, .named(.space), .spotlight),
        reserved(.command, .character("H"), .homeScreen),
        reserved([.command, .shift], .character("3"), .screenshot),
        reserved([.command, .shift], .character("4"), .screenshotOfPart),
        // The app menu iPadOS's menu bar gives every app quits with it.
        standard(.command, .character("Q"), .quit),
        standard(.command, .character("M"), .minimize),
        standard(.command, .character("`"), .cycleWindows),
    ] + editingShortcuts
}
