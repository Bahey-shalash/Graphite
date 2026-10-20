import Foundation
import zlib

/// Why a ZIP archive or one of its entries could not be read.
public enum ZipArchiveError: Error, Hashable, Sendable {
    /// No end-of-central-directory record: the bytes are not a ZIP archive, or its end is cut off.
    case endOfCentralDirectoryMissing
    /// The archive needs ZIP64 records, which notebooks do not use and this reader does not read.
    case zip64NotSupported
    /// The central directory lies outside the archive or does not hold the entries it announces.
    case centralDirectoryDamaged
    case entryMissing(name: String)
    case entryEncrypted(name: String)
    case compressionMethodNotSupported(name: String, method: UInt16)
    case entryTooLarge(name: String, limitBytes: Int)
    /// The entry declares more bytes than deflate can produce from its compressed size: it is damaged, and is refused
    /// before anything of the declared size is allocated.
    case compressionRatioImpossible(name: String)
    /// The entry's local header or data lies outside the archive.
    case entryDataOutsideArchive(name: String)
    /// The deflate stream is damaged, or does not decode to the size the directory records.
    case entryDataDamaged(name: String)
    case checksumMismatch(name: String)
    /// A read that the directory's own checks should have kept inside the archive went past it.
    case readOutsideArchive(offset: Int)
}

/// Why copying a ZIP entry out stopped: the archive's damage, or the destination's own error.
public enum ZipEntryCopyError<DestinationError: Error>: Error {
    case archive(ZipArchiveError)
    case destination(DestinationError)
}

/// The entries of a ZIP archive, read from bytes the caller supplies (memory-mapped for a large file), so that only
/// the entries asked for are ever decompressed and nothing else of the archive is copied. Stored and deflated entries
/// are read; encryption, ZIP64 and other compression methods are refused by name. When two entries share a name the
/// later one is read, as Python's `zipfile` does.
///
/// A notebook's records are read whole (`contents(of:)`). Its attachments, which can be large, are read without a copy
/// when stored (`data(of:)`, a slice of the caller's bytes) or copied out in pieces (`copy(_:chunkByteCount:to:)`).
public struct ZipArchive: Sendable {
    /// The piece size of `copy(_:chunkByteCount:to:)`: the only buffer a deflated entry's copy allocates.
    public static let standardCopyChunkByteCount = 256 * 1024

    public struct Entry: Sendable, Equatable {
        public let name: String
        public let compressionMethod: UInt16
        public let compressedByteCount: Int
        public let uncompressedByteCount: Int
        let isEncrypted: Bool
        let checksum: UInt32
        let localHeaderOffset: Int
    }

    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4B50
    private static let centralDirectorySignature: UInt32 = 0x0201_4B50
    private static let localHeaderSignature: UInt32 = 0x0403_4B50
    private static let endOfCentralDirectoryBytes = 22
    private static let centralDirectoryEntryBytes = 46
    private static let localHeaderBytes = 30
    private static let maximumCommentBytes = 65_535
    static let storedMethod: UInt16 = 0
    static let deflateMethod: UInt16 = 8
    private static let encryptedFlag: UInt16 = 1
    /// Deflate expands at most about 1,032 times (a run of one byte coded as length-258 matches), so a larger ratio
    /// is a damaged or hostile entry; the slack covers the few bytes of a tiny stream's header.
    private static let maximumDeflateExpansion = 1_032
    private static let deflateExpansionSlackBytes = 1_024
    /// Raw deflate, with no zlib header or checksum: the window size negated.
    static let rawDeflateWindowBits: Int32 = -15

    private let archiveBytes: Data
    private let limits: NotebookImportLimits
    /// Every entry in central-directory order.
    public let entries: [Entry]
    private let entryIndexByName: [String: Int]

    public init(archiveBytes: Data, limits: NotebookImportLimits) throws(ZipArchiveError) {
        self.archiveBytes = archiveBytes
        self.limits = limits
        let directory = try archiveBytes.withUnsafeBytes { bytes in
            Result { () throws(ZipArchiveError) in try Self.readCentralDirectory(LittleEndianBytes(bytes)) }
        }.get()
        entries = directory
        var indexByName: [String: Int] = [:]
        for (entryIndex, entry) in directory.enumerated() { indexByName[entry.name] = entryIndex }
        entryIndexByName = indexByName
    }

    public func entry(named name: String) -> Entry? { // nil when the archive has no entry of that name
        entryIndexByName[name].map { entryIndex in entries[entryIndex] }
    }

    public func contents(ofEntryNamed name: String) throws(ZipArchiveError) -> [UInt8] {
        guard let entry = entry(named: name) else { throw ZipArchiveError.entryMissing(name: name) }
        return try contents(of: entry)
    }

