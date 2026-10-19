import Foundation

/// Why a compressed payload in Apple's LZ4 framing could not be decoded.
public enum AppleLZ4Error: Error, Hashable, Sendable {
    case blockKindNotKnown
    /// A block header or block runs past the end of the payload.
    case blockOutsidePayload
    case decodedSizeOverLimit(limitBytes: Int)
    case endMarkerMissing
    /// The LZ4 sequences do not fit the block or decode to another size than the block header declares.
    case blockDamaged
}

/// Decodes Apple's LZ4 framing (the Compression framework's `COMPRESSION_LZ4`), in which Goodnotes stores ink paths
/// and rich text: `bv41` blocks of raw LZ4 with their decoded and encoded sizes, `bv4-` stored blocks with their size,
/// and `bv4$` at the end. Every size is checked before it is used and the total is bounded, so a damaged payload
/// fails instead of growing.
enum AppleLZ4Decoder {
    private static let compressedBlockMagic: [UInt8] = Array("bv41".utf8)
    private static let storedBlockMagic: [UInt8] = Array("bv4-".utf8)
    private static let endMagic: [UInt8] = Array("bv4$".utf8)
    private static let magicBytes = 4
    private static let minimumMatchBytes = 4
    private static let extendedLengthMarker = 15

    static func decode(_ payload: ArraySlice<UInt8>, maximumDecodedBytes: Int) throws(AppleLZ4Error) -> [UInt8] {
        var decoded: [UInt8] = []
        var offset = payload.startIndex
        while payload.endIndex - offset >= magicBytes {
            let magic = Array(payload[offset..<(offset + magicBytes)])
            if magic == endMagic { return decoded }
            let isCompressed = magic == compressedBlockMagic
            guard isCompressed || magic == storedBlockMagic else { throw AppleLZ4Error.blockKindNotKnown }
            let headerBytes = isCompressed ? 12 : 8
            guard payload.endIndex - offset >= headerBytes else { throw AppleLZ4Error.blockOutsidePayload }
            let decodedSize = Int(uint32(payload, at: offset + 4))
            let encodedSize = isCompressed ? Int(uint32(payload, at: offset + 8)) : decodedSize
            let blockStart = offset + headerBytes
            guard encodedSize <= payload.endIndex - blockStart else { throw AppleLZ4Error.blockOutsidePayload }
            guard decodedSize <= maximumDecodedBytes - decoded.count else {
                throw AppleLZ4Error.decodedSizeOverLimit(limitBytes: maximumDecodedBytes)
            }
            let block = payload[blockStart..<(blockStart + encodedSize)]
            if isCompressed {
                try decodeBlock(block, decodedSize: decodedSize, appendingTo: &decoded)
            } else {
                decoded.append(contentsOf: block)
            }
            offset = blockStart + encodedSize
        }
        throw AppleLZ4Error.endMarkerMissing
    }

    /// One raw LZ4 block: sequences of literals and a back-reference, the last sequence without one. A
    /// back-reference reaches only into this block's output, and the output must be exactly `decodedSize` bytes.
    private static func decodeBlock(_ block: ArraySlice<UInt8>, decodedSize: Int, appendingTo decoded: inout [UInt8]) throws(AppleLZ4Error) {
        let blockStart = decoded.count
        let blockEnd = blockStart + decodedSize
        decoded.reserveCapacity(blockEnd)
        var offset = block.startIndex
        while offset < block.endIndex {
            let token = Int(block[offset])
            offset += 1
            let literalLength = try sequenceLength(startingWith: token >> 4, in: block, at: &offset)
            guard literalLength <= block.endIndex - offset, literalLength <= blockEnd - decoded.count else { throw AppleLZ4Error.blockDamaged }
            decoded.append(contentsOf: block[offset..<(offset + literalLength)])
            offset += literalLength
            if offset >= block.endIndex { break }
            guard block.endIndex - offset >= 2 else { throw AppleLZ4Error.blockDamaged }
            let matchDistance = Int(block[offset]) | Int(block[offset + 1]) << 8
            offset += 2
            let matchLength = try sequenceLength(startingWith: token & 0x0F, in: block, at: &offset) + minimumMatchBytes
            let matchStart = decoded.count - matchDistance
            guard matchDistance > 0, matchStart >= blockStart, matchLength <= blockEnd - decoded.count else { throw AppleLZ4Error.blockDamaged }
            // Byte by byte: a match may overlap the bytes it is producing.
            for copiedIndex in 0..<matchLength { decoded.append(decoded[matchStart + copiedIndex]) }
        }
        guard decoded.count == blockEnd else { throw AppleLZ4Error.blockDamaged }
    }

    /// A literal or match length: the token's four bits, extended by bytes of 255 while the length is 15.
    private static func sequenceLength(startingWith tokenLength: Int, in block: ArraySlice<UInt8>, at offset: inout Int) throws(AppleLZ4Error) -> Int {
        var length = tokenLength
        guard length == extendedLengthMarker else { return length }
        while true {
            guard offset < block.endIndex else { throw AppleLZ4Error.blockDamaged }
            let extra = Int(block[offset])
            offset += 1
            length += extra
            if extra != 255 { return length }
        }
    }

    private static func uint32(_ bytes: ArraySlice<UInt8>, at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { number, byteIndex in number | UInt32(bytes[offset + byteIndex]) << (8 * UInt32(byteIndex)) }
    }
}
