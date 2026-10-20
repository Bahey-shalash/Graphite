import XCTest
import Security
import GraphiteApple

/// The keychain item plugins' secrets are kept in: the data protection keychain in the app on
/// iPad and iPhone (the integration tests run this file there), the login keychain when the
/// data protection keychain is refused, as it is to the package tests and to Graphite's Mac app,
/// which is signed without an application identifier.
final class CommunityPluginSecretStoreTests: XCTestCase {
    func testSecretsAreKeptPerVaultAndForgotten() throws {
        let firstStore = CommunityPluginSecretStore(vaultIdentifier: UUID())
        let secondStore = CommunityPluginSecretStore(vaultIdentifier: UUID())
        defer {
            firstStore.removeAllSecrets()
            secondStore.removeAllSecrets()
        }
        try firstStore.setSecret("first-value", forIdentifier: "token")
        try firstStore.setSecret("other-value", forIdentifier: "other")
        try secondStore.setSecret("second-value", forIdentifier: "token")
        XCTAssertEqual(try firstStore.secrets(), ["token": "first-value", "other": "other-value"])
        XCTAssertEqual(try secondStore.secrets(), ["token": "second-value"])
        try firstStore.setSecret("", forIdentifier: "other")
        XCTAssertEqual(try firstStore.secrets(), ["token": "first-value"], "An empty secret removes it, as in Obsidian.")
        firstStore.removeAllSecrets()
        XCTAssertEqual(try firstStore.secrets(), [:])
        XCTAssertEqual(try secondStore.secrets(), ["token": "second-value"])
    }

    /// A failed read is not an empty set of secrets: when the stored item cannot be read, a save
    /// is refused and the item is left as it was, instead of being replaced by the one new secret.
    func testASaveIsRefusedAndTheItemKeptWhenTheStoredSecretsCannotBeRead() throws {
        let vaultIdentifier = UUID()
        let store = CommunityPluginSecretStore(vaultIdentifier: vaultIdentifier)
        defer { store.removeAllSecrets() }
        let unreadableSecrets = Data("not the JSON of a secret list".utf8)
        try RawSecretItem.add(unreadableSecrets, account: vaultIdentifier.uuidString)

        XCTAssertThrowsError(try store.secrets(), "Secrets that cannot be read are not reported as none.")
        XCTAssertThrowsError(try store.setSecret("new-value", forIdentifier: "token"))
        XCTAssertEqual(try RawSecretItem.data(account: vaultIdentifier.uuidString), unreadableSecrets, "The stored item is not written over.")
    }
}

/// The store's keychain item written and read directly, as another writer of the same service
/// and account would. It is kept where the store keeps it: the data protection keychain when
/// this process may use it, the login keychain otherwise.
private enum RawSecretItem {
    /// The item's service: a stored value, since changing it loses every vault's secrets.
    static let service = "Graphite community plugin secrets"

    static func add(_ data: Data, account: String) throws {
        func item(usesDataProtectionKeychain: Bool) -> CFDictionary {
            query(account: account, usesDataProtectionKeychain: usesDataProtectionKeychain)
                .merging([kSecValueData as String: data]) { _, newValue in newValue } as CFDictionary
        }
        var status = SecItemAdd(item(usesDataProtectionKeychain: true), nil)
        if status == errSecMissingEntitlement { status = SecItemAdd(item(usesDataProtectionKeychain: false), nil) }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    static func data(account: String) throws -> Data? {
        for usesDataProtectionKeychain in [true, false] {
            var item: CFTypeRef?
            let readQuery = query(account: account, usesDataProtectionKeychain: usesDataProtectionKeychain)
                .merging([kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]) { _, newValue in newValue }
            let status = SecItemCopyMatching(readQuery as CFDictionary, &item)
            if status == errSecSuccess { return item as? Data }
            guard status == errSecMissingEntitlement || status == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        }
        return nil
    }

    private static func query(account: String, usesDataProtectionKeychain: Bool) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        if usesDataProtectionKeychain { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }
}