    /// The entry's uncompressed bytes, checked against the size and CRC-32 the directory records.
    public func contents(of entry: Entry) throws(ZipArchiveError) -> [UInt8] {
        try checkReadable(entry)
        let contents = try archiveBytes.withUnsafeBytes { rawBytes in
            Result { () throws(ZipArchiveError) in try Self.uncompressedBytes(of: entry, in: LittleEndianBytes(rawBytes)) }
        }.get()
        guard Self.checksum(of: contents) == entry.checksum else { throw ZipArchiveError.checksumMismatch(name: entry.name) }
        return contents
    }

    /// The entry's uncompressed bytes, checked as `contents(of:)` checks them. A stored entry is a slice of the
    /// archive's bytes, not a copy, so its indices start where it lies in the archive; a deflated one is inflated in
    /// pieces into one buffer of its recorded size, so it is held once.
    public func data(of entry: Entry) throws(ZipArchiveError) -> Data {
        try checkReadable(entry)
        guard entry.compressionMethod == Self.storedMethod else { return try inflatedData(of: entry) }
        let range = try archiveBytes.withUnsafeBytes { rawBytes in
            Result { () throws(ZipArchiveError) -> Range<Int> in
                let bytes = LittleEndianBytes(rawBytes)
                let stored = try Self.storedBytes(of: entry, in: bytes)
                guard stored.count == entry.uncompressedByteCount else { throw ZipArchiveError.entryDataDamaged(name: entry.name) }
                guard Self.checksum(of: stored) == entry.checksum else { throw ZipArchiveError.checksumMismatch(name: entry.name) }
                let start = rawBytes.baseAddress.map { base in stored.baseAddress.map { address in address - base } ?? 0 } ?? 0
                return start..<(start + stored.count)
            }
        }.get()
        return archiveBytes[(archiveBytes.startIndex + range.lowerBound)..<(archiveBytes.startIndex + range.upperBound)]
    }

    /// Hands the entry's uncompressed bytes to `consume` in pieces of at most `chunkByteCount` bytes, in order: a stored
    /// entry as slices of the archive's bytes, a deflated one through one buffer of that size. The size and CRC-32 are
    /// known to match only at the end, so the destination must not be used until this returns without an error.
    public func copy<DestinationError: Error>(_ entry: Entry, chunkByteCount: Int = standardCopyChunkByteCount,
                                               to consume: (UnsafeRawBufferPointer) throws(DestinationError) -> Void)
        throws(ZipEntryCopyError<DestinationError>) {
        do throws(ZipArchiveError) { try checkReadable(entry) } catch { throw .archive(error) }
        let pieceByteCount = max(chunkByteCount, 1)
        try archiveBytes.withUnsafeBytes { rawBytes in
            Result { () throws(ZipEntryCopyError<DestinationError>) in
                let stored: UnsafeRawBufferPointer
                do throws(ZipArchiveError) { stored = try Self.storedBytes(of: entry, in: LittleEndianBytes(rawBytes)) } catch { throw .archive(error) }
                var pieces = ZipEntryPieces<DestinationError>(entry: entry)
                switch entry.compressionMethod {
                case Self.storedMethod: try pieces.handOver(stored, pieceByteCount: pieceByteCount, to: consume)
                case Self.deflateMethod: try pieces.inflate(stored, pieceByteCount: pieceByteCount, to: consume)
                default: throw .archive(.compressionMethodNotSupported(name: entry.name, method: entry.compressionMethod))
                }
                try pieces.finish()
            }
        }.get()
    }

    private func inflatedData(of entry: Entry) throws(ZipArchiveError) -> Data {
        var data = Data(capacity: entry.uncompressedByteCount)
        do throws(ZipEntryCopyError<Never>) {
            try copy(entry) { piece in data.append(contentsOf: piece) }
        } catch {
            switch error {
            case .archive(let archiveError): throw archiveError
            case .destination(let impossible): switch impossible {}
            }
        }
        return data
    }

    /// Refuses an entry before anything of it is read: encrypted, larger than the limit, or claiming more than deflate
    /// can produce from its compressed size.
    private func checkReadable(_ entry: Entry) throws(ZipArchiveError) {
        guard !entry.isEncrypted else { throw ZipArchiveError.entryEncrypted(name: entry.name) }
        guard entry.uncompressedByteCount <= limits.maximumEntryBytes else {
            throw ZipArchiveError.entryTooLarge(name: entry.name, limitBytes: limits.maximumEntryBytes)
        }
        guard entry.compressionMethod != Self.deflateMethod
            || entry.uncompressedByteCount <= entry.compressedByteCount * Self.maximumDeflateExpansion + Self.deflateExpansionSlackBytes else {
            throw ZipArchiveError.compressionRatioImpossible(name: entry.name)
        }
    }

