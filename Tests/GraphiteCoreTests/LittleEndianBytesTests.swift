import XCTest
@testable import GraphiteCore

/// CC-IMPORT-03: the archive's little-endian reads relied on each caller's range check and were unchecked in release
/// builds; a read outside the buffer is now a typed error.
final class LittleEndianBytesTests: XCTestCase {
    func testReadsOutsideTheBufferFailWithATypedError() throws {
        let bytes: [UInt8] = [1, 2, 3, 4, 5]
        try bytes.withUnsafeBytes { buffer in
            let reader = LittleEndianBytes(buffer)
            XCTAssertEqual(try? reader.uint32(at: 1), 0x0504_0302) // in range: a value
            for (offset, byteCount) in [(2, 4), (4, 2), (-1, 2), (Int.max, 4)] {
                XCTAssertThrowsError(try byteCount == 4 ? Int(reader.uint32(at: offset)) : Int(reader.uint16(at: offset))) { error in
                    XCTAssertEqual(error as? ZipArchiveError, .readOutsideArchive(offset: offset))
                }
            }
            XCTAssertThrowsError(try reader.slice(3..<9)) { error in XCTAssertEqual(error as? ZipArchiveError, .readOutsideArchive(offset: 3)) }
        }
    }
}
