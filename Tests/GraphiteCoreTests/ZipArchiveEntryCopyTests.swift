import XCTest
@testable import GraphiteCore

/// Reading a large entry without holding a copy of it (`ZipArchive.data(of:)` and `copy(_:chunkByteCount:to:)`): a
/// stored entry stays in the archive's own bytes, a deflated one goes through one buffer of the piece size, and the
/// size and checksum are still checked.
final class ZipArchiveEntryCopyTests: XCTestCase {
    private struct DestinationFull: Error, Equatable {}

    private static let limits = NotebookImportLimits(maximumEntryBytes: 1_000_000, maximumDecodedPayloadBytes: 4_096,
                                                     maximumArchiveReferenceDepth: 8, maximumPropertyListNestingDepth: 8,
                                                     maximumPlainValueCount: 4_096)
    /// Varied but compressible bytes.
    private static let recordingLikeBytes = (0..<300_000).map { byteIndex in UInt8((byteIndex * 7 + byteIndex / 13) & 0xFF) }

    func testAStoredEntrysDataIsASliceOfTheArchiveNotACopy() throws {
        let archiveData = Self.archiveData(contents: Array(Self.recordingLikeBytes.prefix(2_500)), compression: .stored)
        let zipArchive = try ZipArchive(archiveBytes: archiveData, limits: Self.limits)
        let data = try zipArchive.data(of: zipArchive.entries[0])
        XCTAssertEqual(Array(data), Array(Self.recordingLikeBytes.prefix(2_500)))
        XCTAssertTrue(Self.lies(within: archiveData, data), "a stored entry is read where it lies in the archive")
    }

    func testADeflatedEntrysDataIsInflated() throws {
        let zipArchive = try ZipArchive(archiveBytes: Self.archiveData(contents: Self.recordingLikeBytes, compression: .deflated), limits: Self.limits)
        XCTAssertEqual(Array(try zipArchive.data(of: zipArchive.entries[0])), Self.recordingLikeBytes)
    }

    func testAStoredEntryIsCopiedInPiecesOfTheArchiveItself() throws {
        let archiveData = Self.archiveData(contents: Array(Self.recordingLikeBytes.prefix(2_500)), compression: .stored)
        let zipArchive = try ZipArchive(archiveBytes: archiveData, limits: Self.limits)
        var pieces: [[UInt8]] = [], piecesInArchive = 0
        try zipArchive.copy(zipArchive.entries[0], chunkByteCount: 1_000) { piece in
            pieces.append(Array(piece))
            if Self.lies(within: archiveData, piece) { piecesInArchive += 1 }
        }
        XCTAssertEqual(pieces.map(\.count), [1_000, 1_000, 500])
        XCTAssertEqual(pieces.flatMap { piece in piece }, Array(Self.recordingLikeBytes.prefix(2_500)))
        XCTAssertEqual(piecesInArchive, 3)
    }

    func testADeflatedEntryIsCopiedThroughOneBufferOfThePieceSize() throws {
        let zipArchive = try ZipArchive(archiveBytes: Self.archiveData(contents: Self.recordingLikeBytes, compression: .deflated), limits: Self.limits)
        var copied: [UInt8] = [], pieceAddresses: Set<UnsafeRawPointer?> = [], largestPiece = 0
        try zipArchive.copy(zipArchive.entries[0], chunkByteCount: 65_536) { piece in
            copied += piece
            pieceAddresses.insert(piece.baseAddress)
            largestPiece = max(largestPiece, piece.count)
        }
        XCTAssertEqual(copied, Self.recordingLikeBytes)
        XCTAssertEqual(pieceAddresses.count, 1, "every piece is the same buffer")
        XCTAssertLessThanOrEqual(largestPiece, 65_536)
    }

    func testAChangedByteFailsTheChecksumAtTheEndOfTheCopy() throws {
        var archiveBytes = Array(Self.archiveData(contents: Array(Self.recordingLikeBytes.prefix(2_500)), compression: .stored))
        archiveBytes[30 + "data.bin".utf8.count + 1_200] ^= 0xFF
        let zipArchive = try ZipArchive(archiveBytes: Data(archiveBytes), limits: Self.limits)
        var copiedByteCount = 0
        XCTAssertEqual(Self.archiveError { () throws(ZipEntryCopyError<Never>) in
            try zipArchive.copy(zipArchive.entries[0], chunkByteCount: 1_000) { piece in copiedByteCount += piece.count }
        }, .checksumMismatch(name: "data.bin"))
        XCTAssertEqual(copiedByteCount, 2_500, "the pieces were handed over before the checksum could be known")
    }

