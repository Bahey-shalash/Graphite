import SwiftUI
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// How a shortcut is shown and how it reaches the platform's menus and key commands.
extension KeyCombination {
    /// The shortcut as menus show it, modifiers in Apple's order: ⌃⌥⇧⌘B.
    var symbols: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + key.symbol
    }

    /// The shortcut in words, for VoiceOver and for search: "Shift Command H".
    var spokenName: String {
        var words: [String] = []
        if modifiers.contains(.control) { words.append("Control") }
        if modifiers.contains(.option) { words.append("Option") }
        if modifiers.contains(.shift) { words.append("Shift") }
        if modifiers.contains(.command) { words.append("Command") }
        return (words + [key.spokenName]).joined(separator: " ")
    }

    /// The shortcut for a SwiftUI menu item or button; nil for a key SwiftUI cannot name.
    var keyboardShortcut: KeyboardShortcut? {
        guard let equivalent = key.keyEquivalent else { return nil }
        var eventModifiers: EventModifiers = []
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        return KeyboardShortcut(equivalent, modifiers: eventModifiers)
    }
}

extension ShortcutKey {
    var symbol: String {
        switch self {
        case .character(let character): character
        case .named(let namedKey): namedKey.symbol
        case .function(let number): "F\(number)"
        case .unknown(let name): name
        }
    }

    var spokenName: String {
        switch self {
        case .character(let character): character
        case .named(let namedKey): namedKey.spokenName
        case .function(let number): "F\(number)"
        case .unknown(let name): name
        }
    }

    /// SwiftUI's name for the key; letters in small letters, as a capital would add ⇧.
    var keyEquivalent: KeyEquivalent? {
        switch self {
        case .character(let character): character.lowercased().first.map { firstCharacter in KeyEquivalent(firstCharacter) }
        case .named(let namedKey): namedKey.keyEquivalent
        case .function(let number):
            // AppKit's private-use characters for F1 onwards; menus of both systems take them.
            Unicode.Scalar(Self.firstFunctionKeyScalar + UInt32(number - 1)).map { scalar in KeyEquivalent(Character(scalar)) }
        case .unknown: nil
        }
    }

    /// `NSF1FunctionKey`.
    static let firstFunctionKeyScalar: UInt32 = 0xF704
}

extension NamedKey {
    var symbol: String {
        switch self {
        case .arrowUp: "↑"
        case .arrowDown: "↓"
        case .arrowLeft: "←"
        case .arrowRight: "→"
        case .tab: "⇥"
        case .enter: "↩"
        case .escape: "⎋"
        case .space: "Space"
        case .backspace: "⌫"
        case .delete: "⌦"
        case .home: "↖"
        case .end: "↘"
        case .pageUp: "⇞"
        case .pageDown: "⇟"
        }
    }

    var spokenName: String {
        switch self {
        case .arrowUp: "Up Arrow"
        case .arrowDown: "Down Arrow"
        case .arrowLeft: "Left Arrow"
        case .arrowRight: "Right Arrow"
        case .tab: "Tab"
        case .enter: "Return"
        case .escape: "Escape"
        case .space: "Space"
        case .backspace: "Delete"
        case .delete: "Forward Delete"
        case .home: "Home"
        case .end: "End"
        case .pageUp: "Page Up"
        case .pageDown: "Page Down"
        }
    }

    var keyEquivalent: KeyEquivalent {
        switch self {
        case .arrowUp: .upArrow
        case .arrowDown: .downArrow
        case .arrowLeft: .leftArrow
        case .arrowRight: .rightArrow
        case .tab: .tab
        case .enter: .return
        case .escape: .escape
        case .space: .space
        case .backspace: .delete
        case .delete: .deleteForward
        case .home: .home
        case .end: .end
        case .pageUp: .pageUp
        case .pageDown: .pageDown
        }
    }
}

#if canImport(UIKit)
extension KeyCombination {
    /// A key press as UIKit reports it; nil for a modifier key alone. `UIKey` is read on the
    /// main actor, where UIKit delivers presses.
    @MainActor init?(key: UIKey) {
        guard let shortcutKey = ShortcutKey(keyCode: key.keyCode) ?? ShortcutKey(typedCharacter: key.charactersIgnoringModifiers) else { return nil }
        var modifiers: Modifiers = []
        if key.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if key.modifierFlags.contains(.alternate) { modifiers.insert(.option) }
        if key.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if key.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        self.init(modifiers, shortcutKey)
    }

