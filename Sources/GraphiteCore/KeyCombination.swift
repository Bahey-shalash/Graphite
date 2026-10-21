import Foundation

/// A key and the modifier keys held with it: one keyboard shortcut, as Obsidian's
/// `.obsidian/hotkeys.json` writes it (`{"modifiers": ["Mod", "Shift"], "key": "H"}`).
/// Keys are kept by the character they type without modifiers, as Obsidian keeps them, so a
/// shortcut means the same key on every device that opens the vault.
public struct KeyCombination: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// ⌘; Obsidian's `Mod` (and `Meta`) on Apple devices.
        public static let command = Modifiers(rawValue: 1 << 0)
        /// ⌥; Obsidian's `Alt`.
        public static let option = Modifiers(rawValue: 1 << 1)
        /// ⌃; Obsidian's `Ctrl`.
        public static let control = Modifiers(rawValue: 1 << 2)
        /// ⇧; Obsidian's `Shift`.
        public static let shift = Modifiers(rawValue: 1 << 3)
    }

    public let modifiers: Modifiers
    public let key: ShortcutKey

    public init(_ modifiers: Modifiers, _ key: ShortcutKey) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Whether a person may record this combination: it holds ⌘, ⌃ or ⌥, or it is a function
    /// key, so a shortcut never takes over a key that types.
    public var isRecordable: Bool {
        if case .function = key { return true }
        return !modifiers.isDisjoint(with: [.command, .control, .option])
    }
}

/// The key of a shortcut.
public enum ShortcutKey: Hashable, Sendable {
    /// A key that types one character, kept as it types without modifiers; letters are kept
    /// in capitals, as Obsidian keeps them.
    case character(String)
    case named(NamedKey)
    /// F1 to F20.
    case function(Int)
    /// A key Obsidian wrote that Graphite does not know; kept so the file is written back as
    /// it was, never matched.
    case unknown(String)

    /// The function keys a Mac or iPad keyboard has.
    public static let functionKeyNumbers = 1...20

    /// A key by the name Obsidian writes; `Space` is read as the space Obsidian writes.
    public init(obsidianName name: String) {
        if let namedKey = NamedKey(rawValue: name) {
            self = .named(namedKey)
        } else if name == "Space" {
            self = .named(.space)
        } else if name.count == 1 {
            self = .character(name.uppercased())
        } else if name.first == "F", let number = Int(name.dropFirst()), Self.functionKeyNumbers.contains(number) {
            self = .function(number)
        } else {
            self = .unknown(name)
        }
    }

    /// A key from a character a key typed: one character, or nothing for an empty string.
    public init?(typedCharacter character: String) {
        guard character.count == 1 else { return nil }
        if character == " " { self = .named(.space) } else { self = .character(character.uppercased()) }
    }

    /// The name Obsidian writes for the key.
    public var obsidianName: String {
        switch self {
        case .character(let character): character
        case .named(let namedKey): namedKey.rawValue
        case .function(let number): "F\(number)"
        case .unknown(let name): name
        }
    }
}

/// The keys that type no character, by the names Obsidian writes for them (the web's
/// `KeyboardEvent.key`).
public enum NamedKey: String, CaseIterable, Sendable {
    case arrowUp = "ArrowUp", arrowDown = "ArrowDown", arrowLeft = "ArrowLeft", arrowRight = "ArrowRight"
    case tab = "Tab", enter = "Enter", escape = "Escape", space = " "
    case backspace = "Backspace", delete = "Delete"
    case home = "Home", end = "End", pageUp = "PageUp", pageDown = "PageDown"
}

extension KeyCombination {
    /// Obsidian's names for the modifiers, in the order Graphite writes them. `Mod` is ⌘ on
    /// Apple devices and Ctrl elsewhere, so a vault's shortcuts follow it to Windows.
    static let obsidianModifierNames: [(name: String, modifier: Modifiers)] = [
        ("Mod", .command), ("Ctrl", .control), ("Alt", .option), ("Shift", .shift)
    ]

    /// A combination from Obsidian's modifier names and key name; nil when a modifier is not
    /// one Obsidian writes. `Meta` is ⌘, as `Mod` is on Apple devices.
    public init?(obsidianModifiers modifierNames: [String], key keyName: String) {
        var modifiers: Modifiers = []
        for name in modifierNames {
            switch name {
            case "Mod", "Meta": modifiers.insert(.command)
            case "Ctrl": modifiers.insert(.control)
            case "Alt": modifiers.insert(.option)
            case "Shift": modifiers.insert(.shift)
            default: return nil
            }
        }
        guard !keyName.isEmpty else { return nil }
        self.init(modifiers, ShortcutKey(obsidianName: keyName))
    }

    /// The modifier names Obsidian writes for this combination.
    public var obsidianModifierNames: [String] {
        Self.obsidianModifierNames.filter { entry in modifiers.contains(entry.modifier) }.map(\.name)
    }

    /// The combination as one entry of a command's list in `hotkeys.json`.
    var obsidianHotkey: JSONValue {
        .object(["modifiers": .array(obsidianModifierNames.map(JSONValue.string)), "key": .string(key.obsidianName)])
    }

    /// One entry of a command's list in `hotkeys.json`; nil when it is not in Obsidian's form.
    init?(obsidianHotkey: JSONValue) {
        guard case .object(let fields) = obsidianHotkey, case .string(let keyName)? = fields["key"] else { return nil }
        let modifierNames: [String]
        switch fields["modifiers"] {
        case nil, .null?: modifierNames = []
        case .array(let values)?:
            let names = values.compactMap(\.stringValue)
            guard names.count == values.count else { return nil }
            modifierNames = names
        default: return nil
        }
        self.init(obsidianModifiers: modifierNames, key: keyName)
    }
}
