import XCTest
import Security
@testable import GraphiteApple

/// The one keychain item type behind the plugins' secrets, on a service of its own so the test
/// touches no item Graphite keeps.
final class KeychainGenericPasswordItemTests: XCTestCase {
    func testAnItemIsWrittenOverReadBackAndRemoved() {
        let item = KeychainGenericPasswordItem(service: "Graphite keychain item test \(UUID().uuidString)", account: "password")
        defer { item.delete() }

        XCTAssertEqual(item.read().status, errSecItemNotFound, "No item yet.")
        XCTAssertEqual(item.write(Data("first".utf8)), errSecSuccess, "The first write adds the item.")
        XCTAssertEqual(item.write(Data("second".utf8)), errSecSuccess, "A later write updates it.")
        let stored = item.read()
        XCTAssertEqual(stored.status, errSecSuccess)
        XCTAssertEqual(stored.data, Data("second".utf8))
        XCTAssertEqual(item.delete(), errSecSuccess)
        XCTAssertEqual(item.delete(), errSecItemNotFound, "Removing a missing item says so.")
    }

    func testItemsOfOneServiceAreToldApartByAccount() {
        let service = "Graphite keychain item test \(UUID().uuidString)"
        let firstItem = KeychainGenericPasswordItem(service: service, account: "first")
        let secondItem = KeychainGenericPasswordItem(service: service, account: "second")
        defer {
            firstItem.delete()
            secondItem.delete()
        }

        XCTAssertEqual(firstItem.write(Data("one".utf8)), errSecSuccess)
        XCTAssertEqual(secondItem.read().status, errSecItemNotFound)
        XCTAssertEqual(secondItem.write(Data("two".utf8)), errSecSuccess)
        XCTAssertEqual(firstItem.read().data, Data("one".utf8))
    }
}
