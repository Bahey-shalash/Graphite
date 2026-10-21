import XCTest
@testable import NotebookImport

final class ProtocolBufferMessageTests: XCTestCase {
    private func varintBytes(_ number: UInt64) -> [UInt8] {
        var remaining = number
        var encoded: [UInt8] = []
        while remaining >= 0x80 {
            encoded.append(UInt8(remaining & 0x7F) | 0x80)
            remaining >>= 7
        }
        encoded.append(UInt8(remaining))
        return encoded
    }

    private func key(_ fieldNumber: Int, wireType: Int) -> [UInt8] { varintBytes(UInt64(fieldNumber << 3 | wireType)) }

    private func varintField(_ fieldNumber: Int, _ number: UInt64) -> [UInt8] { key(fieldNumber, wireType: 0) + varintBytes(number) }

    private func lengthDelimitedField(_ fieldNumber: Int, _ content: [UInt8]) -> [UInt8] {
        key(fieldNumber, wireType: 2) + varintBytes(UInt64(content.count)) + content
    }

    private func fixed32Field(_ fieldNumber: Int, _ bits: UInt32) -> [UInt8] {
        key(fieldNumber, wireType: 5) + (0..<4).map { byteIndex in UInt8((bits >> (8 * UInt32(byteIndex))) & 0xFF) }
    }

    private func fixed64Field(_ fieldNumber: Int, _ bits: UInt64) -> [UInt8] {
        key(fieldNumber, wireType: 1) + (0..<8).map { byteIndex in UInt8((bits >> (8 * UInt64(byteIndex))) & 0xFF) }
    }

    private func parse(_ messageBytes: [UInt8]) throws -> ProtocolBufferMessage {
        try ProtocolBufferMessage(parsing: ArraySlice(messageBytes))
    }

    private func assertParsingThrows(_ messageBytes: [UInt8], _ expected: ProtocolBufferError, line: UInt = #line) {
        XCTAssertThrowsError(try ProtocolBufferMessage(parsing: ArraySlice(messageBytes)), line: line) { error in
            XCTAssertEqual(error as? ProtocolBufferError, expected, line: line)
        }
    }

    // MARK: Normal behaviour

    func testVarintsOfOneToTenBytesAreRead() throws {
        for byteCount in 1...10 {
            let number: UInt64 = byteCount == 10 ? 1 << 63 : (1 << UInt64(7 * (byteCount - 1)))
            let encoded = varintBytes(number)
            XCTAssertEqual(encoded.count, byteCount)
            XCTAssertEqual(try parse(varintField(1, number)).varint(1), number)
        }
    }

    func testTheLargestUInt64VarintIsRead() throws {
        let encoded = varintField(3, UInt64.max)
        XCTAssertEqual(encoded.count, 1 + 10)
        XCTAssertEqual(try parse(encoded).varint(3), UInt64.max)
    }

    func testFixed32AndFixed64ValuesAreReadLittleEndian() throws {
        let message = try parse(fixed32Field(1, 0x0403_0201) + fixed64Field(2, 0x0807_0605_0403_0201))
        XCTAssertEqual(message.lastValue(1), .fixed32(0x0403_0201))
        XCTAssertEqual(message.lastValue(2), .fixed64(0x0807_0605_0403_0201))
    }

    func testAFloatFieldIsReadAsADouble() throws {
        XCTAssertEqual(try parse(fixed32Field(4, Float(1.5).bitPattern)).float(4), 1.5)
        XCTAssertEqual(try parse(fixed32Field(4, Float(-2).bitPattern)).float(4), -2)
    }

