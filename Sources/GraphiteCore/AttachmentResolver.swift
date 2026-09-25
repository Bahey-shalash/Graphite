import Foundation

/// Applies the vault's Obsidian attachment and link settings. Editors ask this policy
/// where a new file belongs and how to reference it; they never decide it themselves.
public struct AttachmentResolver: Sendable {
    public init() {}

    public func directory(for location: AttachmentLocation, note: VaultPath) throws -> VaultPath {
        switch location {
        case .vaultFolder: return .root
        case .sameFolderAsNote: return note.parent
        case .specifiedFolder(let folder): return try AttachmentLocation.specifiedFolderPath(folder)
        case .subfolderUnderNote(let folder): return try note.parent.appending(folder)
        }
    }

    /// `isNameUniqueInVault` states that no other vault file shares the attachment's name.
    /// Pass false when that is not yet known: a full vault path is always a valid link.
    public func embed(attachment: VaultPath, note: VaultPath, settings: ObsidianSettings, isNameUniqueInVault: Bool) -> String {
        let linkTarget: String
        switch settings.linkFormat {
        case .absolute: linkTarget = attachment.rawValue
        case .relative: linkTarget = attachment.relativePath(from: note.parent)
        case .shortest: linkTarget = isNameUniqueInVault ? attachment.name : attachment.rawValue
        }
        // These characters end or split a Wikilink target, so such names need a Markdown link.
        let wikilinkReservedCharacters = CharacterSet(charactersIn: "|[]#^")
        if settings.usesWikilinks && linkTarget.rangeOfCharacter(from: wikilinkReservedCharacters) == nil {
            return "![[\(linkTarget)]]"
        }
        let unreservedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/")
        return "![](\(linkTarget.addingPercentEncoding(withAllowedCharacters: unreservedCharacters) ?? linkTarget))"
    }

    /// A readable, practically unique name in the style of Obsidian's pasted images. The
    /// year is always Gregorian, like pasted images' names, so names sort by date whatever
    /// calendar the device uses (a Japanese-calendar device would otherwise write year 8).
    public func drawingFileStem(createdAt date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func twoDigits(_ number: Int?) -> String { String(format: "%02d", number ?? 0) }
        return "Drawing \(components.year ?? 0)-\(twoDigits(components.month))-\(twoDigits(components.day)) \(twoDigits(components.hour)).\(twoDigits(components.minute)).\(twoDigits(components.second))"
    }
}
