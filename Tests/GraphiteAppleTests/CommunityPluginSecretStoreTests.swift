import XCTest
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
        XCTAssertEqual(firstStore.secrets(), ["token": "first-value", "other": "other-value"])
        XCTAssertEqual(secondStore.secrets(), ["token": "second-value"])
        try firstStore.setSecret("", forIdentifier: "other")
        XCTAssertEqual(firstStore.secrets(), ["token": "first-value"], "An empty secret removes it, as in Obsidian.")
        firstStore.removeAllSecrets()
        XCTAssertEqual(firstStore.secrets(), [:])
        XCTAssertEqual(secondStore.secrets(), ["token": "second-value"])
    }
}
