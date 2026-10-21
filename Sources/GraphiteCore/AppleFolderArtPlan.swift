import Foundation

/// How a folder look Graphite draws is made from Apple's own folder art: the system draws a
/// stand-in folder that carries the look's tag color and mark, so the colors, gradient and
/// engraving are Apple's; what no tag can hold is added after.
///
/// The stand-in lives in Graphite's temporary items, never in the vault. A color without a
/// symbol or emoji is drawn by giving the stand-in an emoji of one space, which the system
/// tints without drawing anything (found by experiment; Graphite never writes it on a
/// person's folder, where Finder shows a color alone as a tag dot).
public struct AppleFolderArtPlan: Equatable, Sendable {
    /// What the stand-in folder carries.
    public let standIn: FinderFolderLookChange
    /// A color no tag has: the stand-in is gray, and its art is tinted to this color.
    public let tintColor: FolderColor?
    /// A symbol or emoji drawn over the art, for a color no tag has; nil when the art has it.
    public let markDrawnOver: FolderMark?
    /// A picture placed on the art, or drawn as the whole icon.
    public let picture: FolderPicture?

    /// The emoji that tints a stand-in folder without drawing anything on it.
    static let invisibleEmoji = " "

    public static func plan(for style: FolderStyle) -> AppleFolderArtPlan {
        let tagColor = style.color.flatMap(FinderTagColor.init(folderColor:))
        let tintColor = tagColor == nil ? style.color : nil
        let standInColor: FinderTagColor? = tintColor == nil ? tagColor : .gray
        let artMark: FolderMark?
        switch style.mark {
        case .symbol, .emoji: artMark = tintColor == nil ? style.mark : nil
        case .picture, nil: artMark = nil
        }
        let markDrawnOver: FolderMark? = artMark == nil && style.picture == nil ? style.mark : nil
        // Without a mark the stand-in is tinted by the invisible emoji, when it has a color.
        let standInMark = artMark ?? (standInColor == nil ? nil : .emoji(invisibleEmoji))
        let tags = standInColor.map { color in [FinderTag(name: color.defaultTagName, color: color)] } ?? []
        let standIn = FinderFolderLookChange(tags: tags, iconAttributeData: standInMark.flatMap(FinderFolderLook.iconAttributeData(for:)),
                                             setsCustomIconFlag: standInMark != nil, customIconFile: .keep)
        return AppleFolderArtPlan(standIn: standIn, tintColor: tintColor, markDrawnOver: markDrawnOver, picture: style.picture)
    }

    /// The stand-in folder's name: one per look, so the system's icon cache never mixes two.
    public var standInName: String {
        let tagsText = standIn.tags.map(\.storedText).joined(separator: ",")
        let iconText = standIn.iconAttributeData.map { iconData in String(decoding: iconData, as: UTF8.self) } ?? ""
        var hasher = StableNameHasher()
        hasher.combine(tagsText + "|" + iconText)
        return "Look \(hasher.hexadecimalValue)"
    }
}

/// FNV-1a over UTF-8: the same name for the same look in every launch, unlike `Hasher`.
struct StableNameHasher {
    private var value: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01B3

    mutating func combine(_ text: String) {
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* Self.prime
        }
    }

    var hexadecimalValue: String { String(value, radix: 16) }
}
