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

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: vaultIdentifier.uuidString]
    }

    /// Every secret of the vault, by identifier; none when nothing is stored or the stored
    /// value cannot be read.
    public func secrets() -> [String: String] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let secrets = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return secrets
    }

    public func setSecret(_ secret: String, forIdentifier identifier: String) throws {
        var updated = secrets()
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

    public var errorDescription: String? {
        switch self {
        case .tooLarge: "The plugin's secrets are too large to keep."
        case .keychain(let status): "The keychain did not keep the plugin's secret (\(status))."
        }
    }
}
