import Foundation

/// Where a vault folder is, kept in a form that survives relaunches and app updates.
public struct VaultLocation: Codable, Hashable, Sendable {
    public enum Anchor: Codable, Hashable, Sendable {
        /// A folder the user picked, kept as bookmark data so access can be restored.
        case bookmark(Data)
        /// The app's own Documents folder, which Files shows as "On My iPad › Graphite".
        case applicationDocuments
    }

    public var anchor: Anchor
    /// The vault folder inside the anchor folder; empty when the anchor is the vault itself.
    public var relativePath: String

    public init(anchor: Anchor, relativePath: String = "") {
        self.anchor = anchor
        self.relativePath = relativePath
    }
}

/// A vault Graphite has opened before, listed in the vault switcher.
public struct KnownVault: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    /// The folder's name, refreshed each time the vault opens.
    public var name: String
    public var location: VaultLocation
    /// Where the folder was last found, to recognize the same folder when it is picked again.
    public var lastKnownPath: String
    public var lastOpenedDate: Date
    /// The document that was open when the user last left this vault, reopened on return.
    public var lastOpenedDocument: VaultPath?
}

/// The vaults in the vault switcher, like Obsidian's vault list. Only this list is stored
/// by Graphite; the vaults are ordinary folders, and removing an entry never touches them.
public struct VaultList: Codable, Equatable, Sendable {
    public private(set) var vaults: [KnownVault] = []

    public init() {}

    /// Alphabetical, so each vault keeps its place in menus.
    public var sortedByName: [KnownVault] {
        vaults.sorted { leftVault, rightVault in leftVault.name.localizedStandardCompare(rightVault.name) == .orderedAscending }
    }

    public var mostRecentlyOpened: KnownVault? {
        vaults.max { leftVault, rightVault in leftVault.lastOpenedDate < rightVault.lastOpenedDate }
    }

    public func vault(withIdentifier identifier: UUID) -> KnownVault? {
        vaults.first { vault in vault.id == identifier }
    }

    /// The identifier `recordOpening` would return for these arguments, without recording
    /// anything; nil for a vault not in the list yet.
    public func existingIdentifier(identifier: UUID? = nil, location: VaultLocation, path: String) -> UUID? {
        (identifier.flatMap { identifier in vaults.first { vault in vault.id == identifier } }
            ?? vaults.first { vault in vault.lastKnownPath == path || vault.location == location })?.id
    }

    /// Records that a vault was opened and returns its identifier. `identifier` names a
    /// vault already in the list; otherwise the same folder picked again (matched by
    /// `path`) updates its existing entry instead of adding a duplicate.
    @discardableResult
    public mutating func recordOpening(identifier: UUID? = nil, name: String, location: VaultLocation, path: String, at date: Date) -> UUID {
        let existingIndex = identifier.flatMap { identifier in vaults.firstIndex { vault in vault.id == identifier } }
            ?? vaults.firstIndex { vault in vault.lastKnownPath == path || vault.location == location }
        guard let existingIndex else {
            let vault = KnownVault(id: identifier ?? UUID(), name: name, location: location, lastKnownPath: path, lastOpenedDate: date, lastOpenedDocument: nil)
            vaults.append(vault)
            return vault.id
        }
        vaults[existingIndex].name = name
        vaults[existingIndex].location = location
        vaults[existingIndex].lastKnownPath = path
        vaults[existingIndex].lastOpenedDate = date
        return vaults[existingIndex].id
    }

    public mutating func setLastOpenedDocument(_ document: VaultPath?, inVault identifier: UUID) {
        guard let vaultIndex = vaults.firstIndex(where: { vault in vault.id == identifier }) else { return }
        vaults[vaultIndex].lastOpenedDocument = document
    }

    /// Forgets a vault. Its folder and files are left exactly as they are.
    public mutating func remove(_ identifier: UUID) {
        vaults.removeAll { vault in vault.id == identifier }
    }

    /// The name for a new vault folder, or an error explaining why it cannot be used.
    public static func validatedFolderName(_ proposedName: String) throws -> String {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw GraphiteError.invalidFile("Enter a name for the vault.") }
        guard !name.hasPrefix(".") else { throw GraphiteError.invalidFile("A vault name can't start with a period, because the folder would be hidden.") }
        // The same characters Graphite refuses in any file or folder name inside the vault,
        // since the vault folder syncs to the same platforms.
        guard name.rangeOfCharacter(from: FileNameRules.forbiddenCharacters) == nil, name.rangeOfCharacter(from: FileNameRules.controlCharacters) == nil else {
            throw GraphiteError.invalidFile("A vault name can't contain line breaks or any of these characters: / \\ : * ? \" < > |")
        }
        return name
    }

    /// Where a vault's folder is, in words: the enclosing folder rather than a system path.
    /// `deviceName` is "iPad", "iPhone", or "Mac"; `applicationName` names Graphite's own folder.
    public static func readableLocation(of vault: KnownVault, deviceName: String, applicationName: String = "Graphite") -> String {
        if vault.location.anchor == .applicationDocuments {
            let enclosingFolders = vault.location.relativePath.split(separator: "/").dropLast().map(String.init)
            return (["On My \(deviceName)", applicationName] + enclosingFolders).joined(separator: " › ")
        }
        let enclosingPath = (vault.lastKnownPath as NSString).deletingLastPathComponent
        let components = enclosingPath.split(separator: "/").map(String.init)
        if let mobileDocumentsIndex = components.firstIndex(of: "Mobile Documents"), mobileDocumentsIndex + 1 < components.count {
            // iCloud Drive keeps each app's folder as "iCloud~identifier/Documents".
            let container = components[mobileDocumentsIndex + 1]
            var names = ["iCloud Drive"]
            var remainder = Array(components[(mobileDocumentsIndex + 2)...])
            if container != "com~apple~CloudDocs" {
                names.append(container == "iCloud~md~obsidian" ? "Obsidian" : String(container.split(separator: "~").last ?? Substring(container)))
                if remainder.first == "Documents" { remainder.removeFirst() }
            }
            return (names + remainder).joined(separator: " › ")
        }
        if let storageIndex = components.firstIndex(of: "File Provider Storage") {
            // On My iPad and third-party providers (Working Copy, Dropbox) all keep files in a
            // "File Provider Storage" folder of a shared container named by a random identifier,
            // so the path cannot tell which one Files shows; "Files" is true for all of them.
            return (["Files"] + components[(storageIndex + 1)...]).joined(separator: " › ")
        }
        if let applicationIndex = components.firstIndex(of: "Application"), applicationIndex + 2 < components.count, components[applicationIndex + 2] == "Documents" {
            return (["On My \(deviceName)", applicationName] + components[(applicationIndex + 3)...]).joined(separator: " › ")
        }
        return (enclosingPath as NSString).abbreviatingWithTildeInPath
    }
}