    func testLengthDelimitedFieldsGiveBytesStringsAndMessages() throws {
        let inner = varintField(2, 300) + lengthDelimitedField(3, Array("inner".utf8))
        let message = try parse(lengthDelimitedField(1, Array("h\u{E9}llo".utf8)) + lengthDelimitedField(5, inner))
        XCTAssertEqual(try message.string(1), "h\u{E9}llo")
        XCTAssertEqual(try message.bytes(1).map(Array.init), Array("h\u{E9}llo".utf8))
        let embedded = try message.message(5)
        XCTAssertEqual(try embedded.varint(2), 300)
        XCTAssertEqual(try embedded.string(3), "inner")
    }

    func testRepeatedFieldsKeepFileOrderAndTheLastOccurrenceWins() throws {
        let message = try parse(varintField(1, 10) + varintField(2, 99) + varintField(1, 20) + varintField(1, 30))
        XCTAssertEqual(message.values(1), [.varint(10), .varint(20), .varint(30)])
        XCTAssertEqual(try message.varint(1), 30)
        XCTAssertEqual(message.fields.map(\.number), [1, 2, 1, 1])
        XCTAssertEqual(message.fieldNumbers, [1, 2])
        XCTAssertTrue(message.contains(2))
        XCTAssertFalse(message.contains(3))
    }

    func testRepeatedMessagesAreReadInOrder() throws {
        let message = try parse(lengthDelimitedField(1, varintField(1, 1)) + lengthDelimitedField(1, varintField(1, 2))
                                + lengthDelimitedField(1, []))
        let messages = try message.messages(1)
        XCTAssertEqual(try messages.map { try $0.varint(1) }, [1, 2, nil])
    }

    func testAbsentFieldsReadAsTheirDefaults() throws {
        let message = try parse(varintField(1, 5))
        XCTAssertNil(try message.varint(9))
        XCTAssertEqual(try message.string(9), "")
        XCTAssertEqual(try message.float(9), 0)
        XCTAssertNil(try message.bytes(9))
        XCTAssertEqual(try message.message(9).fields, [])
        XCTAssertEqual(try message.messages(9).count, 0)
        XCTAssertEqual(message.values(9), [])
        XCTAssertNil(message.lastValue(9))
    }

    func testAnEmptyMessageHasNoFields() throws {
        let message = try parse([])
        XCTAssertEqual(message.fields, [])
        XCTAssertEqual(message.fieldNumbers, [])
        XCTAssertEqual(ProtocolBufferMessage.empty.fields, [])
    }

    func testAnEmptyLengthDelimitedFieldReadsAsAnEmptyStringAndAsZeroFloat() throws {
        let message = try parse(lengthDelimitedField(1, []))
        XCTAssertEqual(try message.string(1), "")
        XCTAssertEqual(try message.float(1), 0)
        XCTAssertEqual(try message.bytes(1)?.count, 0)
    }

    func testAMessageParsedFromASliceWithAnOffsetStartIsReadCorrectly() throws {
        let fullBytes: [UInt8] = [0xAA, 0xBB, 0xCC] + varintField(1, 77) + lengthDelimitedField(2, [1, 2, 3])
        let message = try ProtocolBufferMessage(parsing: fullBytes[3...])
        XCTAssertEqual(try message.varint(1), 77)
        XCTAssertEqual(try message.bytes(2).map(Array.init), [1, 2, 3])
    }

    func testLengthPrefixedRecordsAreSplit() {
        let fileBytes: [UInt8] = [3, 1, 2, 3, 0, 2, 9, 8]
        let result = ProtocolBufferMessage.lengthPrefixedRecords(in: ArraySlice(fileBytes))
        XCTAssertEqual(result.records.map(Array.init), [[1, 2, 3], [], [9, 8]])
        XCTAssertNil(result.failure)
    }

    func testNoBytesGiveNoLengthPrefixedRecords() {
        let result = ProtocolBufferMessage.lengthPrefixedRecords(in: [])
        XCTAssertEqual(result.records.count, 0)
        XCTAssertNil(result.failure)
    }

    // MARK: Malformed input

