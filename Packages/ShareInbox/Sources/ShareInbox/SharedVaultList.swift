import Foundation

/// The vaults the app knows, published for the share extension, which cannot read the app's
/// own preferences. Only names and identifiers: the extension never reaches a vault.
public struct SharedVaultList: Codable, Equatable, Sendable {
    public struct Vault: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var lastOpenedDate: Date

        public init(id: UUID, name: String, lastOpenedDate: Date) {
            self.id = id
            self.name = name
            self.lastOpenedDate = lastOpenedDate
        }
    }

    public var vaults: [Vault]

    public init(vaults: [Vault]) {
        self.vaults = vaults
    }

    /// The vault opened last, which the share sheet chooses first.
    public var mostRecentlyOpened: Vault? {
        vaults.max { first, second in first.lastOpenedDate < second.lastOpenedDate }
    }

    /// The vaults by name, as the share sheet lists them.
    public var sortedByName: [Vault] {
        vaults.sorted { first, second in first.name.localizedStandardCompare(second.name) == .orderedAscending }
    }
}

/// What reading the published vault list found. A list that cannot be read is not the same
/// as no list: the share sheet says so instead of offering no vault.
public enum SharedVaultListReading: Sendable {
    case missing
    case read(SharedVaultList)
    case unreadable(any Error)
}
