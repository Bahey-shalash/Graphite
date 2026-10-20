import XCTest
import GraphiteApple

/// How much a vault's plugins can keep in the keychain: the stored JSON is at most 1 MiB.
/// Exactly the cap is kept, one byte over is refused with `tooLarge` before the keychain is
/// touched. Every item the tests create is removed again before they end.
final class CommunityPluginSecretStoreSizeLimitTests: XCTestCase {
    private static let capBytes = 1_048_576

    /// The JSON of one secret named "k" is `{"k":"` and `"}` around its value: 8 bytes.
    private static let jsonOverheadBytes = #"{"k":""}"#.utf8.count

    func testTheStoredSecretsAreKeptAtOneMebibyteAndRefusedOneByteOver() throws {
        let store = CommunityPluginSecretStore(vaultIdentifier: UUID())
        defer { store.removeAllSecrets() }
        let valueBytesAtCap = Self.capBytes - Self.jsonOverheadBytes

        let overCapValue = String(repeating: "a", count: valueBytesAtCap + 1)
        XCTAssertThrowsError(try store.setSecret(overCapValue, forIdentifier: "k")) { error in
            guard case CommunityPluginSecretError.tooLarge = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try store.secrets(), [:], "A refused secret is not kept.")

        let atCapValue = String(repeating: "a", count: valueBytesAtCap)
        try store.setSecret(atCapValue, forIdentifier: "k")
        XCTAssertEqual(try store.secrets()["k"]?.utf8.count, valueBytesAtCap)
    }
}
