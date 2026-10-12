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
