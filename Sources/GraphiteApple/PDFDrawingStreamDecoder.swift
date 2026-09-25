import Foundation
import CoreGraphics
import Compression

/// The bytes of a PDF file, read at most once and only if a stream has to be inflated
/// from them.
final class PDFFileBytes {
    let byteCount: Int
    private let readBytes: () -> Data?
    private(set) lazy var bytes: Data? = readBytes()

    init(byteCount: Int, readBytes: @escaping () -> Data?) {
        self.byteCount = byteCount
        self.readBytes = readBytes
    }
}

/// Decodes the streams of a possible Graphite drawing without letting a small file expand
/// into an unbounded allocation.
///
/// `CGPDFStreamCopyData` inflates a whole stream at once, reads up to `endstream` however
/// small `/Length` claims the stream is, and a FlateDecode stream can expand about 1,032
/// times: a 1 MB file could demand a gigabyte each time a note embeds it. Core Graphics
/// compresses every stream it writes, Graphite's own drawings included, so filtered
/// streams cannot simply be refused. Only a file too small for any of its streams to
/// exceed the budget is decoded by Core Graphics. Otherwise the stream is found in the
/// file's bytes and inflated in chunks with a limit on the output.
enum PDFDrawingStreamDecoder {
    /// DEFLATE's maximum compression ratio (258-byte matches coded in about 2 bits).
    private static let maximumFlateExpansion = 1_032
    /// The most Core Graphics is allowed to allocate for one decoded stream.
    private static let maximumDirectlyDecodedBytes = 16 * 1_048_576
    /// How far before a `stream` keyword the enclosing object's header is searched.
    private static let dictionarySearchDistance = 4_096
    private static let inflateChunkByteCount = 65_536
    /// Keys that set other kinds of streams (metadata, images, forms, ICC profiles) apart
    /// from one another. A candidate may carry one only if the stream itself does.
    private static let distinguishingKeys: Set<String> = ["Type", "Subtype", "N"]

    /// The decoded bytes, or nil when there would be more than `maximumDecodedBytes` or the
    /// stream cannot be decoded.
    static func decodedContents(of stream: CGPDFStreamRef, in file: PDFFileBytes, maximumDecodedBytes: Int) -> Data? {
        var decodedBytes = Data()
        let decodedByteCount = decode(stream, in: file, maximumDecodedBytes: maximumDecodedBytes, into: &decodedBytes) { decodedBytes, chunk in
            decodedBytes.append(chunk)
        }
        return decodedByteCount == nil ? nil : decodedBytes
    }

    /// Passes the decoded bytes to `append` in order, possibly in several chunks, and
    /// returns how many there were. Returns nil, with `accumulator` unchanged, when there
    /// would be more than `maximumDecodedBytes` or the stream cannot be decoded.
    static func decode<Accumulator>(_ stream: CGPDFStreamRef, in file: PDFFileBytes, maximumDecodedBytes: Int,
                                    into accumulator: inout Accumulator, append: (inout Accumulator, Data) -> Void) -> Int? {
        guard let dictionary = CGPDFStreamGetDictionary(stream) else { return nil }
        let streamFilter = filter(of: dictionary)
        guard streamFilter != .unsupported else { return nil }
        let expansion = streamFilter == .flate ? maximumFlateExpansion : 1
        let (worstCaseDecodedBytes, overflowed) = file.byteCount.multipliedReportingOverflow(by: expansion)
        if !overflowed, worstCaseDecodedBytes <= min(maximumDecodedBytes, maximumDirectlyDecodedBytes) {
            var format = CGPDFDataFormat.raw
            guard let streamContent = CGPDFStreamCopyData(stream, &format), format == .raw else { return nil }
            let decodedBytes = streamContent as Data
            guard decodedBytes.count <= maximumDecodedBytes else { return nil }
            append(&accumulator, decodedBytes)
            return decodedBytes.count
        }
        var declaredLength: CGPDFInteger = 0
        guard CGPDFDictionaryGetInteger(dictionary, "Length", &declaredLength), declaredLength >= 0, declaredLength <= file.byteCount,
              let fileBytes = file.bytes else { return nil }
        // An incrementally updated file appends new versions of objects after the old ones.
        for rawRange in rawStreamCandidates(in: fileBytes, declaredLength: Int(declaredLength), keys: keys(of: dictionary)).reversed() {
            var candidateAccumulator = accumulator
            let decodedByteCount: Int?
            switch streamFilter {
            case .flate:
                decodedByteCount = inflate(fileBytes[rawRange], maximumDecodedBytes: maximumDecodedBytes, into: &candidateAccumulator, append: append)
            case .none where rawRange.count <= maximumDecodedBytes:
                append(&candidateAccumulator, fileBytes[rawRange])
                decodedByteCount = rawRange.count
            case .none, .unsupported:
                decodedByteCount = nil
            }
            if let decodedByteCount {
                accumulator = candidateAccumulator
                return decodedByteCount
            }
        }
        return nil
    }

