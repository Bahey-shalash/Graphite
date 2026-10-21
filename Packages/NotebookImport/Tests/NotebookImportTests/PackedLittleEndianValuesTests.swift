import XCTest
@testable import NotebookImport

/// CC-IMPORT-03: packed arrays took any slice and relied on every caller to check its length before reading with
/// unchecked loads; the length is now checked once, when the values are made.
final class PackedLittleEndianValuesTests: XCTestCase {
    func testValuesAreMadeOnlyFromExactlyTheDeclaredEntries() throws {
        let bytes: [UInt8] = [1, 0, 0, 0, 0, 0, 0x80, 0x3F]
        let values = try XCTUnwrap(PackedLittleEndianValues(bytes: bytes[...], entryCount: 2, entryByteCount: 4))
        XCTAssertEqual(values.uint32(at: 0), 1)
        XCTAssertEqual(values.float(at: 1), 1)
        XCTAssertEqual(values.bytes.count, 8)
        XCTAssertNil(PackedLittleEndianValues(bytes: bytes[...], entryCount: 3, entryByteCount: 4))
        XCTAssertNil(PackedLittleEndianValues(bytes: bytes[...], entryCount: 1, entryByteCount: 4))
        XCTAssertNil(PackedLittleEndianValues(bytes: bytes[...], entryCount: -1, entryByteCount: 4))
        XCTAssertNil(PackedLittleEndianValues(bytes: bytes[...], entryCount: Int64.max, entryByteCount: 16))
        XCTAssertNil(PackedLittleEndianValues(bytes: bytes[...], entryCount: 8, entryByteCount: 0))
    }

    func testValuesReadFromASliceStartAtTheSlice() throws {
        let bytes: [UInt8] = [9, 9, 2, 0, 0, 0]
        let values = try XCTUnwrap(PackedLittleEndianValues(bytes: bytes[2...], entryCount: 1, entryByteCount: 4))
        XCTAssertEqual(values.uint32(at: 0), 2)
        XCTAssertTrue(PackedLittleEndianValues.empty.bytes.isEmpty)
    }
}