    func testAnElevenByteVarintIsMalformed() {
        assertParsingThrows([0x08] + [UInt8](repeating: 0x80, count: 10) + [0x01], .varintMalformed)
        assertParsingThrows([0x08] + [UInt8](repeating: 0xFF, count: 11), .varintMalformed)
    }

    func testATenByteVarintWithMoreThanBit63IsMalformed() {
        assertParsingThrows([0x08] + [UInt8](repeating: 0xFF, count: 9) + [0x02], .varintMalformed)
        assertParsingThrows([0x08] + [UInt8](repeating: 0xFF, count: 9) + [0x7F], .varintMalformed)
    }

    func testAVarintCutShortIsTruncated() {
        assertParsingThrows([0x08], .truncated)
        assertParsingThrows([0x08, 0x80], .truncated)
        assertParsingThrows([0x80], .truncated)
    }

    func testAKeyWithFieldNumberZeroIsRefused() {
        assertParsingThrows([0x00, 0x01], .fieldNumberZero)
        assertParsingThrows([0x02, 0x00], .fieldNumberZero)
    }

    func testGroupsAndUnassignedWireTypesAreRefused() {
        for wireType in [3, 4, 6, 7] {
            assertParsingThrows(key(1, wireType: wireType), .wireTypeNotSupported(wireType))
            assertParsingThrows(key(1, wireType: wireType) + [1, 2, 3, 4], .wireTypeNotSupported(wireType))
        }
    }

    func testALengthPrefixPastTheEndIsTruncated() {
        assertParsingThrows([0x0A, 0x05, 1, 2, 3], .truncated)
        assertParsingThrows([0x0A], .truncated)
    }

    func testAHugeLengthFailsAtOnce() {
        assertParsingThrows([0x0A] + varintBytes(1 << 60) + [1, 2, 3], .truncated)
        assertParsingThrows([0x0A] + varintBytes(UInt64.max) + [1], .truncated)
    }

    func testFixedWidthValuesCutShortAreTruncated() {
        assertParsingThrows(key(1, wireType: 5) + [1, 2, 3], .truncated)
        assertParsingThrows(key(1, wireType: 5), .truncated)
        assertParsingThrows(key(1, wireType: 1) + [1, 2, 3, 4, 5, 6, 7], .truncated)
    }

    func testAStringOfInvalidUTF8IsRefusedWithItsFieldNumber() throws {
        let message = try parse(lengthDelimitedField(6, [0xC3, 0x28]))
        XCTAssertThrowsError(try message.string(6)) { error in
            XCTAssertEqual(error as? ProtocolBufferError, .textNotUTF8(fieldNumber: 6))
        }
    }

    func testAFieldOfTheWrongWireTypeIsRefusedByEveryAccessor() throws {
        let message = try parse(varintField(1, 5) + lengthDelimitedField(2, [1]) + fixed64Field(3, 1))
        XCTAssertThrowsError(try message.message(1)) { error in
            XCTAssertEqual(error as? ProtocolBufferError, .unexpectedWireType(fieldNumber: 1))
        }
        XCTAssertThrowsError(try message.messages(1)) { error in
            XCTAssertEqual(error as? ProtocolBufferError, .unexpectedWireType(fieldNumber: 1))
        }
        XCTAssertThrowsError(try message.string(1)) { error in
            XCTAssertEqual(error as? ProtocolBufferError, .unexpectedWireType(fieldNumber: 1))
        }
        XCTAssertThrowsError(try message.bytes(1)) { error in
            XCTAssertEqual(error as? ProtocolBufferError, .unexpectedWireType(fieldNumber: 1))
        }
        XCTAssertThrowsError(try message.float(1)) { error in
            XCTAssertEqual(error as? ProtocolBufferError, .unexpectedWireType(fieldNumber: 1))
        }
        XCTAssertThrowsError(try message.varint(2)) { error in
            XCTAssertEqual(error as? ProtocolBufferError, .unexpectedWireType(fieldNumber: 2))
        }
        XCTAssertThrowsError(try message.float(3)) { error in
            XCTAssertEqual(error as? ProtocolBufferError, .unexpectedWireType(fieldNumber: 3))
        }
    }

