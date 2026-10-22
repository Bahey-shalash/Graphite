import Foundation
import Security

/// The secrets community plugins keep with Obsidian's `app.secretStorage` (API keys and
/// tokens), one set per vault, in the device's keychain. They never go into the vault, so
/// they do not sync, as Obsidian keeps them out of the vault too.
public struct CommunityPluginSecretStore: Sendable {
    private static let service = "Graphite community plugin secrets"
    /// A plugin's secrets for one vault are small; more than this is not a secret store.
    private static let maximumStoredBytes = 1_048_576
    private let vaultIdentifier: UUID

    public init(vaultIdentifier: UUID) {
        self.vaultIdentifier = vaultIdentifier
    }

    private var item: KeychainGenericPasswordItem {
        KeychainGenericPasswordItem(service: Self.service, account: vaultIdentifier.uuidString)
    }

    /// Every secret of the vault, by identifier; none when nothing is stored.
    /// - Throws: `CommunityPluginSecretError.unreadable` when the keychain does not give the
    ///   item back or the item is not a list of secrets. A failed read is never "no secrets":
    ///   a save that started from it would replace every other secret of the vault.
    public func secrets() throws -> [String: String] {
        let (status, data) = item.read()
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess, let data else { throw CommunityPluginSecretError.unreadable(status) }
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            throw CommunityPluginSecretError.unreadable(nil)
        }
    }

    /// Keeps `secret` under `identifier`, with every other secret of the vault as it is; an
    /// empty secret removes it. Refused, with nothing written, when the stored secrets cannot
    /// be read.
    public func setSecret(_ secret: String, forIdentifier identifier: String) throws {
        var updated = try secrets()
        updated[identifier] = secret.isEmpty ? nil : secret
        let data = try JSONEncoder().encode(updated)
        guard data.count <= Self.maximumStoredBytes else { throw CommunityPluginSecretError.tooLarge }
        let status = item.write(data)
        guard status == errSecSuccess else { throw CommunityPluginSecretError.keychain(status) }
    }

    /// Forgets the vault's secrets, when the vault leaves Graphite's list.
    public func removeAllSecrets() {
        item.delete()
    }
}

public enum CommunityPluginSecretError: Error, LocalizedError {
    case tooLarge
    case keychain(OSStatus)
    /// The stored secrets could not be read: the keychain answered with this status, or (nil)
    /// gave back an item that is not a list of secrets.
    case unreadable(OSStatus?)

    public var errorDescription: String? {
        switch self {
        case .tooLarge: "The plugin's secrets are too large to keep."
        case .keychain(let status): "The keychain did not keep the plugin's secret (\(status))."
        case .unreadable(let status):
            "The keychain did not give back this vault's plugin secrets\(status.map { statusCode in " (\(statusCode))" } ?? ""), so they were left as they are."
        }
    }
}
