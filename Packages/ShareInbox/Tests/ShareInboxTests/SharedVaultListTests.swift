import XCTest
@testable import ShareInbox

final class SharedVaultListTests: XCTestCase {
    func testAListChoosesTheVaultOpenedLast() {
        let older = SharedVaultList.Vault(id: UUID(), name: "Biology", lastOpenedDate: Date(timeIntervalSince1970: 10))
        let newer = SharedVaultList.Vault(id: UUID(), name: "art", lastOpenedDate: Date(timeIntervalSince1970: 20))
        let vaultList = SharedVaultList(vaults: [older, newer])
        XCTAssertEqual(vaultList.mostRecentlyOpened, newer)
        XCTAssertEqual(vaultList.sortedByName.map(\.name), ["art", "Biology"])
    }
}
