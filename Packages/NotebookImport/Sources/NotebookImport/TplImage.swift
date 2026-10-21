import Foundation

/// Why bytes could not be read as a tpl image.
public enum TplImageError: Error, Hashable, Sendable {
    /// The bytes do not start with `tpl` and the header.
    case notATplImage
    /// The image is big-endian; every image Goodnotes writes is little-endian.
    case bigEndianImage
    case formatStringNotTerminated
    /// A value, or an array's element count, runs past the end of the image.
    case valueOutsideImage
    /// Bytes are left after the values the format string describes.
    case bytesLeftAfterValues(byteCount: Int)
}

/// An image of Troy Hanson's tpl serialisation, as Goodnotes stores an ink path: `tpl`, a flags byte (bit 0 set for
/// big-endian), the total size as a 32-bit integer, a NUL-terminated format string, then the values in the order the
/// format string gives. Values are read in that order by a caller that knows the format (`TplValueCursor`); each array
/// starts with its element count, which is checked against the bytes left before anything is allocated.
struct TplImage {
    private static let signature: [UInt8] = Array("tpl".utf8)
    private static let formatStringStart = 8
    private static let bigEndianFlag: UInt8 = 1

    let formatString: String
    let valueBytes: ArraySlice<UInt8>

    init(_ bytes: [UInt8]) throws(TplImageError) {
        guard bytes.count > Self.formatStringStart, bytes.starts(with: Self.signature) else { throw TplImageError.notATplImage }
        guard bytes[3] & Self.bigEndianFlag == 0 else { throw TplImageError.bigEndianImage }
        guard let formatEnd = bytes[Self.formatStringStart...].firstIndex(of: 0) else { throw TplImageError.formatStringNotTerminated }
        formatString = String(decoding: bytes[Self.formatStringStart..<formatEnd], as: UTF8.self)
        valueBytes = bytes[(formatEnd + 1)...]
    }

    func valueCursor() -> TplValueCursor { TplValueCursor(valueBytes) }
}

/// Reads the values of a tpl image in order. The tpl types used by Goodnotes are `v` (16-bit unsigned), `u`
/// (32-bit unsigned, which Goodnotes fills with the bits of a 32-bit float) and `f` (a 64-bit double); `A(…)` is an
/// array and `S(…)` a structure, whose members follow one another.
struct TplValueCursor {
    private let bytes: ArraySlice<UInt8>
    private var offset: Int

    init(_ bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
        offset = bytes.startIndex
    }

    mutating func uint16() throws(TplImageError) -> UInt16 { try littleEndian(UInt16.self) }

    mutating func uint32() throws(TplImageError) -> UInt32 { try littleEndian(UInt32.self) }

    /// `A(v)`: an array of 16-bit values.
    mutating func uint16Array() throws(TplImageError) -> [UInt16] {
        let count = try arrayCount(elementBytes: 2)
        var values: [UInt16] = []
        values.reserveCapacity(count)
        for _ in 0..<count { values.append(try uint16()) }
        return values
    }

    /// `A(u)`, or `A(S(u…u))` with `valuesPerElement` members: the 32-bit values of every element, one after another.
    mutating func uint32Array(valuesPerElement: Int) throws(TplImageError) -> [UInt32] {
        let valueCount = try arrayCount(elementBytes: 4 * valuesPerElement) * valuesPerElement
        var values: [UInt32] = []
        values.reserveCapacity(valueCount)
        for _ in 0..<valueCount { values.append(try uint32()) }
        return values
    }

    /// `A(f)`: an array of 64-bit values, returned as their bits.
    mutating func uint64Array() throws(TplImageError) -> [UInt64] {
        let count = try arrayCount(elementBytes: 8)
        var values: [UInt64] = []
        values.reserveCapacity(count)
        for _ in 0..<count { values.append(try littleEndian(UInt64.self)) }
        return values
    }

    /// Succeeds only when every byte of the image has been read.
    func finish() throws(TplImageError) {
        guard offset == bytes.endIndex else { throw TplImageError.bytesLeftAfterValues(byteCount: bytes.endIndex - offset) }
    }

    private mutating func arrayCount(elementBytes: Int) throws(TplImageError) -> Int {
        let count = Int(try uint32())
        guard count <= (bytes.endIndex - offset) / max(elementBytes, 1) else { throw TplImageError.valueOutsideImage }
        return count
    }

    private mutating func littleEndian<Integer: FixedWidthInteger>(_ type: Integer.Type) throws(TplImageError) -> Integer {
        guard let number = LittleEndianInteger.read(type, in: bytes, at: offset) else { throw TplImageError.valueOutsideImage }
        offset += MemoryLayout<Integer>.size
        return number
    }
}
