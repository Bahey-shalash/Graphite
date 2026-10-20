import Foundation

/// Little-endian values packed in a slice of a note's bytes, `entryCount` entries of `entryByteCount` bytes each,
/// read in place. The length is checked once, when the values are made, so a read at an entry index below
/// `entryCount` stays inside the slice; every read goes through the slice's subscript, which checks its bounds in
/// every build, so a wrong index traps instead of reading memory past the note.
struct PackedLittleEndianValues: Sendable {
    let bytes: ArraySlice<UInt8>
    let entryCount: Int
    let entryByteCount: Int

    static let empty = PackedLittleEndianValues(checkedBytes: [], entryCount: 0, entryByteCount: 1)

    /// Nil when the bytes are not exactly `entryCount` entries of `entryByteCount` bytes.
    init?(bytes: ArraySlice<UInt8>, entryCount: Int64, entryByteCount: Int) {
        guard entryCount >= 0, entryByteCount > 0, let count = Int(exactly: entryCount) else { return nil }
        let expectedByteCount = count.multipliedReportingOverflow(by: entryByteCount)
        guard !expectedByteCount.overflow, bytes.count == expectedByteCount.partialValue else { return nil }
        self.init(checkedBytes: bytes, entryCount: count, entryByteCount: entryByteCount)
    }

    private init(checkedBytes: ArraySlice<UInt8>, entryCount: Int, entryByteCount: Int) {
        bytes = checkedBytes
        self.entryCount = entryCount
        self.entryByteCount = entryByteCount
    }

    func byte(at index: Int) -> UInt8 { bytes[bytes.startIndex + index] }

    /// The `index`-th 4-byte unsigned integer.
    func uint32(at index: Int) -> UInt32 {
        let start = bytes.startIndex + 4 * index
        return (0..<4).reduce(UInt32(0)) { number, byteIndex in number | UInt32(bytes[start + byteIndex]) << (8 * UInt32(byteIndex)) }
    }

    /// The `index`-th 4-byte float, widened to `Double` exactly.
    func float(at index: Int) -> Double {
        Double(Float(bitPattern: uint32(at: index)))
    }

    /// The `index`-th 16-byte UUID, its bytes in the order stored.
    func uuid(at index: Int) -> UUID {
        let start = bytes.startIndex + 16 * index
        var uuidBytes: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &uuidBytes) { destination in
            for byteIndex in 0..<16 { destination[byteIndex] = bytes[start + byteIndex] }
        }
        return UUID(uuid: uuidBytes)
    }
}
