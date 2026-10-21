import XCTest
@testable import NotebookImport

final class AppleLZ4DecoderTests: XCTestCase {
    private let generousLimit = 1_048_576

    private func littleEndian(_ number: UInt32) -> [UInt8] {
        (0..<4).map { byteIndex in UInt8((number >> (8 * UInt32(byteIndex))) & 0xFF) }
    }

    private func storedBlock(_ contents: [UInt8]) -> [UInt8] {
        Array("bv4-".utf8) + littleEndian(UInt32(contents.count)) + contents
    }

    private func compressedBlock(decodedSize: UInt32, sequences: [UInt8]) -> [UInt8] {
        Array("bv41".utf8) + littleEndian(decodedSize) + littleEndian(UInt32(sequences.count)) + sequences
    }

    private var endMarker: [UInt8] { Array("bv4$".utf8) }

    private func decode(_ payload: [UInt8], limit: Int? = nil) throws -> [UInt8] {
        try AppleLZ4Decoder.decode(ArraySlice(payload), maximumDecodedBytes: limit ?? generousLimit)
    }

    private func assertDecodingThrows(_ payload: [UInt8], _ expected: AppleLZ4Error, limit: Int? = nil, line: UInt = #line) {
        XCTAssertThrowsError(try AppleLZ4Decoder.decode(ArraySlice(payload), maximumDecodedBytes: limit ?? generousLimit), line: line) { error in
            XCTAssertEqual(error as? AppleLZ4Error, expected, line: line)
        }
    }

    /// Literals "abc", then a match of nine bytes at distance three, then the closing literals "wxyz!".
    private let overlappingSequences: [UInt8] = [0x35] + Array("abc".utf8) + [3, 0] + [0x50] + Array("wxyz!".utf8)

    // MARK: Normal behaviour

    func testAnEmptyPayloadWithOnlyTheEndMarkerDecodesToNothing() throws {
        XCTAssertEqual(try decode(endMarker), [])
    }

    func testAStoredBlockIsCopied() throws {
        XCTAssertEqual(try decode(storedBlock([1, 2, 3]) + endMarker), [1, 2, 3])
    }

    func testACompressedBlockWithAnOverlappingBackReferenceIsExpanded() throws {
        let payload = compressedBlock(decodedSize: 17, sequences: overlappingSequences) + endMarker
        XCTAssertEqual(try decode(payload), Array("abcabcabcabcwxyz!".utf8))
    }

    func testABackReferenceAtDistanceOneRepeatsOneByte() throws {
        let sequences: [UInt8] = [0x13, 0x61, 1, 0, 0x50] + Array("12345".utf8)
        XCTAssertEqual(try decode(compressedBlock(decodedSize: 13, sequences: sequences) + endMarker), Array("aaaaaaaa12345".utf8))
    }

    func testExtendedLiteralAndMatchLengthsAreRead() throws {
        let literals = (0..<20).map { UInt8($0) }
        let literalOnly = compressedBlock(decodedSize: 20, sequences: [0xF0, 0x05] + literals)
        XCTAssertEqual(try decode(literalOnly + endMarker), literals)
        let longMatch = compressedBlock(decodedSize: 303, sequences: [0x2F] + Array("ab".utf8) + [2, 0, 0xFF, 26, 0x10, 0x7A])
        let expected = Array(String(repeating: "ab", count: 151).utf8) + [0x7A]
        XCTAssertEqual(try decode(longMatch + endMarker), expected)
    }

    func testSeveralBlocksInARowAreJoined() throws {
        let payload = storedBlock([1, 2]) + compressedBlock(decodedSize: 17, sequences: overlappingSequences) + storedBlock([]) + storedBlock([9])
            + endMarker
        XCTAssertEqual(try decode(payload), [1, 2] + Array("abcabcabcabcwxyz!".utf8) + [9])
    }

    func testAPayloadSliceWithAnOffsetStartIsDecoded() throws {
        let payload: [UInt8] = [0xEE, 0xEE, 0xEE] + storedBlock([5, 6]) + endMarker
        XCTAssertEqual(try AppleLZ4Decoder.decode(payload[3...], maximumDecodedBytes: generousLimit), [5, 6])
    }

    func testADecodedSizeExactlyAtTheLimitIsAccepted() throws {
        XCTAssertEqual(try decode(storedBlock([1, 2, 3, 4]) + storedBlock([5, 6]) + endMarker, limit: 6), [1, 2, 3, 4, 5, 6])
    }

    // MARK: Malformed input

    func testAnUnknownBlockMagicIsRefused() {
        assertDecodingThrows(Array("bv42".utf8) + [0, 0, 0, 0, 0, 0, 0, 0], .blockKindNotKnown)
        assertDecodingThrows([1, 2, 3, 4, 5, 6, 7, 8], .blockKindNotKnown)
        assertDecodingThrows(storedBlock([1]) + Array("junk".utf8), .blockKindNotKnown)
    }

    func testAPayloadTooShortForAMagicHasNoEndMarker() {
        assertDecodingThrows([], .endMarkerMissing)
        assertDecodingThrows(Array("bv".utf8), .endMarkerMissing)
    }

    func testABlockHeaderCutShortIsOutsideThePayload() {
        assertDecodingThrows(Array("bv41".utf8) + [1, 0, 0, 0] + [1, 0], .blockOutsidePayload)
        assertDecodingThrows(Array("bv41".utf8), .blockOutsidePayload)
        assertDecodingThrows(Array("bv4-".utf8) + [1, 0], .blockOutsidePayload)
    }

