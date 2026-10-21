import Foundation
import zlib

/// Writes small ZIP archives in memory for the notebook reader tests: stored or deflated entries, a central directory
/// and its end record, as Goodnotes and Notability write them. Tests damage the result on purpose.
struct ZipArchiveBuilder {
    enum Compression { case stored, deflated }

    private struct WrittenEntry {
        let name: [UInt8]
        let method: UInt16
        let checksum: UInt32
        let compressedByteCount: Int
        let uncompressedByteCount: Int
        let localHeaderOffset: Int
    }

    private var archive: [UInt8] = []
    private var writtenEntries: [WrittenEntry] = []

    mutating func addEntry(named name: String, contents: [UInt8], compression: Compression = .deflated) {
        let stored = compression == .stored ? contents : Self.rawDeflate(contents)
        let nameBytes = Array(name.utf8)
        let checksum = contents.withUnsafeBytes { buffer in
            UInt32(crc32(0, buffer.baseAddress?.assumingMemoryBound(to: Bytef.self), uInt(buffer.count)))
        }
        let entry = WrittenEntry(name: nameBytes, method: compression == .stored ? 0 : 8, checksum: checksum,
                                 compressedByteCount: stored.count, uncompressedByteCount: contents.count,
                                 localHeaderOffset: archive.count)
        appendUInt32(0x0403_4B50)
        appendUInt16(20)
        appendUInt16(0)
        appendUInt16(entry.method)
        appendUInt32(0)
        appendUInt32(entry.checksum)
        appendUInt32(UInt32(entry.compressedByteCount))
        appendUInt32(UInt32(entry.uncompressedByteCount))
        appendUInt16(UInt16(nameBytes.count))
        appendUInt16(0)
        archive += nameBytes
        archive += stored
        writtenEntries.append(entry)
    }

    mutating func addEntry(named name: String, text: String, compression: Compression = .deflated) {
        addEntry(named: name, contents: Array(text.utf8), compression: compression)
    }

    /// The archive with its central directory, consuming the builder's state.
    func archiveBytes() -> Data {
        var finished = self
        let directoryOffset = finished.archive.count
        for entry in writtenEntries {
            finished.appendUInt32(0x0201_4B50)
            finished.appendUInt16(20)
            finished.appendUInt16(20)
            finished.appendUInt16(0)
            finished.appendUInt16(entry.method)
            finished.appendUInt32(0)
            finished.appendUInt32(entry.checksum)
            finished.appendUInt32(UInt32(entry.compressedByteCount))
            finished.appendUInt32(UInt32(entry.uncompressedByteCount))
            finished.appendUInt16(UInt16(entry.name.count))
            finished.appendUInt16(0)
            finished.appendUInt16(0)
            finished.appendUInt16(0)
            finished.appendUInt16(0)
            finished.appendUInt32(0)
            finished.appendUInt32(UInt32(entry.localHeaderOffset))
            finished.archive += entry.name
        }
        let directoryByteCount = finished.archive.count - directoryOffset
        finished.appendUInt32(0x0605_4B50)
        finished.appendUInt16(0)
        finished.appendUInt16(0)
        finished.appendUInt16(UInt16(writtenEntries.count))
        finished.appendUInt16(UInt16(writtenEntries.count))
        finished.appendUInt32(UInt32(directoryByteCount))
        finished.appendUInt32(UInt32(directoryOffset))
        finished.appendUInt16(0)
        return Data(finished.archive)
    }

    private mutating func appendUInt16(_ number: UInt16) {
        archive += [UInt8(number & 0xFF), UInt8(number >> 8)]
    }

    private mutating func appendUInt32(_ number: UInt32) {
        archive += (0..<4).map { byteIndex in UInt8((number >> (8 * UInt32(byteIndex))) & 0xFF) }
    }

    /// Raw deflate (no zlib header), as ZIP stores it.
    static func rawDeflate(_ contents: [UInt8]) -> [UInt8] {
        var stream = z_stream()
        deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        defer { deflateEnd(&stream) }
        var input = contents
        var output = [UInt8](repeating: 0, count: Int(deflateBound(&stream, uLong(contents.count))) + 16)
        let producedByteCount = input.withUnsafeMutableBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes -> Int in
                stream.next_in = inputBytes.baseAddress?.assumingMemoryBound(to: Bytef.self)
                stream.avail_in = uInt(inputBytes.count)
                stream.next_out = outputBytes.baseAddress?.assumingMemoryBound(to: Bytef.self)
                stream.avail_out = uInt(outputBytes.count)
                deflate(&stream, Z_FINISH)
                return Int(stream.total_out)
            }
        }
        return Array(output.prefix(producedByteCount))
    }
}
