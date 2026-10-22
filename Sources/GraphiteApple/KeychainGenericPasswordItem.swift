import Foundation
import Security

/// One of Graphite's generic-password items in the device's keychain, found by its service and
/// account and readable on this device only, after its first unlock. The community plugins'
/// secrets are kept as one per vault; this is the one place that builds the keychain's
/// queries for such items.
struct KeychainGenericPasswordItem: Sendable {
    let service: String
    let account: String

    private var query: [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        // The data protection keychain, so the accessibility below applies on macOS too.
        if KeychainAvailability.usesDataProtectionKeychain { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }

    /// The item's bytes and the keychain's answer: `errSecItemNotFound` when there is no item.
    func read() -> (status: OSStatus, data: Data?) {
        var readQuery = query
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &item)
        return (status, item as? Data)
    }

    /// Writes `data` over the item, adding the item when there is none, and returns the
    /// keychain's answer.
    func write(_ data: Data) -> OSStatus {
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else { return status }
        return SecItemAdd(query.merging(attributes) { _, newValue in newValue } as CFDictionary, nil)
    }

    /// Removes the item and returns the keychain's answer: `errSecItemNotFound` when there was none.
    @discardableResult
    func delete() -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
