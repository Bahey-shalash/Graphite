import Foundation

/// Reads little-endian integers from bytes, checking the range: the one reader every format of the import uses.
enum LittleEndianInteger {
    /// The integer of `type`'s width at `offset`; nil when it does not fit in the bytes.
    static func read<Integer: FixedWidthInteger, Bytes: RandomAccessCollection>(_ type: Integer.Type, in bytes: Bytes,
                                                                               at offset: Int) -> Integer?
        where Bytes.Element == UInt8, Bytes.Index == Int {
        let byteCount = MemoryLayout<Integer>.size
        guard offset >= bytes.startIndex, offset <= bytes.endIndex - byteCount else { return nil }
        var number: Integer = 0
        for byteIndex in 0..<byteCount { number |= Integer(bytes[offset + byteIndex]) << (8 * byteIndex) }
        return number
    }
}

extension UUID {
    /// A UUID from exactly 16 bytes in the order they are stored; nil for any other count.
    init?<Bytes: Collection>(sixteenBytes bytes: Bytes) where Bytes.Element == UInt8 {
        guard bytes.count == 16 else { return nil }
        var uuidBytes: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &uuidBytes) { destination in
            for (byteIndex, byte) in bytes.enumerated() { destination[byteIndex] = byte }
        }
        self.init(uuid: uuidBytes)
    }
}
