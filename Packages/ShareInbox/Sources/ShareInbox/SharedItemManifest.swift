import Foundation

/// Where a shared item asks to go: a note of its own, or the end of the daily note of the
/// day it was shared. A destination written by a newer extension that this build does not
/// know is kept as `unknown`, so the item is left in the inbox rather than misfiled.
public enum SharedItemDestination: Equatable, Sendable, Codable {
    case newNote
    case dailyNote
    case unknown(String)

    private static let newNoteRawValue = "newNote"
    private static let dailyNoteRawValue = "dailyNote"

    public init(rawValue: String) {
        switch rawValue {
        case Self.newNoteRawValue: self = .newNote
        case Self.dailyNoteRawValue: self = .dailyNote
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .newNote: Self.newNoteRawValue
        case .dailyNote: Self.dailyNoteRawValue
        case .unknown(let rawValue): rawValue
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The description of one shared item, `item.json` in the item's folder. The item's text is
/// its `Note.md` and its files are in its `Attachments` folder, in `attachmentFileNames` order.
public struct SharedItemManifest: Codable, Equatable, Sendable {
    /// The format this build writes. An item of a later format is left for a later build.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var identifier: UUID
    /// When the item was shared: a daily note destination means the daily note of this day.
    public var createdDate: Date
    /// The vault chosen in the share sheet, nil when the device knew no vault yet.
    public var vaultIdentifier: UUID?
    /// The vault's name when it was chosen, to name it if it is gone by delivery.
    public var vaultName: String?
    public var destination: SharedItemDestination
    /// The title typed in the share sheet: the new note's name.
    public var title: String
    public var attachmentFileNames: [String]

    public init(identifier: UUID, createdDate: Date, vaultIdentifier: UUID?, vaultName: String?, destination: SharedItemDestination,
                title: String, attachmentFileNames: [String], formatVersion: Int = Self.currentFormatVersion) {
        self.formatVersion = formatVersion
        self.identifier = identifier
        self.createdDate = createdDate
        self.vaultIdentifier = vaultIdentifier
        self.vaultName = vaultName
        self.destination = destination
        self.title = title
        self.attachmentFileNames = attachmentFileNames
    }
}
