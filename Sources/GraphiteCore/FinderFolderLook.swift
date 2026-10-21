import Foundation

/// The color numbers of Finder's tags, as a tag keeps it after its name ("Green\n2"). Finder
/// tints a folder that has a symbol or emoji in the color of its last tag with a color.
public enum FinderTagColor: Int, CaseIterable, Sendable {
    case gray = 1, green, purple, blue, yellow, red, orange

    /// The tag color of a folder color; nil for a color no tag has, such as a custom one.
    public init?(folderColor: FolderColor) {
        switch folderColor {
        case .gray: self = .gray
        case .green: self = .green
        case .purple: self = .purple
        case .blue: self = .blue
        case .yellow: self = .yellow
        case .red: self = .red
        case .orange: self = .orange
        case .pink, .indigo, .teal, .custom, .unknown: return nil
        }
    }

    public var folderColor: FolderColor {
        switch self {
        case .gray: .gray
        case .green: .green
        case .purple: .purple
        case .blue: .blue
        case .yellow: .yellow
        case .red: .red
        case .orange: .orange
        }
    }

    /// The English name of the tag Finder makes for this color, used where the system's own
    /// (possibly translated) names are not at hand.
    public var defaultTagName: String {
        switch self {
        case .gray: "Gray"
        case .green: "Green"
        case .purple: "Purple"
        case .blue: "Blue"
        case .yellow: "Yellow"
        case .red: "Red"
        case .orange: "Orange"
        }
    }
}

/// One of Finder's tags as `com.apple.metadata:_kMDItemUserTags` keeps it: its name, then a
/// line break and its color number when it has one.
public struct FinderTag: Equatable, Sendable {
    public let name: String
    public let color: FinderTagColor?

    public init(name: String, color: FinderTagColor?) {
        self.name = name
        self.color = color
    }

    /// As the tag attribute keeps it: "Green\n2", or the name alone for a tag without a color.
    public var storedText: String {
        color.map { color in "\(name)\n\(color.rawValue)" } ?? name
    }

    init(storedText: String) {
        let parts = storedText.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        name = String(parts[0])
        color = parts.count == 2 ? Int(parts[1]).flatMap(FinderTagColor.init(rawValue:)) : nil
    }
}

/// How Finder shows a folder, read from the folder's own metadata where macOS 27's Finder
/// keeps it (found by experiment, see `Docs/Notebook-library-and-new-file-todo.md`):
/// - the color is the last colored tag of `com.apple.metadata:_kMDItemUserTags`;
/// - a symbol or emoji is the JSON `{"sym": name}` or `{"emoji": text}` of
///   `com.apple.icon.folder#S`, used only while the custom-icon flag of `com.apple.FinderInfo`
///   is set; the `#S` marks the attribute as one iCloud Drive syncs;
/// - a picture is the folder's hidden `Icon\r` file, with the same flag.
public struct FinderFolderLook: Equatable, Sendable {
    public static let tagsAttributeName = "com.apple.metadata:_kMDItemUserTags"
    public static let iconAttributeName = "com.apple.icon.folder#S"
    public static let finderInformationAttributeName = "com.apple.FinderInfo"
    public static let customIconFileName = "Icon\r"
    /// Bounds on what is read: a folder's tags, and the icon attribute's few bytes of JSON.
    public static let maximumTagsBytes = 65_536
    public static let maximumIconAttributeBytes = 4_096
    /// The legacy Finder information is 32 bytes; its flags are the big-endian bytes 8 and 9.
    public static let finderInformationBytes = 32
    static let flagsByteOffset = 8
    /// `kHasCustomIcon`, in the high byte of the flags.
    static let customIconFlagHighByte: UInt8 = 0x04
    /// The legacy color label, bits 1 to 3 of the low byte of the flags; Finder keeps it equal
    /// to the color of the last colored tag.
    static let labelBitsMask: UInt8 = 0x0E

    private enum IconFieldName {
        static let symbol = "sym"
        static let emoji = "emoji"
    }

    public var tags: [FinderTag]
    /// Drawn only while `hasCustomIconFlag` is set, as Finder does.
    public var iconMark: FolderMark?
    public var hasCustomIconFlag: Bool
    public var hasCustomIconFile: Bool

    public static let plain = FinderFolderLook(tags: [], iconMark: nil, hasCustomIconFlag: false, hasCustomIconFile: false)

    public init(tags: [FinderTag], iconMark: FolderMark?, hasCustomIconFlag: Bool, hasCustomIconFile: Bool) {
        self.tags = tags
        self.iconMark = iconMark
        self.hasCustomIconFlag = hasCustomIconFlag
        self.hasCustomIconFile = hasCustomIconFile
    }