    private enum StreamFilter { case none, flate, unsupported }

    /// Only an unfiltered stream or a single FlateDecode without parameters has a known
    /// expansion bound. Chained filters multiply it, and Graphite never writes predictors.
    private static func filter(of dictionary: CGPDFDictionaryRef) -> StreamFilter {
        var decodeParameters: CGPDFObjectRef?
        if CGPDFDictionaryGetObject(dictionary, "DecodeParms", &decodeParameters),
           let decodeParameters, CGPDFObjectGetType(decodeParameters) != .null {
            return .unsupported
        }
        var filterName: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(dictionary, "Filter", &filterName), let filterName {
            return String(cString: filterName) == "FlateDecode" ? .flate : .unsupported
        }
        var filterArray: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(dictionary, "Filter", &filterArray), let filterArray {
            switch CGPDFArrayGetCount(filterArray) {
            case 0: return .none
            case 1:
                var arrayFilterName: UnsafePointer<CChar>?
                guard CGPDFArrayGetName(filterArray, 0, &arrayFilterName), let arrayFilterName else { return .unsupported }
                return String(cString: arrayFilterName) == "FlateDecode" ? .flate : .unsupported
            default: return .unsupported
            }
        }
        var filterObject: CGPDFObjectRef?
        if CGPDFDictionaryGetObject(dictionary, "Filter", &filterObject), let filterObject, CGPDFObjectGetType(filterObject) != .null {
            return .unsupported
        }
        return .none
    }

    private static func keys(of dictionary: CGPDFDictionaryRef) -> Set<String> {
        var keys: Set<String> = []
        CGPDFDictionaryApplyBlock(dictionary, { keyPointer, _, _ in
            keys.insert(String(cString: keyPointer))
            return true
        }, nil)
        return keys
    }

    /// Byte ranges of the data of streams that could be the one Core Graphics resolved.
    ///
    /// Core Graphics resolves objects but does not expose their file offsets, so the
    /// stream is found in the file itself. The PDF format never stores a stream inside a
    /// compressed object stream, so every stream dictionary is plain text in the file. A
    /// candidate counts only when its dictionary names every key of the resolved one and
    /// no key that marks another kind of stream, and `endstream` follows exactly
    /// `declaredLength` bytes of data. A wrong match can
    /// only fail to decode or fail the drawing's later checks; it never makes a file look
    /// editable, and whatever it decodes is still bounded.
    static func rawStreamCandidates(in fileBytes: Data, declaredLength: Int, keys: Set<String>) -> [Range<Data.Index>] {
        let excludedKeys = distinguishingKeys.subtracting(keys)
        let candidateOffsets = fileBytes.withUnsafeBytes { buffer -> [Range<Int>] in
            let streamKeyword = Array("stream".utf8), objectKeyword = Array("obj".utf8)
            var candidates: [Range<Int>] = []
            var searchStart = 0
            while let keywordStart = firstOffset(of: streamKeyword, in: buffer, from: searchStart, to: buffer.count) {
                searchStart = keywordStart + streamKeyword.count
                // `endstream` and `endobj` end in the keywords searched for.
                guard !followsEnd(keywordStart, in: buffer),
                      let objectStart = lastOffset(of: objectKeyword, in: buffer, before: keywordStart, searchDistance: dictionarySearchDistance),
                      !followsEnd(objectStart, in: buffer) else { continue }
                let dictionaryRange = (objectStart + objectKeyword.count)..<keywordStart
                guard keys.allSatisfy({ key in containsName(key, in: buffer, range: dictionaryRange) }),
                      !excludedKeys.contains(where: { key in containsName(key, in: buffer, range: dictionaryRange) }),
                      let dataStart = streamDataStart(after: searchStart, in: buffer),
                      declaredLength <= buffer.count - dataStart,
                      isEndOfStream(at: dataStart + declaredLength, in: buffer) else { continue }
                candidates.append(dataStart..<(dataStart + declaredLength))
            }
            return candidates
        }
        return candidateOffsets.map { offsets in (fileBytes.startIndex + offsets.lowerBound)..<(fileBytes.startIndex + offsets.upperBound) }
    }

    private static func firstOffset(of pattern: [UInt8], in buffer: UnsafeRawBufferPointer, from start: Int, to end: Int) -> Int? {
        guard let baseAddress = buffer.baseAddress, start < end, end <= buffer.count else { return nil }
        return pattern.withUnsafeBytes { patternBuffer in
            guard let match = memmem(baseAddress + start, end - start, patternBuffer.baseAddress, pattern.count) else { return nil }
            return baseAddress.distance(to: UnsafeRawPointer(match))
        }
    }

    private static func followsEnd(_ offset: Int, in buffer: UnsafeRawBufferPointer) -> Bool {
        offset >= 3 && buffer[offset - 3] == UInt8(ascii: "e") && buffer[offset - 2] == UInt8(ascii: "n") && buffer[offset - 1] == UInt8(ascii: "d")
    }

