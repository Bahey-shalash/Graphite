import XCTest
@testable import GraphiteCore

final class ZipArchiveTests: XCTestCase {
    private let centralDirectoryEntryBytes = 46
    private let endRecordBytes = 22

    private func archiveWith(entries: [(name: String, contents: [UInt8], compression: ZipArchiveBuilder.Compression)]) -> [UInt8] {
        var builder = ZipArchiveBuilder()
        for entry in entries { builder.addEntry(named: entry.name, contents: entry.contents, compression: entry.compression) }
        return Array(builder.archiveBytes())
    }

    private func singleEntryArchive(contents: [UInt8], compression: ZipArchiveBuilder.Compression) -> [UInt8] {
        archiveWith(entries: [(name: "data.bin", contents: contents, compression: compression)])
    }

    private func readableLimits(maximumEntryBytes: Int = 4_096) -> NotebookImportLimits {
        NotebookImportLimits(maximumEntryBytes: maximumEntryBytes, maximumDecodedPayloadBytes: 4_096,
                             maximumArchiveReferenceDepth: 8, maximumPropertyListNestingDepth: 8,
                             maximumPlainValueCount: 4_096)
    }

    /// The offset of the first central directory entry, found through the end record of an archive without a comment.
    private func firstDirectoryEntryOffset(of archiveBytes: [UInt8]) -> Int {
        let endRecordOffset = archiveBytes.count - endRecordBytes
        return Int(readUInt32(archiveBytes, at: endRecordOffset + 16))
    }

    private func readUInt32(_ archiveBytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { number, byteIndex in number | UInt32(archiveBytes[offset + byteIndex]) << (8 * UInt32(byteIndex)) }
    }

    private func write(_ number: UInt32, byteCount: Int, into archiveBytes: inout [UInt8], at offset: Int) {
        for byteIndex in 0..<byteCount { archiveBytes[offset + byteIndex] = UInt8((number >> (8 * UInt32(byteIndex))) & 0xFF) }
    }

    private func archive(_ archiveBytes: [UInt8], opens limits: NotebookImportLimits? = nil) throws -> ZipArchive {
        try ZipArchive(archiveBytes: Data(archiveBytes), limits: limits ?? readableLimits())
    }

    private func assertOpeningThrows(_ archiveBytes: [UInt8], _ expected: ZipArchiveError, line: UInt = #line) {
        XCTAssertThrowsError(try ZipArchive(archiveBytes: Data(archiveBytes), limits: readableLimits()), line: line) { error in
            XCTAssertEqual(error as? ZipArchiveError, expected, line: line)
        }
    }

    private func assertReadingThrows(_ archiveBytes: [UInt8], _ expected: ZipArchiveError, line: UInt = #line) throws {
        let zipArchive = try archive(archiveBytes)
        XCTAssertThrowsError(try zipArchive.contents(ofEntryNamed: "data.bin"), line: line) { error in
            XCTAssertEqual(error as? ZipArchiveError, expected, line: line)
        }
    }

    // MARK: Normal behaviour

    func testAStoredEntryRoundTrips() throws {
        let contents: [UInt8] = [1, 2, 3, 250, 0, 7]
        let zipArchive = try archive(singleEntryArchive(contents: contents, compression: .stored))
        XCTAssertEqual(try zipArchive.contents(ofEntryNamed: "data.bin"), contents)
        XCTAssertEqual(zipArchive.entry(named: "data.bin")?.compressionMethod, 0)
        XCTAssertEqual(zipArchive.entry(named: "data.bin")?.uncompressedByteCount, contents.count)
    }

    func testADeflatedEntryRoundTrips() throws {
        let contents = [UInt8](repeating: 65, count: 1_000) + Array("graphite".utf8)
        let zipArchive = try archive(singleEntryArchive(contents: contents, compression: .deflated))
        XCTAssertEqual(try zipArchive.contents(ofEntryNamed: "data.bin"), contents)
        XCTAssertEqual(zipArchive.entry(named: "data.bin")?.compressionMethod, 8)
        XCTAssertLessThan(zipArchive.entry(named: "data.bin")?.compressedByteCount ?? .max, contents.count)
    }