    /// Reads the attributes as stored; data that is not in the expected form counts as absent.
    public init(tagsData: Data?, iconData: Data?, finderInformationData: Data?, hasCustomIconFile: Bool) {
        self.init(tags: Self.tags(from: tagsData), iconMark: Self.mark(from: iconData),
                  hasCustomIconFlag: Self.hasCustomIconFlag(in: finderInformationData), hasCustomIconFile: hasCustomIconFile)
    }

    /// The color Finder tints the folder in: its last tag with a color.
    public var color: FinderTagColor? { tags.last { tag in tag.color != nil }?.color }

    /// The symbol or emoji Finder draws on the folder.
    public var mark: FolderMark? { hasCustomIconFlag ? iconMark : nil }

    /// Whether Finder draws its custom icon file: the flag is set and no symbol or emoji wins over it.
    public var showsCustomIconFile: Bool { hasCustomIconFlag && hasCustomIconFile && mark == nil }

    /// Whether Finder draws the folder unlike a plain one. A tag alone only adds a dot
    /// beside the name: Finder tints a folder only when it has a symbol or emoji.
    public var isCustomized: Bool { mark != nil || (hasCustomIconFlag && hasCustomIconFile) }

    /// The look in Graphite's terms, for drawing where the system's icon is not available.
    /// The look in Graphite's terms: the tag color and the symbol or emoji. A picture set in
    /// Finder has no place in Graphite's style; the system's icon shows it.
    public var style: FolderStyle {
        FolderStyle(color: color?.folderColor, mark: mark)
    }

    static func tags(from tagsData: Data?) -> [FinderTag] {
        guard let tagsData, tagsData.count <= maximumTagsBytes,
              let storedTexts = try? PropertyListSerialization.propertyList(from: tagsData, format: nil) as? [String] // Not a tag list: no tags.
        else { return [] }
        return storedTexts.map(FinderTag.init(storedText:))
    }

    static func mark(from iconData: Data?) -> FolderMark? {
        guard let iconData, iconData.count <= maximumIconAttributeBytes,
              case .object(let fields) = try? JSONDecoder().decode(JSONValue.self, from: iconData) // Not JSON: no mark.
        else { return nil }
        // Finder draws the symbol when both are there.
        if case .string(let symbolName) = fields[IconFieldName.symbol], !symbolName.isEmpty { return .symbol(symbolName) }
        if case .string(let emojiText) = fields[IconFieldName.emoji], !emojiText.isEmpty { return .emoji(emojiText) }
        return nil
    }

    static func hasCustomIconFlag(in finderInformationData: Data?) -> Bool {
        guard let finderInformationData, finderInformationData.count == finderInformationBytes else { return false }
        return finderInformationData[finderInformationData.startIndex + flagsByteOffset] & customIconFlagHighByte != 0
    }

    /// The icon attribute Finder reads for a symbol or emoji; nil for a picture, which is
    /// Finder's custom icon file instead.
    public static func iconAttributeData(for mark: FolderMark) -> Data? {
        let fields: [String: JSONValue]
        switch mark {
        case .symbol(let symbolName): fields = [IconFieldName.symbol: .string(symbolName)]
        case .emoji(let emojiText): fields = [IconFieldName.emoji: .string(emojiText)]
        case .picture: return nil
        }
        return (try? JSONEncoder().encode(JSONValue.object(fields))) ?? Data() // Encoding a dictionary of strings cannot fail.
    }

    /// The Finder information with the custom-icon flag set or cleared and the color label
    /// set, every other byte kept; nil when nothing is left in it, so the attribute can be removed.
    public static func finderInformation(_ existingData: Data?, settingCustomIconFlag isSet: Bool, labelColor: FinderTagColor?) -> Data? {
        var bytes = existingData.flatMap { data in data.count == finderInformationBytes ? [UInt8](data) : nil }
            ?? [UInt8](repeating: 0, count: finderInformationBytes)
        if isSet { bytes[flagsByteOffset] |= customIconFlagHighByte } else { bytes[flagsByteOffset] &= ~customIconFlagHighByte }
        let labelBits = UInt8(labelColor?.rawValue ?? 0) << 1
        bytes[flagsByteOffset + 1] = bytes[flagsByteOffset + 1] & ~labelBitsMask | labelBits
        return bytes.allSatisfy { byte in byte == 0 } ? nil : Data(bytes)
    }

    /// The tag attribute for these tags; nil for none, so the attribute can be removed.
    public static func tagsAttributeData(for tags: [FinderTag]) -> Data? {
        guard !tags.isEmpty else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: tags.map(\.storedText), format: .binary, options: 0) // A list of strings always encodes.
    }
}
