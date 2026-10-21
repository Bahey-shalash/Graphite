import Foundation

/// The keys of one folder's entry in `.obsidian/graphite-folder-styles.json`.
enum FolderStyleFieldName {
    static let color = "color"
    static let symbol = "symbol"
    static let emoji = "emoji"
}

/// A folder tile's color in the library.
public enum FolderColor: Equatable, Hashable, Sendable {
    case blue, green, yellow, orange, red, pink, purple, indigo, teal, gray
    /// Any color, chosen with the system's color picker; stored as `#RRGGBB`.
    case custom(red: UInt8, green: UInt8, blue: UInt8)
    /// A color written by a newer Graphite, kept as written.
    case unknown(String)

    public static let knownColors: [FolderColor] = [.blue, .green, .yellow, .orange, .red, .pink, .purple, .indigo, .teal, .gray]
    /// The colors Finder's tags have, in the order its folder popover shows them.
    public static let tagColors: [FolderColor] = [.red, .orange, .yellow, .green, .blue, .purple, .gray]

    public init(rawValue: String) {
        if let named = Self.knownColors.first(where: { color in color.rawValue == rawValue }) {
            self = named
        } else if let components = Self.hexadecimalComponents(of: rawValue) {
            self = .custom(red: components.red, green: components.green, blue: components.blue)
        } else {
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .blue: "blue"
        case .green: "green"
        case .yellow: "yellow"
        case .orange: "orange"
        case .red: "red"
        case .pink: "pink"
        case .purple: "purple"
        case .indigo: "indigo"
        case .teal: "teal"
        case .gray: "gray"
        case .custom(let red, let green, let blue): String(format: "#%02X%02X%02X", red, green, blue)
        case .unknown(let rawValue): rawValue
        }
    }

    /// `#RRGGBB`, in either case; anything else is not a custom color.
    private static func hexadecimalComponents(of rawValue: String) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        let digits = rawValue.dropFirst()
        guard rawValue.first == "#", digits.count == 6, digits.allSatisfy(\.isHexDigit), let packed = UInt32(digits, radix: 16) else { return nil }
        return (UInt8(packed >> 16 & 0xFF), UInt8(packed >> 8 & 0xFF), UInt8(packed & 0xFF))
    }
}

/// What is drawn on a folder, as Finder draws it: an SF Symbol engraved in the folder's
/// color, or an emoji in its own colors. A folder has one or the other.
public enum FolderMark: Equatable, Hashable, Sendable {
    case symbol(String)
    case emoji(String)

    /// The first emoji of typed text, as the emoji keyboard or the character palette types
    /// it: one whole character, with its skin tone and joined parts. Nil when none is an emoji.
    public static func firstEmoji(in typedText: String) -> String? {
        typedText.first(where: isEmoji).map(String.init)
    }

    /// A character drawn as a picture: one shown as emoji by default, or a symbol made emoji
    /// by its variation selector. Digits, `#` and `*` carry the emoji property too, but only
    /// count with that selector or a keycap.
    static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        let emojiVariationSelector: Unicode.Scalar = "\u{FE0F}"
        return first.properties.isEmoji && scalars.contains(emojiVariationSelector)
    }
}

/// How one folder looks in the library: its color, and a symbol or emoji drawn on it.
/// A style with neither is a plain folder.
public struct FolderStyle: Equatable, Sendable {
    /// Nil keeps the folder's default color, the blue of Files and Finder.
    public var color: FolderColor?
    public var mark: FolderMark?
    /// Keys this build does not know, kept as they were.
    var otherFields: [String: JSONValue]

    /// What `color` is written as when there is none: older builds read it as an unknown
    /// color and draw the default blue, so they still show the folder's symbol.
    static let noColorRawValue = "none"

    public init(color: FolderColor? = nil, mark: FolderMark? = nil) {
        self.color = color
        self.mark = mark
        otherFields = [:]
    }

    /// Whether the folder looks like any other: nothing chosen, nothing to clear.
    public var isPlain: Bool { color == nil && mark == nil }

    init?(fields: [String: JSONValue]) {
        var fields = fields
        switch fields.removeValue(forKey: FolderStyleFieldName.color) {
        case .string(Self.noColorRawValue), nil: color = nil
        case .string(let colorName): color = FolderColor(rawValue: colorName)
        default: return nil
        }
        let symbol = fields.removeValue(forKey: FolderStyleFieldName.symbol)
        let emoji = fields.removeValue(forKey: FolderStyleFieldName.emoji)
        // Finder draws the symbol when a folder somehow has both.
        if case .string(let symbolName) = symbol, !symbolName.isEmpty {
            mark = .symbol(symbolName)
        } else if case .string(let emojiText) = emoji, !emojiText.isEmpty {
            mark = .emoji(emojiText)
        } else {
            mark = nil
        }
        otherFields = fields
    }

    var fields: [String: JSONValue] {
        var fields = otherFields
        fields[FolderStyleFieldName.color] = .string(color?.rawValue ?? Self.noColorRawValue)
        switch mark {
        case .symbol(let symbolName): fields[FolderStyleFieldName.symbol] = .string(symbolName)
        case .emoji(let emojiText): fields[FolderStyleFieldName.emoji] = .string(emojiText)
        case nil: break
        }
        return fields
    }
}