    func testEmptyEntriesRoundTripStoredAndDeflated() throws {
        let archiveBytes = archiveWith(entries: [(name: "stored.bin", contents: [], compression: .stored),
                                                 (name: "deflated.bin", contents: [], compression: .deflated)])
        let zipArchive = try archive(archiveBytes)
        XCTAssertEqual(try zipArchive.contents(ofEntryNamed: "stored.bin"), [])
        XCTAssertEqual(try zipArchive.contents(ofEntryNamed: "deflated.bin"), [])
    }

    func testEntriesAreListedInDirectoryOrderAndFoundByName() throws {
        let archiveBytes = archiveWith(entries: [(name: "b.txt", contents: [1], compression: .stored),
                                                 (name: "folder/a.txt", contents: [2], compression: .deflated),
                                                 (name: "Notizen/\u{FC}.plist", contents: [3], compression: .stored)])
        let zipArchive = try archive(archiveBytes)
        XCTAssertEqual(zipArchive.entries.map(\.name), ["b.txt", "folder/a.txt", "Notizen/\u{FC}.plist"])
        XCTAssertEqual(try zipArchive.contents(ofEntryNamed: "folder/a.txt"), [2])
        XCTAssertEqual(try zipArchive.contents(ofEntryNamed: "Notizen/\u{FC}.plist"), [3])
        XCTAssertEqual(try zipArchive.contents(of: zipArchive.entries[0]), [1])
    }

    func testAnArchiveWithoutEntriesHasNoEntries() throws {
        let zipArchive = try archive(archiveWith(entries: []))
        XCTAssertEqual(zipArchive.entries, [])
        XCTAssertNil(zipArchive.entry(named: "anything"))
    }

    func testTheLaterOfTwoEntriesWithTheSameNameIsRead() throws {
        let archiveBytes = archiveWith(entries: [(name: "same.bin", contents: [1, 1], compression: .stored),
                                                 (name: "same.bin", contents: [2, 2, 2], compression: .deflated)])
        let zipArchive = try archive(archiveBytes)
        XCTAssertEqual(zipArchive.entries.count, 2)
        XCTAssertEqual(try zipArchive.contents(ofEntryNamed: "same.bin"), [2, 2, 2])
        XCTAssertEqual(zipArchive.entry(named: "same.bin")?.uncompressedByteCount, 3)
    }

    func testAMissingEntryIsReportedByName() throws {
        let zipArchive = try archive(singleEntryArchive(contents: [1], compression: .stored))
        XCTAssertNil(zipArchive.entry(named: "absent.bin"))
        XCTAssertThrowsError(try zipArchive.contents(ofEntryNamed: "absent.bin")) { error in
            XCTAssertEqual(error as? ZipArchiveError, .entryMissing(name: "absent.bin"))
        }
    }

    func testAnArchiveCommentAfterTheEndRecordIsSkipped() throws {
        var archiveBytes = singleEntryArchive(contents: [9, 8, 7], compression: .stored)
        let comment = Array("a comment that mentions nothing".utf8)
        write(UInt32(comment.count), byteCount: 2, into: &archiveBytes, at: archiveBytes.count - 2)
        archiveBytes += comment
        let zipArchive = try archive(archiveBytes)
        XCTAssertEqual(try zipArchive.contents(ofEntryNamed: "data.bin"), [9, 8, 7])
    }

    func testAnEntryAtTheLimitIsReadAndOneByteOverIsRefused() throws {
        let contents = [UInt8](repeating: 3, count: 64)
        let archiveBytes = singleEntryArchive(contents: contents, compression: .stored)
        XCTAssertEqual(try archive(archiveBytes, opens: readableLimits(maximumEntryBytes: 64)).contents(ofEntryNamed: "data.bin"), contents)
        let refusingArchive = try archive(archiveBytes, opens: readableLimits(maximumEntryBytes: 63))
        XCTAssertThrowsError(try refusingArchive.contents(ofEntryNamed: "data.bin")) { error in
            XCTAssertEqual(error as? ZipArchiveError, .entryTooLarge(name: "data.bin", limitBytes: 63))
        }
    }

    // MARK: Not a ZIP archive

    func testBytesWithoutAnEndRecordAreNotAnArchive() {
        assertOpeningThrows([], .endOfCentralDirectoryMissing)
        assertOpeningThrows([UInt8](repeating: 0, count: 21), .endOfCentralDirectoryMissing)
        assertOpeningThrows([UInt8](repeating: 0, count: 22), .endOfCentralDirectoryMissing)
        assertOpeningThrows(Array("This is plain text, long enough to hold an end record but not one.".utf8), .endOfCentralDirectoryMissing)
    }