    private static func lastOffset(of pattern: [UInt8], in buffer: UnsafeRawBufferPointer, before end: Int, searchDistance: Int) -> Int? {
        var candidateStart = end - pattern.count
        let lowestStart = max(0, end - searchDistance)
        while candidateStart >= lowestStart {
            if pattern.indices.allSatisfy({ patternIndex in buffer[candidateStart + patternIndex] == pattern[patternIndex] }) { return candidateStart }
            candidateStart -= 1
        }
        return nil
    }

    /// Whether `/name` appears as a whole name: followed by whitespace or a delimiter.
    private static func containsName(_ name: String, in buffer: UnsafeRawBufferPointer, range: Range<Int>) -> Bool {
        let token = Array("/\(name)".utf8)
        let nameTerminators = Set(" \t\r\n\u{0C}/<>[]()%".utf8).union([0])
        var searchStart = range.lowerBound
        while let matchStart = firstOffset(of: token, in: buffer, from: searchStart, to: range.upperBound), matchStart + token.count < range.upperBound {
            if nameTerminators.contains(buffer[matchStart + token.count]) { return true }
            searchStart = matchStart + 1
        }
        return false
    }

    /// The `stream` keyword is followed by CRLF or LF, then the data.
    private static func streamDataStart(after keywordEnd: Int, in buffer: UnsafeRawBufferPointer) -> Int? {
        let carriageReturn = UInt8(ascii: "\r"), lineFeed = UInt8(ascii: "\n")
        guard keywordEnd < buffer.count else { return nil }
        if buffer[keywordEnd] == lineFeed { return keywordEnd + 1 }
        if buffer[keywordEnd] == carriageReturn, keywordEnd + 1 < buffer.count, buffer[keywordEnd + 1] == lineFeed { return keywordEnd + 2 }
        return nil
    }

    /// Writers put an optional end-of-line, and sometimes a space, before `endstream`.
    private static func isEndOfStream(at dataEnd: Int, in buffer: UnsafeRawBufferPointer) -> Bool {
        let endKeyword = Array("endstream".utf8)
        let whitespace: Set<UInt8> = [UInt8(ascii: "\r"), UInt8(ascii: "\n"), UInt8(ascii: " ")]
        var keywordStart = dataEnd
        while keywordStart < buffer.count, keywordStart - dataEnd < 3, whitespace.contains(buffer[keywordStart]) { keywordStart += 1 }
        guard endKeyword.count <= buffer.count - keywordStart else { return false }
        return endKeyword.indices.allSatisfy { keywordIndex in buffer[keywordStart + keywordIndex] == endKeyword[keywordIndex] }
    }

    private struct DecodedSizeExceeded: Error {}

    /// Collects inflated chunks for the escaping `OutputFilter` callback.
    private final class InflatedOutput<Accumulator> {
        var accumulator: Accumulator
        var decodedByteCount = 0
        init(accumulator: Accumulator) { self.accumulator = accumulator }
    }

    /// Inflates a zlib-wrapped FlateDecode stream chunk by chunk, giving up as soon as the
    /// output passes `maximumDecodedBytes`.
    static func inflate<Accumulator>(_ zlibStream: Data, maximumDecodedBytes: Int,
                                     into accumulator: inout Accumulator, append: (inout Accumulator, Data) -> Void) -> Int? {
        // RFC 1950 header: method 8 (deflate), a check value, and no preset dictionary.
        guard zlibStream.count > 2 else { return nil }
        let methodAndWindow = zlibStream[zlibStream.startIndex], flags = zlibStream[zlibStream.startIndex + 1]
        guard methodAndWindow & 0x0F == 8, (UInt16(methodAndWindow) << 8 | UInt16(flags)) % 31 == 0, flags & 0x20 == 0 else { return nil }
        // Apple's `.zlib` algorithm is raw DEFLATE; it stops at the final block and so
        // ignores the trailing Adler-32 checksum.
        let deflateData = zlibStream.dropFirst(2)
        let output = InflatedOutput(accumulator: accumulator)
        let succeeded = withoutActuallyEscaping(append) { escapableAppend in
            do {
                let filter = try OutputFilter(.decompress, using: .zlib) { decodedChunk in
                    guard let decodedChunk else { return }
                    guard decodedChunk.count <= maximumDecodedBytes - output.decodedByteCount else { throw DecodedSizeExceeded() }
                    output.decodedByteCount += decodedChunk.count
                    escapableAppend(&output.accumulator, decodedChunk)
                }
                var chunkStart = deflateData.startIndex
                while chunkStart < deflateData.endIndex {
                    let chunkEnd = min(chunkStart + inflateChunkByteCount, deflateData.endIndex)
                    try filter.write(deflateData[chunkStart..<chunkEnd])
                    chunkStart = chunkEnd
                }
                try filter.finalize()
                return true
            } catch {
                return false
            }
        }
        guard succeeded else { return nil }
        accumulator = output.accumulator
        return output.decodedByteCount
    }
}
