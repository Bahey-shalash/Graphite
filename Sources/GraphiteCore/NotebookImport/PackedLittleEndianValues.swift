import Foundation

/// Little-endian values packed in a slice of a note's bytes, `entryCount` entries of `entryByteCount` bytes each,
/// read in place. The length is checked once, when the values are made, so a read at an entry index below
/// `entryCount` stays inside the slice; every read checks its range all the same, so a wrong index stops the program
/// instead of reading memory past the note.
struct PackedLittleEndianValues: Sendable {
    let bytes: ArraySlice<UInt8>

    static let empty = PackedLittleEndianValues(checkedBytes: [])

    /// Nil when the bytes are not exactly `entryCount` entries of `entryByteCount` bytes.
    init?(bytes: ArraySlice<UInt8>, entryCount: Int64, entryByteCount: Int) {
        guard entryCount >= 0, entryByteCount > 0, let count = Int(exactly: entryCount) else { return nil }
        let expectedByteCount = count.multipliedReportingOverflow(by: entryByteCount)
        guard !expectedByteCount.overflow, bytes.count == expectedByteCount.partialValue else { return nil }
        self.init(checkedBytes: bytes)
    }

    private init(checkedBytes: ArraySlice<UInt8>) {
        bytes = checkedBytes
    }

    func byte(at index: Int) -> UInt8 { bytes[bytes.startIndex + index] }

    /// The `index`-th 4-byte unsigned integer.
    func uint32(at index: Int) -> UInt32 {
        guard let number = LittleEndianInteger.read(UInt32.self, in: bytes, at: bytes.startIndex + 4 * index) else {
            preconditionFailure("entry \(index) is past the length checked when the values were made")
        }
        return number
    }

    /// The `index`-th 4-byte float, widened to `Double` exactly.
    func float(at index: Int) -> Double {
        Double(Float(bitPattern: uint32(at: index)))
    }

    /// The `index`-th 16-byte UUID, its bytes in the order stored.
    func uuid(at index: Int) -> UUID {
        let start = bytes.startIndex + 16 * index
        guard let uuid = UUID(sixteenBytes: bytes[start..<(start + 16)]) else {
            preconditionFailure("entry \(index) is past the length checked when the values were made")
        }
        return uuid
    }
}