    func testAWrongEndRecordSignatureIsNotAnArchive() {
        var archiveBytes = singleEntryArchive(contents: [1, 2], compression: .stored)
        archiveBytes[archiveBytes.count - endRecordBytes] = 0x51
        assertOpeningThrows(archiveBytes, .endOfCentralDirectoryMissing)
    }

    func testAnEndRecordWhoseCommentLengthDoesNotReachTheEndIsNotFound() {
        var archiveBytes = singleEntryArchive(contents: [1, 2], compression: .stored)
        write(5, byteCount: 2, into: &archiveBytes, at: archiveBytes.count - 2)
        assertOpeningThrows(archiveBytes, .endOfCentralDirectoryMissing)
    }

    // MARK: Damaged directory

    func testAnEntryCountFarLargerThanTheDirectoryAllowsIsRefused() {
        var archiveBytes = singleEntryArchive(contents: [1, 2], compression: .stored)
        write(60_000, byteCount: 2, into: &archiveBytes, at: archiveBytes.count - endRecordBytes + 10)
        assertOpeningThrows(archiveBytes, .centralDirectoryDamaged)
    }

    func testAnEntryCountOnePastTheDirectoryIsRefused() {
        var archiveBytes = singleEntryArchive(contents: [1, 2], compression: .stored)
        write(2, byteCount: 2, into: &archiveBytes, at: archiveBytes.count - endRecordBytes + 10)
        assertOpeningThrows(archiveBytes, .centralDirectoryDamaged)
    }

    func testADirectoryOffsetOutsideTheArchiveIsRefused() {
        var archiveBytes = singleEntryArchive(contents: [1, 2], compression: .stored)
        write(0x7FFF_0000, byteCount: 4, into: &archiveBytes, at: archiveBytes.count - endRecordBytes + 16)
        assertOpeningThrows(archiveBytes, .centralDirectoryDamaged)
    }

    func testADirectoryEntryWithAWrongSignatureIsRefused() {
        var archiveBytes = singleEntryArchive(contents: [1, 2], compression: .stored)
        archiveBytes[firstDirectoryEntryOffset(of: archiveBytes)] = 0
        assertOpeningThrows(archiveBytes, .centralDirectoryDamaged)
    }

    func testADirectoryEntryWhoseNameRunsPastTheDirectoryIsRefused() {
        var archiveBytes = singleEntryArchive(contents: [1, 2], compression: .stored)
        write(500, byteCount: 2, into: &archiveBytes, at: firstDirectoryEntryOffset(of: archiveBytes) + 28)
        assertOpeningThrows(archiveBytes, .centralDirectoryDamaged)
    }

    func testZip64MarkersAreRefused() throws {
        let archiveBytes = singleEntryArchive(contents: [1, 2], compression: .stored)
        let entryOffset = firstDirectoryEntryOffset(of: archiveBytes)
        for markerOffset in [entryOffset + 20, entryOffset + 24, entryOffset + 42] {
            var marked = archiveBytes
            write(0xFFFF_FFFF, byteCount: 4, into: &marked, at: markerOffset)
            assertOpeningThrows(marked, .zip64NotSupported)
        }
        var manyEntries = archiveBytes
        write(0xFFFF, byteCount: 2, into: &manyEntries, at: manyEntries.count - endRecordBytes + 10)
        assertOpeningThrows(manyEntries, .zip64NotSupported)
        var directorySize = archiveBytes
        write(0xFFFF_FFFF, byteCount: 4, into: &directorySize, at: directorySize.count - endRecordBytes + 12)
        assertOpeningThrows(directorySize, .zip64NotSupported)
        var directoryOffset = archiveBytes
        write(0xFFFF_FFFF, byteCount: 4, into: &directoryOffset, at: directoryOffset.count - endRecordBytes + 16)
        assertOpeningThrows(directoryOffset, .zip64NotSupported)
    }

    // MARK: Damaged entries

    func testALocalHeaderOffsetOutsideTheArchiveIsRefusedWhenTheEntryIsRead() throws {
        var archiveBytes = singleEntryArchive(contents: [1, 2], compression: .stored)
        write(0x00FF_0000, byteCount: 4, into: &archiveBytes, at: firstDirectoryEntryOffset(of: archiveBytes) + 42)
        try assertReadingThrows(archiveBytes, .entryDataOutsideArchive(name: "data.bin"))
    }

