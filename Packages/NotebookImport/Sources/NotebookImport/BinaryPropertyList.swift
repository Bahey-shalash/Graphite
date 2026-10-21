import Foundation

/// A binary property list (`bplist00`) read from bytes the caller supplies. Opening it checks the trailer and the
/// offset table against the byte count; objects are then decoded one at a time, by index, when asked for. Every
/// length an object announces is checked against the bytes left in the object area before anything of that length
/// is allocated, so a damaged or hostile list fails with a typed error. Integers inside the list are big-endian.
public struct BinaryPropertyList: Sendable {
    private static let magic = Array("bplist00".utf8)
    private static let headerByteCount = 8
    private static let trailerByteCount = 32
    private static let largestIntegerByteCount = 8
    /// The marker's low four bits say this when the length follows as an integer object.
    private static let lengthFollowsInformation = 0x0F

    private let bytes: ArraySlice<UInt8>
    private let offsetByteCount: Int
    private let referenceByteCount: Int
    public let objectCount: Int
    public let topObjectIndex: Int
    /// Where the offset table starts: every object lies between the header and this offset.
    private let objectAreaEnd: Int

    public var byteCount: Int { bytes.count }

    public init(bytes: ArraySlice<UInt8>) throws(BinaryPropertyListError) {
        guard bytes.count >= Self.headerByteCount + Self.trailerByteCount,
              bytes.prefix(Self.headerByteCount).elementsEqual(Self.magic) else { throw .notBinaryPropertyList }
        let trailerStart = bytes.count - Self.trailerByteCount
        let offsetByteCount = Int(Self.unsignedBigEndian(in: bytes, at: trailerStart + 6, byteCount: 1))
        let referenceByteCount = Int(Self.unsignedBigEndian(in: bytes, at: trailerStart + 7, byteCount: 1))
        let objectCount = Self.unsignedBigEndian(in: bytes, at: trailerStart + 8, byteCount: 8)
        let topObjectIndex = Self.unsignedBigEndian(in: bytes, at: trailerStart + 16, byteCount: 8)
        let offsetTableOffset = Self.unsignedBigEndian(in: bytes, at: trailerStart + 24, byteCount: 8)
        let integerSizes = 1...Self.largestIntegerByteCount
        guard integerSizes.contains(offsetByteCount), integerSizes.contains(referenceByteCount),
              objectCount >= 1, topObjectIndex < objectCount else { throw .trailerDamaged }
        guard offsetTableOffset >= UInt64(Self.headerByteCount), offsetTableOffset <= UInt64(trailerStart),
              objectCount <= (UInt64(trailerStart) - offsetTableOffset) / UInt64(offsetByteCount) else {
            throw .offsetTableOutsideFile
        }
        self.bytes = bytes
        self.offsetByteCount = offsetByteCount
        self.referenceByteCount = referenceByteCount
        self.objectCount = Int(objectCount)
        self.topObjectIndex = Int(topObjectIndex)
        objectAreaEnd = Int(offsetTableOffset)
    }

    /// The object at this index of the offset table, its members named by index and not decoded.
    public func object(at objectIndex: Int) throws(BinaryPropertyListError) -> BinaryPropertyListObject {
        let offset = try objectOffset(of: objectIndex)
        let marker = byte(at: offset)
        let information = Int(marker & 0x0F)
        let contentStart = offset + 1
        switch marker >> 4 {
        case 0x0: return try singleton(marker: marker, objectIndex: objectIndex)
        case 0x1: return .integer(try integer(sizeExponent: information, at: contentStart, objectIndex: objectIndex))
        case 0x2: return .real(try real(sizeExponent: information, at: contentStart, objectIndex: objectIndex))
        case 0x3:
            guard information == 0x3 else { throw .objectMarkerUnknown(objectIndex: objectIndex, marker: marker) }
            return .date(secondsSince2001: try real(sizeExponent: information, at: contentStart, objectIndex: objectIndex))
        case 0x4:
            let length = try length(information: information, at: contentStart, elementByteCount: 1, objectIndex: objectIndex)
            return .data(slice(from: length.contentStart, byteCount: length.count))
        case 0x5: return .string(try asciiString(information: information, at: contentStart, objectIndex: objectIndex))
        case 0x6: return .string(try utf16String(information: information, at: contentStart, objectIndex: objectIndex))
        case 0x8: return .uid(try uid(byteCount: information + 1, at: contentStart, objectIndex: objectIndex))
        case 0xA: return .array(memberIndices: try memberIndices(information: information, at: contentStart, objectIndex: objectIndex))
        case 0xB, 0xC: return .set(memberIndices: try memberIndices(information: information, at: contentStart, objectIndex: objectIndex))
        case 0xD: return try dictionary(information: information, at: contentStart, objectIndex: objectIndex)
        default: throw .objectMarkerUnknown(objectIndex: objectIndex, marker: marker)
        }
    }

