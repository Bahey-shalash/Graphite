import Foundation
import zlib

/// One ZIP entry handed to a consumer in pieces (`ZipArchive.copy(_:chunkByteCount:to:)`), with its size and CRC-32
/// counted as it goes and checked by `finish()`. A deflated entry is inflated through one buffer of the piece size, and
/// a stream that would produce more than the entry's recorded size is refused as soon as it does.
struct ZipEntryPieces<DestinationError: Error> {
    typealias Consume = (UnsafeRawBufferPointer) throws(DestinationError) -> Void

    private let entry: ZipArchive.Entry
    private var byteCount = 0
    private var checksum: UInt32 = 0

    init(entry: ZipArchive.Entry) {
        self.entry = entry
    }

    /// A stored entry's bytes, in slices of the archive.
    mutating func handOver(_ stored: UnsafeRawBufferPointer, pieceByteCount: Int, to consume: Consume) throws(ZipEntryCopyError<DestinationError>) {
        guard stored.count == entry.uncompressedByteCount else { throw .archive(.entryDataDamaged(name: entry.name)) }
        var start = 0
        while start < stored.count {
            let end = min(start + pieceByteCount, stored.count)
            try take(UnsafeRawBufferPointer(rebasing: stored[start..<end]), to: consume)
            start = end
        }
    }

    mutating func inflate(_ compressed: UnsafeRawBufferPointer, pieceByteCount: Int, to consume: Consume) throws(ZipEntryCopyError<DestinationError>) {
        let piece = UnsafeMutableRawBufferPointer.allocate(byteCount: pieceByteCount, alignment: 1)
        defer { piece.deallocate() }
        var stream = z_stream()
        guard inflateInit2_(&stream, ZipArchive.rawDeflateWindowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw .archive(.entryDataDamaged(name: entry.name))
        }
        defer { inflateEnd(&stream) }
        stream.next_in = UnsafeMutablePointer(mutating: compressed.baseAddress?.assumingMemoryBound(to: Bytef.self))
        stream.avail_in = uInt(compressed.count)
        var status = Z_OK
        while status != Z_STREAM_END {
            stream.next_out = piece.baseAddress?.assumingMemoryBound(to: Bytef.self)
            stream.avail_out = uInt(piece.count)
            status = zlib.inflate(&stream, Z_NO_FLUSH)
            let produced = piece.count - Int(stream.avail_out)
            // Z_BUF_ERROR: no progress with all the input given, so the stream is cut short.
            guard status == Z_OK || status == Z_STREAM_END, produced > 0 || status == Z_STREAM_END else {
                throw .archive(.entryDataDamaged(name: entry.name))
            }
            guard byteCount + produced <= entry.uncompressedByteCount else { throw .archive(.entryDataDamaged(name: entry.name)) }
            if produced > 0 { try take(UnsafeRawBufferPointer(rebasing: piece[0..<produced]), to: consume) }
        }
    }

    /// Checks the size and CRC-32 the directory records, once every piece is handed over.
    func finish() throws(ZipEntryCopyError<DestinationError>) {
        guard byteCount == entry.uncompressedByteCount else { throw .archive(.entryDataDamaged(name: entry.name)) }
        guard checksum == entry.checksum else { throw .archive(.checksumMismatch(name: entry.name)) }
    }

    private mutating func take(_ piece: UnsafeRawBufferPointer, to consume: Consume) throws(ZipEntryCopyError<DestinationError>) {
        byteCount += piece.count
        checksum = ZipArchive.checksum(of: piece, continuing: checksum)
        do throws(DestinationError) { try consume(piece) } catch { throw .destination(error) }
    }
}