    func testALocalHeaderOffsetOfTheLastBytesIsRefusedWhenTheEntryIsRead() throws {
        var archiveBytes = singleEntryArchive(contents: [1, 2], compression: .stored)
        write(UInt32(archiveBytes.count - 10), byteCount: 4, into: &archiveBytes, at: firstDirectoryEntryOffset(of: archiveBytes) + 42)
        try assertReadingThrows(archiveBytes, .entryDataOutsideArchive(name: "data.bin"))
    }

    func testALocalHeaderWithAWrongSignatureIsRefusedWhenTheEntryIsRead() throws {
        var archiveBytes = singleEntryArchive(contents: [1, 2], compression: .stored)
        archiveBytes[0] = 0
        try assertReadingThrows(archiveBytes, .entryDataOutsideArchive(name: "data.bin"))
    }

    func testACompressedSizePastTheArchiveIsRefusedWhenTheEntryIsRead() throws {
        var archiveBytes = singleEntryArchive(contents: [1, 2], compression: .stored)
        write(0x0010_0000, byteCount: 4, into: &archiveBytes, at: firstDirectoryEntryOffset(of: archiveBytes) + 20)
        try assertReadingThrows(archiveBytes, .entryDataOutsideArchive(name: "data.bin"))
    }

    func testAChangedDataByteOfAStoredEntryFailsTheChecksum() throws {
        var archiveBytes = singleEntryArchive(contents: [10, 20, 30, 40], compression: .stored)
        let dataOffset = 30 + "data.bin".utf8.count + 1
        archiveBytes[dataOffset] ^= 0xFF
        try assertReadingThrows(archiveBytes, .checksumMismatch(name: "data.bin"))
    }

    func testAStoredEntryWhoseSizesDisagreeIsDamaged() throws {
        var archiveBytes = singleEntryArchive(contents: [10, 20, 30, 40], compression: .stored)
        write(3, byteCount: 4, into: &archiveBytes, at: firstDirectoryEntryOffset(of: archiveBytes) + 24)
        try assertReadingThrows(archiveBytes, .entryDataDamaged(name: "data.bin"))
    }

    func testAnEncryptedFlagRefusesTheEntry() throws {
        var archiveBytes = singleEntryArchive(contents: [1, 2], compression: .stored)
        write(1, byteCount: 2, into: &archiveBytes, at: firstDirectoryEntryOffset(of: archiveBytes) + 8)
        try assertReadingThrows(archiveBytes, .entryEncrypted(name: "data.bin"))
    }

    func testAnUnsupportedCompressionMethodRefusesTheEntry() throws {
        var archiveBytes = singleEntryArchive(contents: [1, 2], compression: .stored)
        write(12, byteCount: 2, into: &archiveBytes, at: firstDirectoryEntryOffset(of: archiveBytes) + 10)
        try assertReadingThrows(archiveBytes, .compressionMethodNotSupported(name: "data.bin", method: 12))
    }

    func testAnEntryLargerThanTheLimitIsRefusedBeforeItIsInflated() throws {
        let contents = [UInt8](repeating: 0, count: 100_000)
        let archiveBytes = singleEntryArchive(contents: contents, compression: .deflated)
        let zipArchive = try archive(archiveBytes, opens: readableLimits(maximumEntryBytes: 1_000))
        XCTAssertEqual(zipArchive.entry(named: "data.bin")?.uncompressedByteCount, 100_000)
        XCTAssertThrowsError(try zipArchive.contents(ofEntryNamed: "data.bin")) { error in
            XCTAssertEqual(error as? ZipArchiveError, .entryTooLarge(name: "data.bin", limitBytes: 1_000))
        }
    }

    func testADeclaredSizeFarOverTheLimitIsRefusedWithoutAllocatingIt() throws {
        var archiveBytes = singleEntryArchive(contents: [UInt8](repeating: 0, count: 100), compression: .deflated)
        write(0xFFFF_FFFE, byteCount: 4, into: &archiveBytes, at: firstDirectoryEntryOffset(of: archiveBytes) + 24)
        try assertReadingThrows(archiveBytes, .entryTooLarge(name: "data.bin", limitBytes: 4_096))
    }

