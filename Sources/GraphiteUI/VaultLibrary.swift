import Foundation
import Observation
import GraphiteCore
#if canImport(UIKit)
import UIKit
#endif

/// The vaults this device knows, saved in the app's preferences. Only where each folder
/// is and what was last open are stored; the vaults stay ordinary folders.
@MainActor @Observable
final class VaultLibrary {
    private static let storageKey = "GraphiteKnownVaults"
    /// Graphite remembered a single vault before it had a vault list.
    private static let singleVaultBookmarkKey = "GraphiteVaultBookmark"
    /// A stored list this build could not read at all, kept rather than written over.
    static let unreadableListKey = "GraphiteKnownVaults.unreadable"
    private let defaults: UserDefaults
    /// Stored entries this build cannot decode, such as a vault saved by a newer build with
    /// a kind of location this one does not know. They are written back unchanged.
    @ObservationIgnored private var unreadableEntries: [Any] = []

    private(set) var list: VaultList {
        didSet { if list != oldValue { saveList() } }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        list = VaultList()
        if let storedList = defaults.data(forKey: Self.storageKey) { loadList(from: storedList) }
        adoptSingleVaultBookmark()
    }

    var vaults: [KnownVault] { list.sortedByName }

    func vault(withIdentifier identifier: UUID) -> KnownVault? { list.vault(withIdentifier: identifier) }

    @discardableResult
    func recordOpening(identifier: UUID?, root: URL, location: VaultLocation) -> UUID {
        list.recordOpening(identifier: identifier, name: root.lastPathComponent, location: location, path: Self.comparablePath(of: root), at: .now)
    }

    /// The identifier the vault at `root` has or will have in the list.
    func existingIdentifier(identifier: UUID?, root: URL, location: VaultLocation) -> UUID? {
        list.existingIdentifier(identifier: identifier, location: location, path: Self.comparablePath(of: root))
    }

    func setLastOpenedDocument(_ document: VaultPath?, inVault identifier: UUID) {
        list.setLastOpenedDocument(document, inVault: identifier)
    }

    func remove(_ identifier: UUID) { list.remove(identifier) }

    /// Where the vault's folder is, in the Files app's words, such as "iCloud Drive › Obsidian".
    func readableLocation(of vault: KnownVault) -> String {
        #if canImport(UIKit)
        VaultList.readableLocation(of: vault, deviceName: UIDevice.current.model)
        #else
        VaultList.readableLocation(of: vault, deviceName: "Mac")
        #endif
    }

    /// The same folder can be reported with or without iOS's `/private` prefix.
    private static func comparablePath(of folder: URL) -> String {
        folder.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Reads the stored list one entry at a time, so one entry this build cannot decode
    /// does not hide every other vault. `VaultList` stores its entries under "vaults".
    private func loadList(from storedList: Data) {
        guard let storedObject = try? JSONSerialization.jsonObject(with: storedList) as? [String: Any],
              let storedEntries = storedObject["vaults"] as? [Any] else {
            // Kept under another key, so the next change to the list cannot destroy it.
            defaults.set(storedList, forKey: Self.unreadableListKey)
            return
        }
        var readableEntries: [Any] = []
        for entry in storedEntries {
            // `JSONSerialization` raises an exception, rather than throwing, for a value that
            // is not an object or array, so every entry is checked first.
            if JSONSerialization.isValidJSONObject(entry), let entryData = try? JSONSerialization.data(withJSONObject: entry),
               (try? JSONDecoder().decode(KnownVault.self, from: entryData)) != nil {
                readableEntries.append(entry)
            } else {
                unreadableEntries.append(entry)
            }
        }
        var readableObject = storedObject
        readableObject["vaults"] = readableEntries
        guard let readableData = try? JSONSerialization.data(withJSONObject: readableObject),
              let readableList = try? JSONDecoder().decode(VaultList.self, from: readableData) else {
            defaults.set(storedList, forKey: Self.unreadableListKey)
            unreadableEntries = []
            return
        }
        list = readableList
    }

    private func saveList() {
        guard let encodedList = try? JSONEncoder().encode(list) else { return }
        guard !unreadableEntries.isEmpty,
              var listObject = (try? JSONSerialization.jsonObject(with: encodedList)) as? [String: Any],
              let entries = listObject["vaults"] as? [Any] else {
            defaults.set(encodedList, forKey: Self.storageKey)
            return
        }
        listObject["vaults"] = entries + unreadableEntries
        guard let mergedList = try? JSONSerialization.data(withJSONObject: listObject) else { return }
        defaults.set(mergedList, forKey: Self.storageKey)
    }

    /// Adds the vault a single-vault build remembered. Its bookmark is forgotten only once
    /// it resolves: an iCloud or external folder that is unavailable now is tried again at
    /// the next launch.
    private func adoptSingleVaultBookmark() {
        guard let bookmark = defaults.data(forKey: Self.singleVaultBookmarkKey) else { return }
        var isStale = false
        #if os(macOS)
        let resolvedFolder = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #else
        let resolvedFolder = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #endif
        guard let resolvedFolder else { return }
        defaults.removeObject(forKey: Self.singleVaultBookmarkKey)
        let location = VaultLocation(anchor: .bookmark(bookmark))
        let path = Self.comparablePath(of: resolvedFolder)
        guard !list.vaults.contains(where: { vault in vault.lastKnownPath == path || vault.location == location }) else { return }
        // Vaults listed while the bookmark could not be resolved were opened after this one,
        // so it is dated before them and does not replace the vault reopened at launch.
        let openedDate = list.vaults.map(\.lastOpenedDate).min().map { oldestDate in oldestDate.addingTimeInterval(-1) } ?? .now
        list.recordOpening(name: resolvedFolder.lastPathComponent, location: location, path: path, at: openedDate)
    }
}
