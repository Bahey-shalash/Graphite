import XCTest
@testable import GraphiteCore

final class KeyOrderedDictionaryTests: XCTestCase {
    func testKeysKeepTheirFirstPlaceAndALaterValueWins() {
        var dictionary = KeyOrderedDictionary<Int>()
        dictionary.setValue(1, named: "b")
        dictionary.setValue(2, named: "a")
        dictionary.setValue(3, named: "b")
        XCTAssertEqual(dictionary.keys, ["b", "a"])
        XCTAssertEqual(dictionary["b"], 3)
        XCTAssertNil(dictionary["c"])
        XCTAssertEqual(dictionary.entries.map(\.key), ["b", "a"])
        XCTAssertEqual(dictionary.entries.map(\.value), [3, 2])
    }
}