    func testAnEmbeddedMessageThatIsDamagedFailsWhenItIsRead() throws {
        let message = try parse(lengthDelimitedField(1, [0x08]))
        XCTAssertThrowsError(try message.message(1)) { error in
            XCTAssertEqual(error as? ProtocolBufferError, .truncated)
        }
    }

    func testLengthPrefixedRecordsBeforeATruncatedOneAreReturnedWithTheFailure() {
        let fileBytes: [UInt8] = [2, 1, 2, 1, 7, 9, 5, 1]
        let result = ProtocolBufferMessage.lengthPrefixedRecords(in: ArraySlice(fileBytes))
        XCTAssertEqual(result.records.map(Array.init), [[1, 2], [7]])
        XCTAssertEqual(result.failure, .truncated)
    }

    func testLengthPrefixedRecordsStopAtAMalformedLengthVarint() {
        let fileBytes: [UInt8] = [1, 4] + [UInt8](repeating: 0xFF, count: 11)
        let result = ProtocolBufferMessage.lengthPrefixedRecords(in: ArraySlice(fileBytes))
        XCTAssertEqual(result.records.map(Array.init), [[4]])
        XCTAssertEqual(result.failure, .varintMalformed)
    }

    func testAHugeRecordLengthStopsLengthPrefixedRecordsAtOnce() {
        let result = ProtocolBufferMessage.lengthPrefixedRecords(in: ArraySlice(varintBytes(1 << 60) + [1, 2]))
        XCTAssertEqual(result.records.count, 0)
        XCTAssertEqual(result.failure, .truncated)
    }

    // MARK: Fuzzing

    func testRandomDamageToAMessageEndsInATypedErrorOrAReadMessage() {
        let inner = varintField(1, 1_000) + lengthDelimitedField(2, Array("text".utf8)) + fixed32Field(3, Float(2.5).bitPattern)
        let validBytes = varintField(1, UInt64.max) + lengthDelimitedField(2, inner) + fixed64Field(3, 99)
            + lengthDelimitedField(4, Array("name".utf8)) + lengthDelimitedField(2, inner)
        var generator = ProtocolBufferMessageTestRandomNumberGenerator(seed: 0x5EED_0002)
        var failedCount = 0, succeededCount = 0
        for _ in 0..<4_000 {
            var damaged = validBytes
            for _ in 0..<Int.random(in: 1...3, using: &generator) {
                damaged[Int.random(in: 0..<damaged.count, using: &generator)] = UInt8.random(in: 0...255, using: &generator)
            }
            if Bool.random(using: &generator) { damaged.removeLast(Int.random(in: 0..<damaged.count, using: &generator)) }
            do throws(ProtocolBufferError) {
                let message = try ProtocolBufferMessage(parsing: ArraySlice(damaged))
                for fieldNumber in 0...5 {
                    do throws(ProtocolBufferError) {
                        _ = try message.varint(fieldNumber)
                        _ = try message.string(fieldNumber)
                        _ = try message.float(fieldNumber)
                        _ = try message.messages(fieldNumber)
                    } catch { _ = error }
                }
                succeededCount += 1
            } catch {
                failedCount += 1
            }
            let records = ProtocolBufferMessage.lengthPrefixedRecords(in: ArraySlice(damaged))
            for record in records.records {
                XCTAssertTrue(record.startIndex >= 0 && record.endIndex <= damaged.count)
            }
        }
        XCTAssertGreaterThan(failedCount, 0)
        XCTAssertGreaterThan(succeededCount, 0)
    }
}

/// SplitMix64 with a fixed seed, so a failing sequence of damage can be replayed.
private struct ProtocolBufferMessageTestRandomNumberGenerator: RandomNumberGenerator {
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