    /// CC-IMPORT-01: a 100-byte entry declaring 500 MiB was given 500 MiB of memory before its first byte was inflated.
    func testAnEntryDeclaringMoreThanDeflateCanProduceIsRefusedBeforeAllocating() throws {
        var archiveBytes = singleEntryArchive(contents: [UInt8](repeating: 0, count: 100), compression: .deflated)
        write(500 * 1_048_576, byteCount: 4, into: &archiveBytes, at: firstDirectoryEntryOffset(of: archiveBytes) + 24)
        let zipArchive = try archive(archiveBytes, opens: readableLimits(maximumEntryBytes: 512 * 1_048_576))
        XCTAssertThrowsError(try zipArchive.contents(ofEntryNamed: "data.bin")) { error in
            XCTAssertEqual(error as? ZipArchiveError, .compressionRatioImpossible(name: "data.bin"))
        }
    }

    func testADeflateStreamThatExpandsPastItsDeclaredSizeIsDamaged() throws {
        var archiveBytes = singleEntryArchive(contents: [UInt8](repeating: 7, count: 2_000), compression: .deflated)
        write(1_000, byteCount: 4, into: &archiveBytes, at: firstDirectoryEntryOffset(of: archiveBytes) + 24)
        try assertReadingThrows(archiveBytes, .entryDataDamaged(name: "data.bin"))
    }

    func testADeflateStreamThatEndsShortOfItsDeclaredSizeIsDamaged() throws {
        var archiveBytes = singleEntryArchive(contents: [UInt8](repeating: 7, count: 2_000), compression: .deflated)
        write(3_000, byteCount: 4, into: &archiveBytes, at: firstDirectoryEntryOffset(of: archiveBytes) + 24)
        try assertReadingThrows(archiveBytes, .entryDataDamaged(name: "data.bin"))
    }

    func testADeflateStreamOfGarbageIsDamaged() throws {
        var archiveBytes = singleEntryArchive(contents: [UInt8](repeating: 7, count: 200), compression: .deflated)
        let dataOffset = 30 + "data.bin".utf8.count
        for byteIndex in 0..<4 { archiveBytes[dataOffset + byteIndex] = 0xFF }
        try assertReadingThrows(archiveBytes, .entryDataDamaged(name: "data.bin"))
    }

    // MARK: Truncation and fuzzing

    func testAnArchiveCutAtEveryLengthFailsWithATypedErrorOrStillReadsItsEntries() {
        let archiveBytes = archiveWith(entries: [(name: "first.bin", contents: Array("first entry".utf8), compression: .deflated),
                                                 (name: "second.bin", contents: [1, 2, 3, 4], compression: .stored)])
        var openedCount = 0
        for length in 0...archiveBytes.count {
            do throws(ZipArchiveError) {
                let zipArchive = try ZipArchive(archiveBytes: Data(archiveBytes[0..<length]), limits: readableLimits())
                openedCount += 1
                for entry in zipArchive.entries {
                    do throws(ZipArchiveError) { _ = try zipArchive.contents(of: entry) } catch { _ = error }
                }
            } catch {
                _ = error
            }
        }
        XCTAssertEqual(openedCount, 1, "Only the complete archive has an end record that reaches its end.")
    }

    func testRandomDamageToAnArchiveEndsInATypedErrorOrAnEntryRead() {
        let archiveBytes = archiveWith(entries: [(name: "first.bin", contents: Array("first entry, first entry".utf8), compression: .deflated),
                                                 (name: "second.bin", contents: [1, 2, 3, 4], compression: .stored)])
        var generator = ZipArchiveTestRandomNumberGenerator(seed: 0x5EED_0001)
        var failedCount = 0, succeededCount = 0
        for _ in 0..<3_000 {
            var damaged = archiveBytes
            for _ in 0..<Int.random(in: 1...4, using: &generator) {
                damaged[Int.random(in: 0..<damaged.count, using: &generator)] = UInt8.random(in: 0...255, using: &generator)
            }
            if Bool.random(using: &generator) { damaged.removeLast(Int.random(in: 0..<10, using: &generator)) }
            do throws(ZipArchiveError) {
                let zipArchive = try ZipArchive(archiveBytes: Data(damaged), limits: readableLimits())
                for entry in zipArchive.entries { _ = try zipArchive.contents(of: entry) }
                succeededCount += 1
            } catch {
                failedCount += 1
            }
        }
        XCTAssertGreaterThan(failedCount, 0)
        XCTAssertGreaterThan(succeededCount, 0)
    }
}

/// SplitMix64 with a fixed seed, so a failing sequence of damage can be replayed.
private struct ZipArchiveTestRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