    private func objectOffset(of objectIndex: Int) throws(BinaryPropertyListError) -> Int {
        guard objectIndex >= 0, objectIndex < objectCount else {
            throw .objectIndexOutOfRange(objectIndex: objectIndex, objectCount: objectCount)
        }
        let offset = unsignedBigEndian(at: objectAreaEnd + objectIndex * offsetByteCount, byteCount: offsetByteCount)
        guard offset >= UInt64(Self.headerByteCount), offset < UInt64(objectAreaEnd) else {
            throw .objectOffsetOutsideObjects(objectIndex: objectIndex)
        }
        return Int(offset)
    }

    private func singleton(marker: UInt8, objectIndex: Int) throws(BinaryPropertyListError) -> BinaryPropertyListObject {
        switch marker {
        case 0x00: return .null
        case 0x08: return .boolean(false)
        case 0x09: return .boolean(true)
        default: throw .objectMarkerUnknown(objectIndex: objectIndex, marker: marker)
        }
    }

    /// An integer of 2^sizeExponent bytes: 1, 2 and 4 bytes are unsigned, 8 and 16 bytes signed. Foundation writes
    /// some small numbers in 16 bytes; one is read when its value fits in 64 bits.
    private func integer(sizeExponent: Int, at position: Int, objectIndex: Int) throws(BinaryPropertyListError) -> Int64 {
        guard sizeExponent <= 3 else {
            guard sizeExponent == 4 else { throw .objectMarkerUnknown(objectIndex: objectIndex, marker: UInt8(0x10 | sizeExponent)) }
            return try wideInteger(at: position, objectIndex: objectIndex)
        }
        let byteCount = 1 << sizeExponent
        try requireBytes(byteCount, at: position, objectIndex: objectIndex)
        let unsigned = unsignedBigEndian(at: position, byteCount: byteCount)
        return byteCount == Self.largestIntegerByteCount ? Int64(bitPattern: unsigned) : Int64(unsigned)
    }

    /// A 16-byte integer whose high 8 bytes only extend the sign of its low 8 bytes.
    private func wideInteger(at position: Int, objectIndex: Int) throws(BinaryPropertyListError) -> Int64 {
        let wideByteCount = 2 * Self.largestIntegerByteCount
        try requireBytes(wideByteCount, at: position, objectIndex: objectIndex)
        let high = unsignedBigEndian(at: position, byteCount: Self.largestIntegerByteCount)
        let low = Int64(bitPattern: unsignedBigEndian(at: position + Self.largestIntegerByteCount, byteCount: Self.largestIntegerByteCount))
        guard high == (low < 0 ? UInt64.max : 0) else { throw .integerTooWide(objectIndex: objectIndex, byteCount: wideByteCount) }
        return low
    }

    private func real(sizeExponent: Int, at position: Int, objectIndex: Int) throws(BinaryPropertyListError) -> Double {
        switch sizeExponent {
        case 2:
            try requireBytes(4, at: position, objectIndex: objectIndex)
            return Double(Float(bitPattern: UInt32(unsignedBigEndian(at: position, byteCount: 4))))
        case 3:
            try requireBytes(8, at: position, objectIndex: objectIndex)
            return Double(bitPattern: unsignedBigEndian(at: position, byteCount: 8))
        default:
            throw .objectMarkerUnknown(objectIndex: objectIndex, marker: UInt8(0x20 | sizeExponent))
        }
    }

    private func uid(byteCount: Int, at position: Int, objectIndex: Int) throws(BinaryPropertyListError) -> Int {
        guard byteCount <= Self.largestIntegerByteCount else { throw .integerTooWide(objectIndex: objectIndex, byteCount: byteCount) }
        try requireBytes(byteCount, at: position, objectIndex: objectIndex)
        let unsigned = unsignedBigEndian(at: position, byteCount: byteCount)
        guard unsigned <= UInt64(Int.max) else { throw .integerTooWide(objectIndex: objectIndex, byteCount: byteCount) }
        return Int(unsigned)
    }

    private func asciiString(information: Int, at position: Int, objectIndex: Int) throws(BinaryPropertyListError) -> String {
        let length = try length(information: information, at: position, elementByteCount: 1, objectIndex: objectIndex)
        let characters = slice(from: length.contentStart, byteCount: length.count)
        guard characters.allSatisfy({ character in character < 0x80 }) else { throw .stringNotDecodable(objectIndex: objectIndex) }
        return String(decoding: characters, as: Unicode.ASCII.self)
    }

