import Foundation

/// The keys of one folder's entry in `.obsidian/graphite-folder-styles.json`.
enum FolderStyleFieldName {
    static let color = "color"
    static let symbol = "symbol"
    static let emoji = "emoji"
    static let picture = "picture"
    static let pictureLayout = "pictureLayout"
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

/// How a folder's picture is drawn.
public enum FolderPictureLayout: Equatable, Hashable, Sendable {
    /// A rounded picture in the middle of the folder, as Finder draws app folders.
    case onFolder
    /// The picture is the whole icon, as a custom icon set in Finder.
    case wholeIcon
    /// A layout written by a newer Graphite; drawn on the folder.
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "onFolder": self = .onFolder
        case "wholeIcon": self = .wholeIcon
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .onFolder: "onFolder"
        case .wholeIcon: "wholeIcon"
        case .unknown(let rawValue): rawValue
        }
    }
}

/// A picture a folder carries: a PNG kept in the vault, under `directory`, so it syncs with it.
public struct FolderPicture: Equatable, Hashable, Sendable {
    /// Where Graphite keeps folder pictures; Obsidian ignores the folder.
    public static let directory = ".obsidian/graphite-folder-icons"

    public let path: VaultPath
    public let layout: FolderPictureLayout

    public init(path: VaultPath, layout: FolderPictureLayout) {
        self.path = path
        self.layout = layout
    }
}

/// What is drawn on a folder, as Finder draws it: an SF Symbol engraved in the folder's
/// color, an emoji in its own colors, or a picture. A folder has one of them.
public enum FolderMark: Equatable, Hashable, Sendable {
    case symbol(String)
    case emoji(String)
    case picture(FolderPicture)

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

    /// The folder's picture, when its mark is one.
    public var picture: FolderPicture? {
        if case .picture(let picture) = mark { picture } else { nil }
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
        let picture = Self.picture(path: fields.removeValue(forKey: FolderStyleFieldName.picture),
                                   layout: fields.removeValue(forKey: FolderStyleFieldName.pictureLayout))
        // Finder draws the symbol when a folder somehow has both; a picture comes first, as Finder's custom icon.
        if let picture {
            mark = .picture(picture)
        } else if case .string(let symbolName) = symbol, !symbolName.isEmpty {
            mark = .symbol(symbolName)
        } else if case .string(let emojiText) = emoji, !emojiText.isEmpty {
            mark = .emoji(emojiText)
        } else {
            mark = nil
        }
        otherFields = fields
    }

    /// A picture only inside Graphite's picture folder: a style file edited by hand cannot
    /// point a tile at another file of the vault.
    private static func picture(path: JSONValue?, layout: JSONValue?) -> FolderPicture? {
        guard case .string(let pathText) = path, let picturePath = try? VaultPath(pathText), // A path no vault can hold is no picture.
              picturePath.parent.rawValue == FolderPicture.directory else { return nil }
        let layoutName = if case .string(let name) = layout { name } else { FolderPictureLayout.onFolder.rawValue }
        return FolderPicture(path: picturePath, layout: FolderPictureLayout(rawValue: layoutName))
    }

    var fields: [String: JSONValue] {
        var fields = otherFields
        fields[FolderStyleFieldName.color] = .string(color?.rawValue ?? Self.noColorRawValue)
        switch mark {
        case .symbol(let symbolName): fields[FolderStyleFieldName.symbol] = .string(symbolName)
        case .emoji(let emojiText): fields[FolderStyleFieldName.emoji] = .string(emojiText)
        case .picture(let picture):
            fields[FolderStyleFieldName.picture] = .string(picture.path.rawValue)
            fields[FolderStyleFieldName.pictureLayout] = .string(picture.layout.rawValue)
        case nil: break
        }
        return fields
    }
}