    private static func uncompressedBytes(of entry: Entry, in bytes: LittleEndianBytes) throws(ZipArchiveError) -> [UInt8] {
        let storedBytes = try storedBytes(of: entry, in: bytes)
        switch entry.compressionMethod {
        case storedMethod:
            guard storedBytes.count == entry.uncompressedByteCount else { throw ZipArchiveError.entryDataDamaged(name: entry.name) }
            return [UInt8](storedBytes)
        case deflateMethod:
            return try inflate(storedBytes, expectedByteCount: entry.uncompressedByteCount, entryName: entry.name)
        default:
            throw ZipArchiveError.compressionMethodNotSupported(name: entry.name, method: entry.compressionMethod)
        }
    }

    private static func readCentralDirectory(_ bytes: LittleEndianBytes) throws(ZipArchiveError) -> [Entry] {
        let endRecord = try endOfCentralDirectoryOffset(bytes)
        let entryCount = Int(try bytes.uint16(at: endRecord + 10))
        let directoryByteCount = Int(try bytes.uint32(at: endRecord + 12))
        let directoryOffset = Int(try bytes.uint32(at: endRecord + 16))
        guard entryCount != 0xFFFF, directoryByteCount != 0xFFFF_FFFF, directoryOffset != 0xFFFF_FFFF else {
            throw ZipArchiveError.zip64NotSupported
        }
        guard directoryOffset + directoryByteCount <= endRecord,
              entryCount * centralDirectoryEntryBytes <= directoryByteCount else { throw ZipArchiveError.centralDirectoryDamaged }
        var entries: [Entry] = []
        entries.reserveCapacity(entryCount)
        var offset = directoryOffset
        let directoryEnd = directoryOffset + directoryByteCount
        for _ in 0..<entryCount {
            let (entry, nextOffset) = try centralDirectoryEntry(at: offset, end: directoryEnd, in: bytes)
            entries.append(entry)
            offset = nextOffset
        }
        return entries
    }

    /// The last end-of-central-directory signature whose comment ends exactly at the end of the archive.
    private static func endOfCentralDirectoryOffset(_ bytes: LittleEndianBytes) throws(ZipArchiveError) -> Int {
        guard bytes.count >= endOfCentralDirectoryBytes else { throw ZipArchiveError.endOfCentralDirectoryMissing }
        let latestStart = bytes.count - endOfCentralDirectoryBytes
        let earliestStart = max(0, latestStart - maximumCommentBytes)
        for candidate in stride(from: latestStart, through: earliestStart, by: -1) {
            guard try bytes.uint32(at: candidate) == endOfCentralDirectorySignature else { continue }
            if candidate + endOfCentralDirectoryBytes + Int(try bytes.uint16(at: candidate + 20)) == bytes.count { return candidate }
        }
        throw ZipArchiveError.endOfCentralDirectoryMissing
    }

    private static func centralDirectoryEntry(at offset: Int, end: Int, in bytes: LittleEndianBytes) throws(ZipArchiveError) -> (Entry, Int) {
        guard offset + centralDirectoryEntryBytes <= end, try bytes.uint32(at: offset) == centralDirectorySignature else {
            throw ZipArchiveError.centralDirectoryDamaged
        }
        let flags = try bytes.uint16(at: offset + 8)
        let nameByteCount = Int(try bytes.uint16(at: offset + 28))
        let extraByteCount = Int(try bytes.uint16(at: offset + 30))
        let commentByteCount = Int(try bytes.uint16(at: offset + 32))
        let nameStart = offset + centralDirectoryEntryBytes
        let nextOffset = nameStart + nameByteCount + extraByteCount + commentByteCount
        guard nextOffset <= end else { throw ZipArchiveError.centralDirectoryDamaged }
        let compressedByteCount = try bytes.uint32(at: offset + 20), uncompressedByteCount = try bytes.uint32(at: offset + 24)
        let localHeaderOffset = try bytes.uint32(at: offset + 42)
        guard compressedByteCount != 0xFFFF_FFFF, uncompressedByteCount != 0xFFFF_FFFF, localHeaderOffset != 0xFFFF_FFFF else {
            throw ZipArchiveError.zip64NotSupported
        }
        let nameBytes = try bytes.slice(nameStart..<(nameStart + nameByteCount))
        let entry = Entry(name: entryName(nameBytes),
                          compressionMethod: try bytes.uint16(at: offset + 10), compressedByteCount: Int(compressedByteCount),
                          uncompressedByteCount: Int(uncompressedByteCount), isEncrypted: flags & encryptedFlag != 0,
                          checksum: try bytes.uint32(at: offset + 16), localHeaderOffset: Int(localHeaderOffset))
        return (entry, nextOffset)
    }

