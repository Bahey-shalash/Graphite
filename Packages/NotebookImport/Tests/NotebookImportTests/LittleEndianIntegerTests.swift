import XCTest
@testable import NotebookImport

final class LittleEndianIntegerTests: XCTestCase {
    func testIntegersAreReadInRangeAndRefusedOutsideIt() {
        let bytes: [UInt8] = [9, 0x01, 0x02, 0x03, 0x04, 0x05]
        XCTAssertEqual(LittleEndianInteger.read(UInt32.self, in: bytes, at: 1), 0x0403_0201)
        XCTAssertEqual(LittleEndianInteger.read(UInt16.self, in: bytes[1...], at: 4), 0x0504)
        XCTAssertNil(LittleEndianInteger.read(UInt32.self, in: bytes, at: 3))
        XCTAssertNil(LittleEndianInteger.read(UInt32.self, in: bytes[1...], at: 0), "an offset before a slice's start")
        XCTAssertNil(LittleEndianInteger.read(UInt64.self, in: bytes, at: Int.max))
    }

    func testAUUIDIsMadeFromExactlySixteenBytes() {
        let bytes = [UInt8](0..<16)
        XCTAssertEqual(UUID(sixteenBytes: bytes)?.uuidString, "00010203-0405-0607-0809-0A0B0C0D0E0F")
        XCTAssertNil(UUID(sixteenBytes: bytes.dropLast()))
        XCTAssertNil(UUID(sixteenBytes: bytes + [16]))
    }
}
