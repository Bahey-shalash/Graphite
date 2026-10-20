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

    /// Whether this process may use the data protection keychain. A Mac app signed without an
    /// application identifier, as Graphite's Mac builds are so far, may not
    /// (errSecMissingEntitlement, -34018), and keeps the secrets in the login keychain instead,
    /// where the item belongs to the app. Deleting an item that never exists tells: a read
    /// would only answer that nothing was found.
    private static let usesDataProtectionKeychain: Bool = {
        #if os(macOS)
        let probe: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service + " availability",
                                    kSecUseDataProtectionKeychain as String: true]
        return SecItemDelete(probe as CFDictionary) != errSecMissingEntitlement
        #else
        return true
        #endif
    }()

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service,
                                    kSecAttrAccount as String: vaultIdentifier.uuidString]
        // The data protection keychain, so the accessibility below applies on macOS too.
        if Self.usesDataProtectionKeychain { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }

    /// Every secret of the vault, by identifier; none when nothing is stored.
    /// - Throws: `CommunityPluginSecretError.unreadable` when the keychain does not give the
    ///   item back or the item is not a list of secrets. A failed read is never "no secrets":
    ///   a save that started from it would replace every other secret of the vault.
    public func secrets() throws -> [String: String] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess, let data = item as? Data else { throw CommunityPluginSecretError.unreadable(status) }
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
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(baseQuery.merging(attributes) { _, newValue in newValue } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CommunityPluginSecretError.keychain(status) }
    }

    /// Forgets the vault's secrets, when the vault leaves Graphite's list.
    public func removeAllSecrets() {
        SecItemDelete(baseQuery as CFDictionary)
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