    /// A name is read as UTF-8, whether or not its entry is flagged so (notebooks write UTF-8 either way), and as
    /// Latin-1 when it is not valid UTF-8.
    /// Names are only compared with names of the same archive, so the choice never changes which entry is read.
    private static func entryName(_ nameBytes: UnsafeRawBufferPointer) -> String {
        if let name = String(validating: nameBytes, as: UTF8.self) { return name }
        return String(nameBytes.map { byte in Character(Unicode.Scalar(byte)) })
    }

    private static func storedBytes(of entry: Entry, in bytes: LittleEndianBytes) throws(ZipArchiveError) -> UnsafeRawBufferPointer {
        let header = entry.localHeaderOffset
        guard header + localHeaderBytes <= bytes.count, try bytes.uint32(at: header) == localHeaderSignature else {
            throw ZipArchiveError.entryDataOutsideArchive(name: entry.name)
        }
        let dataStart = header + localHeaderBytes + Int(try bytes.uint16(at: header + 26)) + Int(try bytes.uint16(at: header + 28))
        guard dataStart + entry.compressedByteCount <= bytes.count else { throw ZipArchiveError.entryDataOutsideArchive(name: entry.name) }
        return try bytes.slice(dataStart..<(dataStart + entry.compressedByteCount))
    }

    /// Inflates into a buffer of exactly the recorded size: a stream that would produce more stops when the buffer is
    /// full and is refused, so a small entry cannot expand into more memory than its directory record admits.
    private static func inflate(_ compressed: UnsafeRawBufferPointer, expectedByteCount: Int, entryName: String) throws(ZipArchiveError) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: max(expectedByteCount, 1))
        var stream = z_stream()
        guard inflateInit2_(&stream, rawDeflateWindowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ZipArchiveError.entryDataDamaged(name: entryName)
        }
        defer { inflateEnd(&stream) }
        let status = output.withUnsafeMutableBytes { outputBytes -> Int32 in
            stream.next_in = UnsafeMutablePointer(mutating: compressed.baseAddress?.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = uInt(compressed.count)
            stream.next_out = outputBytes.baseAddress?.assumingMemoryBound(to: Bytef.self)
            stream.avail_out = uInt(expectedByteCount)
            return zlib.inflate(&stream, Z_FINISH)
        }
        guard status == Z_STREAM_END, Int(stream.total_out) == expectedByteCount else { throw ZipArchiveError.entryDataDamaged(name: entryName) }
        output.removeLast(output.count - expectedByteCount)
        return output
    }

    private static func checksum(of contents: [UInt8]) -> UInt32 {
        contents.withUnsafeBytes { buffer in checksum(of: buffer) }
    }

    static func checksum(of buffer: UnsafeRawBufferPointer, continuing previous: UInt32 = 0) -> UInt32 {
        UInt32(crc32(uLong(previous), buffer.baseAddress?.assumingMemoryBound(to: Bytef.self), uInt(buffer.count)))
    }
}

/// Little-endian integers read from a byte buffer. Every read checks its range and fails as `readOutsideArchive`, so
/// an offset a caller forgot to check cannot read memory outside the archive.
struct LittleEndianBytes {
    let buffer: UnsafeRawBufferPointer

    init(_ buffer: UnsafeRawBufferPointer) { self.buffer = buffer }

    var count: Int { buffer.count }

    func uint16(at offset: Int) throws(ZipArchiveError) -> UInt16 {
        guard let number = LittleEndianInteger.read(UInt16.self, in: buffer, at: offset) else { throw .readOutsideArchive(offset: offset) }
        return number
    }

    func uint32(at offset: Int) throws(ZipArchiveError) -> UInt32 {
        guard let number = LittleEndianInteger.read(UInt32.self, in: buffer, at: offset) else { throw .readOutsideArchive(offset: offset) }
        return number
    }

    func slice(_ range: Range<Int>) throws(ZipArchiveError) -> UnsafeRawBufferPointer {
        try checkRange(range.lowerBound, byteCount: range.count)
        return UnsafeRawBufferPointer(rebasing: buffer[range])
    }

    private func checkRange(_ offset: Int, byteCount: Int) throws(ZipArchiveError) {
        guard offset >= 0, byteCount >= 0, offset <= buffer.count - byteCount else { throw .readOutsideArchive(offset: offset) }
    }
}
