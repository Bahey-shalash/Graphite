import Foundation

/// One of a vault's Obsidian settings files as Graphite last read it. A file that is missing
/// reads as Obsidian's defaults; a file that is there but cannot be read is `unreadable`, never
/// defaults and never the settings of the vault open before, so nothing is created or filled
/// in from settings the vault does not hold.
public enum VaultSettingsReading<Settings: Equatable & Sendable>: Equatable, Sendable {
    /// The file's settings, or Obsidian's defaults when there is no file.
    case read(Settings)
    /// The file is there and could not be read; `reason` says why, in words for the person.
    case unreadable(reason: String)

    /// The settings read, or nil while the file cannot be read.
    public var settings: Settings? {
        switch self {
        case .read(let settings): settings
        case .unreadable: nil
        }
    }

    /// Why the file could not be read, or nil when it was.
    public var unreadableReason: String? {
        switch self {
        case .read: nil
        case .unreadable(let reason): reason
        }
    }
}
