import Foundation
import Security

/// Which keychain Graphite's items go in.
enum KeychainAvailability {
    /// Whether this process may use the data protection keychain. A Mac app signed without an
    /// application identifier, as Graphite's Mac builds are so far, may not
    /// (errSecMissingEntitlement, -34018), and keeps its items in the login keychain instead,
    /// where they belong to the app. Deleting an item that never exists tells: a read would
    /// only answer that nothing was found.
    static let usesDataProtectionKeychain: Bool = {
        #if os(macOS)
        let probe: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Graphite community plugin secrets availability",
                                    kSecUseDataProtectionKeychain as String: true]
        return SecItemDelete(probe as CFDictionary) != errSecMissingEntitlement
        #else
        return true
        #endif
    }()
}