    /// The input of a `UIKeyCommand`; nil for a key UIKit cannot name (F13 and above).
    var keyCommandInput: String? {
        switch key {
        case .character(let character): character.lowercased()
        case .named(let namedKey): namedKey.keyCommandInput
        case .function(let number): Self.functionKeyInputs.dropFirst(number - 1).first
        case .unknown: nil
        }
    }

    var keyModifierFlags: UIKeyModifierFlags {
        var flags: UIKeyModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.option) { flags.insert(.alternate) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        return flags
    }

    private static let functionKeyInputs = [
        UIKeyCommand.f1, UIKeyCommand.f2, UIKeyCommand.f3, UIKeyCommand.f4, UIKeyCommand.f5, UIKeyCommand.f6, UIKeyCommand.f7,
        UIKeyCommand.f8, UIKeyCommand.f9, UIKeyCommand.f10, UIKeyCommand.f11, UIKeyCommand.f12,
    ]
}

extension NamedKey {
    var keyCommandInput: String {
        switch self {
        case .arrowUp: UIKeyCommand.inputUpArrow
        case .arrowDown: UIKeyCommand.inputDownArrow
        case .arrowLeft: UIKeyCommand.inputLeftArrow
        case .arrowRight: UIKeyCommand.inputRightArrow
        case .tab: "\t"
        case .enter: "\r"
        case .escape: UIKeyCommand.inputEscape
        case .space: " "
        case .backspace: "\u{8}"
        case .delete: UIKeyCommand.inputDelete
        case .home: UIKeyCommand.inputHome
        case .end: UIKeyCommand.inputEnd
        case .pageUp: UIKeyCommand.inputPageUp
        case .pageDown: UIKeyCommand.inputPageDown
        }
    }
}

extension ShortcutKey {
    /// The keys that type no character, by their place on the keyboard; nil for the others,
    /// and for the modifier keys.
    init?(keyCode: UIKeyboardHIDUsage) {
        if let namedKey = Self.namedKeysByUsage[keyCode] { self = .named(namedKey); return }
        if let functionIndex = Self.functionKeyUsages.firstIndex(of: keyCode) { self = .function(functionIndex + 1); return }
        return nil
    }

    private static let namedKeysByUsage: [UIKeyboardHIDUsage: NamedKey] = [
        .keyboardUpArrow: .arrowUp, .keyboardDownArrow: .arrowDown, .keyboardLeftArrow: .arrowLeft, .keyboardRightArrow: .arrowRight,
        .keyboardTab: .tab, .keyboardReturnOrEnter: .enter, .keypadEnter: .enter, .keyboardEscape: .escape, .keyboardSpacebar: .space,
        .keyboardDeleteOrBackspace: .backspace, .keyboardDeleteForward: .delete, .keyboardHome: .home, .keyboardEnd: .end,
        .keyboardPageUp: .pageUp, .keyboardPageDown: .pageDown,
    ]

    private static let functionKeyUsages: [UIKeyboardHIDUsage] = [
        .keyboardF1, .keyboardF2, .keyboardF3, .keyboardF4, .keyboardF5, .keyboardF6, .keyboardF7, .keyboardF8, .keyboardF9, .keyboardF10,
        .keyboardF11, .keyboardF12, .keyboardF13, .keyboardF14, .keyboardF15, .keyboardF16, .keyboardF17, .keyboardF18, .keyboardF19, .keyboardF20,
    ]
}
#else
extension KeyCombination {
    /// A key press as AppKit reports it, by the key typed without modifiers; nil for a
    /// modifier key alone.
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        let shortcutKey: ShortcutKey
        if let namedKey = Self.namedKeysByCode[event.keyCode] {
            shortcutKey = .named(namedKey)
        } else if let functionIndex = Self.functionKeyCodes.firstIndex(of: event.keyCode) {
            shortcutKey = .function(functionIndex + 1)
        } else if let typed = event.characters(byApplyingModifiers: []).flatMap(ShortcutKey.init(typedCharacter:)) {
            shortcutKey = typed
        } else {
            return nil
        }
        var modifiers: Modifiers = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        self.init(modifiers, shortcutKey)
    }

    /// Virtual key codes of the keys that type no character (`kVK_…` in Carbon's Events.h).
    private static let namedKeysByCode: [UInt16: NamedKey] = [
        126: .arrowUp, 125: .arrowDown, 123: .arrowLeft, 124: .arrowRight, 48: .tab, 36: .enter, 76: .enter, 53: .escape,
        49: .space, 51: .backspace, 117: .delete, 115: .home, 119: .end, 116: .pageUp, 121: .pageDown,
    ]

    /// `kVK_F1` to `kVK_F20`.
    private static let functionKeyCodes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
}
#endif
