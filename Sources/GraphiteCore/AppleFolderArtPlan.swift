import Foundation

/// How a folder look is drawn with Apple's own folder art where the folder itself cannot
/// carry it yet (a preview in the popover, a look not written): the system draws a stand-in
/// folder that carries exactly the attributes Graphite writes for the look, so the colors,
/// gradient and engraving are Apple's and the same as on the folder once written. A picture
/// is placed on that art.
///
/// The stand-in lives in Graphite's temporary items, never in the vault.
public struct AppleFolderArtPlan: Equatable, Sendable {
    /// What the stand-in folder carries: the look's tag color and symbol or emoji.
    public let standIn: FinderFolderLookChange
    /// A picture placed on the art, or drawn as the whole icon.
    public let picture: FolderPicture?

    public static func plan(for style: FolderStyle) -> AppleFolderArtPlan {
        let colorTagNames = Dictionary(uniqueKeysWithValues: FinderTagColor.allCases.map { color in (color, color.defaultTagName) })
        var withoutPicture = style
        if style.picture != nil { withoutPicture.mark = nil }
        let standIn = FinderFolderLookChange.change(for: withoutPicture, from: .plain, colorTagNames: colorTagNames)
        return AppleFolderArtPlan(standIn: standIn, picture: style.picture)
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
