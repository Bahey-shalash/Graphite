import Foundation

/// The shortcuts a person set for menu items in System Settings › Keyboard › Keyboard
/// Shortcuts › App Shortcuts, which macOS keeps as `NSUserKeyEquivalents`: menu titles (or
/// menu paths, `\u{1B}Menu\u{1B}Item`) to key equivalents such as `@~b` (⌥⌘B). They override
/// the shortcuts of the menu items with those titles.
public enum UserKeyEquivalents {
    /// The shortcut each menu title was given; nil for a title given no shortcut, which
    /// takes the menu item's own away.
    public static func combinationsByMenuTitle(_ equivalents: [String: String]) -> [String: KeyCombination?] {
        var combinations: [String: KeyCombination?] = [:]
        for (titleOrPath, equivalent) in equivalents {
            let title = titleOrPath.split(separator: "\u{1B}").last.map(String.init) ?? titleOrPath
            guard !title.isEmpty else { continue }
            if equivalent.isEmpty {
                combinations[title] = .some(nil)
            } else if let combination = combination(fromKeyEquivalent: equivalent) {
                combinations[title] = combination
            }
        }
        return combinations
    }

    /// A key equivalent as macOS writes it: the modifier marks `@` (⌘), `~` (⌥), `^` (⌃) and
    /// `$` (⇧), then one key.
    public static func combination(fromKeyEquivalent equivalent: String) -> KeyCombination? {
        var modifiers: KeyCombination.Modifiers = []
        var remaining = Substring(equivalent)
        while remaining.count > 1, let mark = remaining.first, let modifier = modifierMarks[mark] {
            modifiers.insert(modifier)
            remaining = remaining.dropFirst()
        }
        guard remaining.count == 1, let scalar = remaining.unicodeScalars.first else { return nil }
        if let namedKey = namedKeys[scalar.value] { return KeyCombination(modifiers, .named(namedKey)) }
        if functionKeyScalars.contains(scalar.value) {
            return KeyCombination(modifiers, .function(Int(scalar.value - firstFunctionKeyScalar) + 1))
        }
        return KeyCombination(modifiers, .character(String(remaining).uppercased()))
    }

    private static let modifierMarks: [Character: KeyCombination.Modifiers] = ["@": .command, "~": .option, "^": .control, "$": .shift]

    /// AppKit's private-use characters for keys that type nothing (`NSUpArrowFunctionKey`…).
    private static let namedKeys: [UInt32: NamedKey] = [
        0xF700: .arrowUp, 0xF701: .arrowDown, 0xF702: .arrowLeft, 0xF703: .arrowRight,
        0xF729: .home, 0xF72B: .end, 0xF72C: .pageUp, 0xF72D: .pageDown, 0xF728: .delete,
        0x09: .tab, 0x0D: .enter, 0x03: .enter, 0x1B: .escape, 0x20: .space, 0x08: .backspace, 0x7F: .backspace,
    ]
    /// `NSF1FunctionKey` to `NSF20FunctionKey`.
    private static let firstFunctionKeyScalar: UInt32 = 0xF704
    private static let functionKeyScalars = firstFunctionKeyScalar...(firstFunctionKeyScalar + UInt32(ShortcutKey.functionKeyNumbers.upperBound) - 1)
}