    func testADeflatedCopyStopsAtTheRecordedSizeOrFailsShortOfIt() throws {
        for recordedByteCount: UInt32 in [100_000, 400_000] {
            var archiveBytes = Array(Self.archiveData(contents: Self.recordingLikeBytes, compression: .deflated))
            Self.writeUncompressedByteCount(recordedByteCount, into: &archiveBytes)
            let zipArchive = try ZipArchive(archiveBytes: Data(archiveBytes), limits: Self.limits)
            var copiedByteCount = 0
            XCTAssertEqual(Self.archiveError { () throws(ZipEntryCopyError<Never>) in
                try zipArchive.copy(zipArchive.entries[0], chunkByteCount: 65_536) { piece in copiedByteCount += piece.count }
            }, .entryDataDamaged(name: "data.bin"))
            XCTAssertLessThanOrEqual(copiedByteCount, Int(recordedByteCount))
        }
    }

    func testTheDestinationsErrorStopsTheCopyAndIsPassedOn() throws {
        let zipArchive = try ZipArchive(archiveBytes: Self.archiveData(contents: Self.recordingLikeBytes, compression: .deflated), limits: Self.limits)
        var pieceCount = 0
        do throws(ZipEntryCopyError<DestinationFull>) {
            try zipArchive.copy(zipArchive.entries[0], chunkByteCount: 65_536) { (_: UnsafeRawBufferPointer) throws(DestinationFull) in
                pieceCount += 1
                if pieceCount == 2 { throw DestinationFull() }
            }
            XCTFail("the copy went on past the destination's error")
        } catch {
            guard case .destination(let destinationError) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(destinationError, DestinationFull())
        }
        XCTAssertEqual(pieceCount, 2)
    }

    func testAnEntryOverTheLimitIsRefusedBeforeAnyPiece() throws {
        let limits = NotebookImportLimits(maximumEntryBytes: 1_000, maximumDecodedPayloadBytes: 4_096, maximumArchiveReferenceDepth: 8,
                                          maximumPropertyListNestingDepth: 8, maximumPlainValueCount: 4_096)
        let zipArchive = try ZipArchive(archiveBytes: Self.archiveData(contents: Array(Self.recordingLikeBytes.prefix(2_500)), compression: .stored),
                                        limits: limits)
        var pieceCount = 0
        XCTAssertEqual(Self.archiveError { () throws(ZipEntryCopyError<Never>) in try zipArchive.copy(zipArchive.entries[0]) { _ in pieceCount += 1 } },
                       .entryTooLarge(name: "data.bin", limitBytes: 1_000))
        XCTAssertEqual(pieceCount, 0)
        XCTAssertThrowsError(try zipArchive.data(of: zipArchive.entries[0]))
    }

    private static func archiveData(contents: [UInt8], compression: ZipArchiveBuilder.Compression) -> Data {
        var builder = ZipArchiveBuilder()
        builder.addEntry(named: "data.bin", contents: contents, compression: compression)
        return builder.archiveBytes()
    }

    /// The uncompressed size in the first central directory entry of an archive without a comment.
    private static func writeUncompressedByteCount(_ byteCount: UInt32, into archiveBytes: inout [UInt8]) {
        let endRecord = archiveBytes.count - 22
        let directoryOffset = (0..<4).reduce(0) { offset, byteIndex in offset | Int(archiveBytes[endRecord + 16 + byteIndex]) << (8 * byteIndex) }
        for byteIndex in 0..<4 { archiveBytes[directoryOffset + 24 + byteIndex] = UInt8((byteCount >> (8 * UInt32(byteIndex))) & 0xFF) }
    }

    private static func lies(within archiveData: Data, _ data: Data) -> Bool {
        data.withUnsafeBytes { buffer in lies(within: archiveData, buffer) }
    }

    private static func lies(within archiveData: Data, _ buffer: UnsafeRawBufferPointer) -> Bool {
        archiveData.withUnsafeBytes { archive in
            guard let archiveStart = archive.baseAddress, let start = buffer.baseAddress else { return false }
            return start >= archiveStart && start + buffer.count <= archiveStart + archive.count
        }
    }

    private static func archiveError(_ copy: () throws(ZipEntryCopyError<Never>) -> Void) -> ZipArchiveError? {
        do throws(ZipEntryCopyError<Never>) {
            try copy()
            return nil
        } catch {
            guard case .archive(let archiveError) = error else { return nil }
            return archiveError
        }
    }
}
