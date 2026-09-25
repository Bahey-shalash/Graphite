import Foundation
import CryptoKit
import zlib

public struct DecodedPNG: Sendable {
    /// Metadata-free PNG suitable for ImageIO even when optional metadata has a bad CRC.
    public let imageData: Data
    public let drawing: DrawingPayload?
    public let metadataWasDiscarded: Bool
}

public enum GraphitePNG {
    public static let maximumFileBytes = 128 * 1_048_576
    private static let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])
    // Ancillary, private, reserved bit valid, unsafe to copy after pixel modification.
    private static let chunkType = Data("grPK".utf8)
    private static let imageHeaderType = Data("IHDR".utf8)
    private static let imageDataType = Data("IDAT".utf8)
    private static let imageEndType = Data("IEND".utf8)
    /// Length, type, and checksum fields around every chunk payload.
    private static let chunkFramingBytes = 12

    public static func encode(imageData: Data, drawing: DrawingPayload) throws -> Data {
        let chunks = try parse(imageData)
        let encodedPayload = try drawing.replacingVisibleContentDigest(visibleContentDigest(chunks, in: imageData)).encoded()
        var encodedImage = signature
        encodedImage.reserveCapacity(imageData.count + encodedPayload.count + chunkFramingBytes)
        for chunk in chunks where chunk.type != chunkType {
            if chunk.type == imageEndType { encodedImage.append(makeChunk(type: chunkType, payload: encodedPayload)) }
            encodedImage.append(imageData[chunk.rawRange])
        }
        guard encodedImage.count <= maximumFileBytes else { throw GraphiteError.oversized("PNG exceeds the file budget.") }
        return encodedImage
    }

    public static func decode(_ fileData: Data) throws -> DecodedPNG {
        let chunks = try parse(fileData)
        let metadataChunks = chunks.filter { chunk in chunk.type == chunkType }
        guard !metadataChunks.isEmpty else {
            // Parsing requires every byte after the signature to belong to a chunk, so a
            // file without metadata already is the metadata-free image. Most embedded PNGs
            // are ordinary images, and this avoids copying them. A slice is copied so the
            // result is indexed from zero like every other Data the app handles.
            let imageData = fileData.startIndex == 0 ? fileData : Data(fileData)
            return DecodedPNG(imageData: imageData, drawing: nil, metadataWasDiscarded: false)
        }
        var imageWithoutMetadata = signature
        imageWithoutMetadata.reserveCapacity(fileData.count)
        for chunk in chunks where chunk.type != chunkType { imageWithoutMetadata.append(fileData[chunk.rawRange]) }
        var payload: DrawingPayload?
        if metadataChunks.count == 1, let metadataChunk = metadataChunks.first, metadataChunk.validCRC,
           let candidatePayload = DrawingPayload.decodeIfValid(fileData[metadataChunk.payloadRange]),
           isCurrent(candidatePayload.visibleContentDigest, chunks: chunks, in: fileData) {
            payload = candidatePayload
        }
        return DecodedPNG(imageData: imageWithoutMetadata, drawing: payload, metadataWasDiscarded: payload == nil)
    }

    /// A chunk located inside the file it was parsed from. Ranges index that file directly,
    /// so parsing never copies image data.
    private struct Chunk {
        let type: Data
        let payloadRange: Range<Data.Index>
        /// The whole chunk: length, type, payload, and checksum.
        let rawRange: Range<Data.Index>
        let validCRC: Bool
    }

    private static func parse(_ fileData: Data) throws -> [Chunk] {
        guard fileData.count <= maximumFileBytes, fileData.starts(with: signature) else { throw GraphiteError.invalidFile("Not a supported PNG file.") }
        // Positions are absolute indices so that a Data slice, whose first index is not
        // zero, is read correctly.
        var chunkStart = fileData.startIndex + signature.count
        var chunks: [Chunk] = []
        var ended = false
        while fileData.endIndex - chunkStart >= chunkFramingBytes {
            let length = Int(readUInt32(fileData, at: chunkStart))
            guard length <= fileData.endIndex - chunkStart - chunkFramingBytes else { throw GraphiteError.invalidFile("Truncated PNG chunk.") }
            let typeStart = chunkStart + 4
            let payloadStart = typeStart + 4
            let payloadEnd = payloadStart + length
            let type = Data(fileData[typeStart..<payloadStart])
            let valid = calculateChecksum(fileData[typeStart..<payloadEnd]) == readUInt32(fileData, at: payloadEnd)
            guard valid || type == chunkType else { throw GraphiteError.invalidFile("PNG image data is damaged.") }
            let chunkEnd = payloadEnd + 4
            chunks.append(Chunk(type: type, payloadRange: payloadStart..<payloadEnd, rawRange: chunkStart..<chunkEnd, validCRC: valid))
            chunkStart = chunkEnd
            if type == imageEndType { ended = true; break }
            guard chunks.count < 100_000 else { throw GraphiteError.oversized("PNG has too many chunks.") }
        }
        guard ended, chunkStart == fileData.endIndex, chunks.first?.type == imageHeaderType, chunks.first?.payloadRange.count == 13,
              chunks.contains(where: { chunk in chunk.type == imageDataType }) else { throw GraphiteError.invalidFile("Incomplete PNG image.") }
        return chunks
    }

    /// Chunks that only describe the image in words or record when it was saved. Every
    /// other chunk can change what a viewer shows: colour (gAMA, cHRM, sRGB, iCCP, cICP),
    /// orientation (eXIf), animation frames (acTL, fcTL, fdAT), and chunks this reader does
    /// not know. The PNG specification lets an editor that changes only those ancillary
    /// chunks copy `grPK` forward, so the digest must cover them.
    private static let descriptiveChunkTypes: Set<Data> = Set(["tEXt", "zTXt", "iTXt", "tIME"].map { type in Data(type.utf8) })
    /// Separates this digest from the earlier pixel-only digest, so a record written by
    /// this version is never accepted by the weaker check.
    private static let visibleContentDigestDomain = Data("Graphite PNG visible content, version 2".utf8)

    private static func visibleContentDigest(_ chunks: [Chunk], in fileData: Data) -> Data {
        var hash = SHA256()
        hash.update(data: visibleContentDigestDomain)
        for chunk in chunks where chunk.type != chunkType && !descriptiveChunkTypes.contains(chunk.type) {
            // The length keeps the concatenation unambiguous across chunk boundaries.
            hash.update(data: uint32Data(UInt32(chunk.payloadRange.count)))
            hash.update(data: chunk.type)
            hash.update(data: fileData[chunk.payloadRange])
        }
        return Data(hash.finalize())
    }

    /// The digest drawings saved before `visibleContentDigest` existed carry. It covers only
    /// the pixel chunks. Such drawings stay editable, and the next save upgrades them.
    private static func legacyPixelDigest(_ chunks: [Chunk], in fileData: Data) -> Data {
        let pixelChunkTypes: Set<Data> = Set(["IHDR", "PLTE", "IDAT", "tRNS"].map { type in Data(type.utf8) })
        var hash = SHA256()
        for chunk in chunks where pixelChunkTypes.contains(chunk.type) {
            hash.update(data: chunk.type); hash.update(data: fileData[chunk.payloadRange])
        }
        return Data(hash.finalize())
    }

    private static func isCurrent(_ storedDigest: Data, chunks: [Chunk], in fileData: Data) -> Bool {
        storedDigest == visibleContentDigest(chunks, in: fileData) || storedDigest == legacyPixelDigest(chunks, in: fileData)
    }

    private static func makeChunk(type: Data, payload: Data) -> Data {
        var encodedChunk = uint32Data(UInt32(payload.count))
        encodedChunk.append(type); encodedChunk.append(payload)
        encodedChunk.append(uint32Data(calculateChecksum(payload, continuing: calculateChecksum(type))))
        return encodedChunk
    }

    private static func readUInt32(_ fileData: Data, at index: Data.Index) -> UInt32 {
        fileData[index..<index + 4].reduce(0) { accumulated, byte in (accumulated << 8) | UInt32(byte) }
    }

    private static func uint32Data(_ number: UInt32) -> Data {
        Data([UInt8(truncatingIfNeeded: number >> 24), UInt8(truncatingIfNeeded: number >> 16), UInt8(truncatingIfNeeded: number >> 8), UInt8(truncatingIfNeeded: number)])
    }

    /// The PNG chunk CRC-32, which is zlib's. zlib's implementation is several times faster
    /// than a byte loop, and every chunk of every embedded PNG is checked on each render.
    /// Chunk lengths are bounded by `maximumFileBytes`, so they fit zlib's 32-bit length.
    private static func calculateChecksum(_ bytes: Data, continuing previousChecksum: UInt32 = 0) -> UInt32 {
        bytes.withUnsafeBytes { buffer in
            // zlib returns 0 rather than the running checksum for a null buffer.
            guard !buffer.isEmpty else { return previousChecksum }
            let checksum = crc32(uLong(previousChecksum), buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count))
            return UInt32(truncatingIfNeeded: checksum)
        }
    }
}