    private func utf16String(information: Int, at position: Int, objectIndex: Int) throws(BinaryPropertyListError) -> String {
        let length = try length(information: information, at: position, elementByteCount: 2, objectIndex: objectIndex)
        var codeUnits: [UInt16] = []
        codeUnits.reserveCapacity(length.count)
        for unitIndex in 0..<length.count {
            codeUnits.append(UInt16(unsignedBigEndian(at: length.contentStart + 2 * unitIndex, byteCount: 2)))
        }
        var scalars = String.UnicodeScalarView()
        var iterator = codeUnits.makeIterator()
        var decoder = UTF16()
        while true {
            switch decoder.decode(&iterator) {
            case .scalarValue(let scalar): scalars.append(scalar)
            case .emptyInput: return String(scalars)
            case .error: throw .stringNotDecodable(objectIndex: objectIndex)
            }
        }
    }

    private func memberIndices(information: Int, at position: Int, objectIndex: Int) throws(BinaryPropertyListError) -> [Int] {
        let length = try length(information: information, at: position, elementByteCount: referenceByteCount, objectIndex: objectIndex)
        return references(count: length.count, at: length.contentStart)
    }

    private func dictionary(information: Int, at position: Int, objectIndex: Int) throws(BinaryPropertyListError) -> BinaryPropertyListObject {
        let length = try length(information: information, at: position, elementByteCount: 2 * referenceByteCount, objectIndex: objectIndex)
        let keyIndices = references(count: length.count, at: length.contentStart)
        let valueIndices = references(count: length.count, at: length.contentStart + length.count * referenceByteCount)
        return .dictionary(keyIndices: keyIndices, valueIndices: valueIndices)
    }

    /// The element count an object announces, in its marker or in the integer object after it, and where its contents
    /// start. The contents are checked to fit in the object area before the caller reserves anything for them.
    private func length(information: Int, at position: Int, elementByteCount: Int,
                        objectIndex: Int) throws(BinaryPropertyListError) -> (count: Int, contentStart: Int) {
        var count = information
        var contentStart = position
        if information == Self.lengthFollowsInformation {
            try requireBytes(1, at: position, objectIndex: objectIndex)
            let lengthMarker = byte(at: position)
            guard lengthMarker >> 4 == 0x1 else { throw .objectMarkerUnknown(objectIndex: objectIndex, marker: lengthMarker) }
            let sizeExponent = Int(lengthMarker & 0x0F)
            let announcedCount = try integer(sizeExponent: sizeExponent, at: position + 1, objectIndex: objectIndex)
            guard announcedCount >= 0 else { throw .objectTruncated(objectIndex: objectIndex) }
            count = Int(announcedCount)
            contentStart = position + 1 + (1 << sizeExponent)
        }
        guard contentStart <= objectAreaEnd, count <= (objectAreaEnd - contentStart) / elementByteCount else {
            throw .objectTruncated(objectIndex: objectIndex)
        }
        return (count, contentStart)
    }

    /// Object references of the list's reference size, from a range the caller checked; a reference too large for
    /// `Int` is clamped, and `object(at:)` refuses it as out of range.
    private func references(count: Int, at position: Int) -> [Int] {
        var indices: [Int] = []
        indices.reserveCapacity(count)
        for referenceIndex in 0..<count {
            let reference = unsignedBigEndian(at: position + referenceIndex * referenceByteCount, byteCount: referenceByteCount)
            indices.append(Int(clamping: reference))
        }
        return indices
    }

    private func requireBytes(_ byteCount: Int, at position: Int, objectIndex: Int) throws(BinaryPropertyListError) {
        guard position <= objectAreaEnd, byteCount <= objectAreaEnd - position else { throw .objectTruncated(objectIndex: objectIndex) }
    }

    private func byte(at offset: Int) -> UInt8 { bytes[bytes.startIndex + offset] }

    private func slice(from offset: Int, byteCount: Int) -> ArraySlice<UInt8> {
        bytes[(bytes.startIndex + offset)..<(bytes.startIndex + offset + byteCount)]
    }

    private func unsignedBigEndian(at offset: Int, byteCount: Int) -> UInt64 {
        Self.unsignedBigEndian(in: bytes, at: offset, byteCount: byteCount)
    }

    /// A big-endian unsigned integer of 1 to 8 bytes at an offset from the start of `bytes` that the caller checked.
    private static func unsignedBigEndian(in bytes: ArraySlice<UInt8>, at offset: Int, byteCount: Int) -> UInt64 {
        var number: UInt64 = 0
        for byteIndex in 0..<byteCount { number = number << 8 | UInt64(bytes[bytes.startIndex + offset + byteIndex]) }
        return number
    }
}