    func testAnEncodedSizePastThePayloadIsOutsideThePayload() {
        assertDecodingThrows(Array("bv41".utf8) + littleEndian(10) + littleEndian(50) + [0x10, 0x61], .blockOutsidePayload)
        assertDecodingThrows(Array("bv4-".utf8) + littleEndian(5) + [1, 2, 3], .blockOutsidePayload)
        assertDecodingThrows(Array("bv4-".utf8) + littleEndian(0xFFFF_FFFF) + [1, 2, 3], .blockOutsidePayload)
    }

    func testADeclaredDecodedSizeOfFourGibibytesIsRefusedImmediately() {
        let payload = Array("bv41".utf8) + littleEndian(0xFFFF_FFFF) + littleEndian(2) + [0x10, 0x61] + endMarker
        assertDecodingThrows(payload, .decodedSizeOverLimit(limitBytes: generousLimit))
        assertDecodingThrows(payload, .decodedSizeOverLimit(limitBytes: 64 * 1_048_576), limit: 64 * 1_048_576)
    }

    func testATotalOverTheLimitAcrossSeveralStoredBlocksIsRefused() {
        let payload = storedBlock([1, 2, 3, 4]) + storedBlock([5, 6, 7, 8]) + storedBlock([9, 10, 11, 12]) + endMarker
        assertDecodingThrows(payload, .decodedSizeOverLimit(limitBytes: 10), limit: 10)
        assertDecodingThrows(payload, .decodedSizeOverLimit(limitBytes: 11), limit: 11)
    }

    func testABackReferenceDistanceOfZeroIsDamaged() {
        let payload = compressedBlock(decodedSize: 6, sequences: [0x20, 0x61, 0x62, 0, 0]) + endMarker
        assertDecodingThrows(payload, .blockDamaged)
    }

    func testABackReferenceReachingBeforeTheBlocksOutputIsDamaged() {
        let beforeAnyOutput = compressedBlock(decodedSize: 5, sequences: [0x10, 0x61, 5, 0]) + endMarker
        assertDecodingThrows(beforeAnyOutput, .blockDamaged)
        let intoThePreviousBlock = storedBlock(Array("abcd".utf8)) + compressedBlock(decodedSize: 4, sequences: [0x00, 4, 0]) + endMarker
        assertDecodingThrows(intoThePreviousBlock, .blockDamaged)
    }

    func testLiteralsRunningPastTheBlockAreDamaged() {
        assertDecodingThrows(compressedBlock(decodedSize: 5, sequences: [0x50, 0x61, 0x62]) + endMarker, .blockDamaged)
        assertDecodingThrows(compressedBlock(decodedSize: 300, sequences: [0xF0, 0xFF]) + endMarker, .blockDamaged)
    }

    func testAMatchOffsetCutShortIsDamaged() {
        assertDecodingThrows(compressedBlock(decodedSize: 8, sequences: [0x11, 0x61, 1]) + endMarker, .blockDamaged)
    }

    func testAMatchLengthExtensionCutShortIsDamaged() {
        assertDecodingThrows(compressedBlock(decodedSize: 30, sequences: [0x1F, 0x61, 1, 0, 0xFF]) + endMarker, .blockDamaged)
    }

    func testOutputShorterThanDeclaredIsDamaged() {
        let sequences: [UInt8] = [0x50] + Array("hello".utf8)
        assertDecodingThrows(compressedBlock(decodedSize: 6, sequences: sequences) + endMarker, .blockDamaged)
    }

    func testOutputLongerThanDeclaredIsDamaged() {
        let sequences: [UInt8] = [0x50] + Array("hello".utf8)
        assertDecodingThrows(compressedBlock(decodedSize: 4, sequences: sequences) + endMarker, .blockDamaged)
        assertDecodingThrows(compressedBlock(decodedSize: 10, sequences: overlappingSequences) + endMarker, .blockDamaged)
    }

    func testAPayloadWithoutAnEndMarkerIsRefused() {
        assertDecodingThrows(storedBlock([1, 2, 3]), .endMarkerMissing)
        assertDecodingThrows(storedBlock([1, 2, 3]) + [0x62, 0x76], .endMarkerMissing)
    }

    // MARK: Fuzzing

    func testRandomDamageToAPayloadEndsInATypedErrorOrDecodedBytes() {
        let validPayload = storedBlock([1, 2, 3]) + compressedBlock(decodedSize: 17, sequences: overlappingSequences)
            + compressedBlock(decodedSize: 8, sequences: [0x13, 0x61, 1, 0, 0x00]) + endMarker
        var generator = AppleLZ4DecoderTestRandomNumberGenerator(seed: 0x5EED_0003)
        var failedCount = 0, succeededCount = 0
        for _ in 0..<5_000 {
            var damaged = validPayload
            for _ in 0..<Int.random(in: 1...3, using: &generator) {
                damaged[Int.random(in: 0..<damaged.count, using: &generator)] = UInt8.random(in: 0...255, using: &generator)
            }
            if Bool.random(using: &generator) { damaged.removeLast(Int.random(in: 0..<damaged.count, using: &generator)) }
            do throws(AppleLZ4Error) {
                _ = try AppleLZ4Decoder.decode(ArraySlice(damaged), maximumDecodedBytes: 4_096)
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
private struct AppleLZ4DecoderTestRandomNumberGenerator: RandomNumberGenerator {
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
