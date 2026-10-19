import Foundation

/// Little-endian values packed in a slice of a note's bytes and read in place, at entry indices the caller has
/// checked against the slice's length.
struct PackedLittleEndianValues: Sendable {
    let bytes: ArraySlice<UInt8>

    var isEmpty: Bool { bytes.isEmpty }

    func byte(at index: Int) -> UInt8 { bytes[bytes.startIndex + index] }

    /// The `index`-th 4-byte unsigned integer.
    func uint32(at index: Int) -> UInt32 {
        bytes.withUnsafeBytes { buffer in UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: 4 * index, as: UInt32.self)) }
    }

    /// The `index`-th 4-byte float, widened to `Double` exactly.
    func float(at index: Int) -> Double {
        Double(Float(bitPattern: uint32(at: index)))
    }

    /// The `index`-th 16-byte UUID, its bytes in the order stored.
    func uuid(at index: Int) -> UUID {
        var uuidBytes: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        let start = bytes.startIndex + 16 * index
        withUnsafeMutableBytes(of: &uuidBytes) { destination in destination.copyBytes(from: bytes[start..<(start + 16)]) }
        return UUID(uuid: uuidBytes)
    }
}
