import XCTest
@testable import NotebookImport

final class TplImageTests: XCTestCase {
    private func littleEndian(_ number: UInt64, byteCount: Int) -> [UInt8] {
        (0..<byteCount).map { byteIndex in UInt8((number >> (8 * UInt64(byteIndex))) & 0xFF) }
    }

    private func image(format: String, flags: UInt8 = 0, values: [UInt8]) -> [UInt8] {
        let body = Array(format.utf8) + [0] + values
        return Array("tpl".utf8) + [flags] + littleEndian(UInt64(8 + body.count), byteCount: 4) + body
    }

    private func assertImageThrows(_ imageBytes: [UInt8], _ expected: TplImageError, line: UInt = #line) {
        XCTAssertThrowsError(try TplImage(imageBytes), line: line) { error in
            XCTAssertEqual(error as? TplImageError, expected, line: line)
        }
    }

    private func assertCursorThrows(_ values: [UInt8], _ expected: TplImageError, line: UInt = #line,
                                    reading: (inout TplValueCursor) throws(TplImageError) -> Void) throws {
        var cursor = try TplImage(image(format: "x", values: values)).valueCursor()
        XCTAssertThrowsError(try reading(&cursor), line: line) { error in
            XCTAssertEqual(error as? TplImageError, expected, line: line)
        }
    }

    // MARK: Normal behaviour

    func testTheFormatStringAndValueBytesAreSeparated() throws {
        let tplImage = try TplImage(image(format: "vA(u)", values: [1, 2, 3]))
        XCTAssertEqual(tplImage.formatString, "vA(u)")
        XCTAssertEqual(Array(tplImage.valueBytes), [1, 2, 3])
    }

    func testAnImageWithoutValuesFinishesAtOnce() throws {
        let tplImage = try TplImage(image(format: "", values: []))
        XCTAssertEqual(tplImage.formatString, "")
        XCTAssertNoThrow(try tplImage.valueCursor().finish())
    }

    func testScalarsAndArraysAreReadInOrder() throws {
        var values: [UInt8] = littleEndian(0xBEEF, byteCount: 2) + littleEndian(0xDEAD_BEEF, byteCount: 4)
        values += littleEndian(3, byteCount: 4) + littleEndian(1, byteCount: 2) + littleEndian(2, byteCount: 2) + littleEndian(65_535, byteCount: 2)
        values += littleEndian(2, byteCount: 4) + [10, 0, 0, 0, 11, 0, 0, 0, 12, 0, 0, 0, 13, 0, 0, 0]
        values += littleEndian(1, byteCount: 4) + littleEndian(0x0102_0304_0506_0708, byteCount: 8)
        var cursor = try TplImage(image(format: "vuA(v)A(S(uu))A(f)", values: values)).valueCursor()
        XCTAssertEqual(try cursor.uint16(), 0xBEEF)
        XCTAssertEqual(try cursor.uint32(), 0xDEAD_BEEF)
        XCTAssertEqual(try cursor.uint16Array(), [1, 2, 65_535])
        XCTAssertEqual(try cursor.uint32Array(valuesPerElement: 2), [10, 11, 12, 13])
        XCTAssertEqual(try cursor.uint64Array(), [0x0102_0304_0506_0708])
        XCTAssertNoThrow(try cursor.finish())
    }

    func testEmptyArraysAreRead() throws {
        var cursor = try TplImage(image(format: "A(v)A(u)A(f)", values: [UInt8](repeating: 0, count: 12))).valueCursor()
        XCTAssertEqual(try cursor.uint16Array(), [])
        XCTAssertEqual(try cursor.uint32Array(valuesPerElement: 1), [])
        XCTAssertEqual(try cursor.uint64Array(), [])
        XCTAssertNoThrow(try cursor.finish())
    }

    // MARK: Malformed input

    func testBytesThatDoNotStartWithTplAreRefused() {
        assertImageThrows(image(format: "v", values: [1, 2]).enumerated().map { position, byte in position == 0 ? 0x54 : byte }, .notATplImage)
        assertImageThrows(Array("PNG".utf8) + [0, 9, 0, 0, 0, 0x76, 0, 1, 2], .notATplImage)
    }

    func testAnImageTooShortForItsHeaderIsRefused() {
        assertImageThrows([], .notATplImage)
        assertImageThrows(Array("tp".utf8), .notATplImage)
        assertImageThrows(Array("tpl".utf8) + [0, 8, 0, 0, 0], .notATplImage)
    }

    func testABigEndianImageIsRefused() {
        assertImageThrows(image(format: "v", flags: 1, values: [1, 2]), .bigEndianImage)
        assertImageThrows(image(format: "v", flags: 0x03, values: [1, 2]), .bigEndianImage)
    }

    func testAFormatStringWithoutATerminatorIsRefused() {
        assertImageThrows(Array("tpl".utf8) + [0, 20, 0, 0, 0] + Array("A(v)".utf8), .formatStringNotTerminated)
        assertImageThrows(Array("tpl".utf8) + [0, 9, 0, 0, 0, 0x76], .formatStringNotTerminated)
    }

    func testAnArrayCountOfTwoToThe31FailsWithoutAllocating() throws {
        let hugeCount = littleEndian(1 << 31, byteCount: 4)
        try assertCursorThrows(hugeCount + [1, 2, 3, 4], .valueOutsideImage) { cursor throws(TplImageError) in _ = try cursor.uint16Array() }
        try assertCursorThrows(hugeCount, .valueOutsideImage) { cursor throws(TplImageError) in _ = try cursor.uint32Array(valuesPerElement: 3) }
        try assertCursorThrows(hugeCount, .valueOutsideImage) { cursor throws(TplImageError) in _ = try cursor.uint64Array() }
        try assertCursorThrows(littleEndian(0xFFFF_FFFF, byteCount: 4), .valueOutsideImage) { cursor throws(TplImageError) in
            _ = try cursor.uint32Array(valuesPerElement: 1)
        }
    }

    func testAnArrayCountOneAboveTheBytesLeftIsRefused() throws {
        try assertCursorThrows(littleEndian(3, byteCount: 4) + [1, 0, 2, 0, 3], .valueOutsideImage) { cursor throws(TplImageError) in
            _ = try cursor.uint16Array()
        }
        try assertCursorThrows(littleEndian(2, byteCount: 4) + [UInt8](repeating: 0, count: 15), .valueOutsideImage) { cursor throws(TplImageError) in
            _ = try cursor.uint32Array(valuesPerElement: 2)
        }
    }

    func testValuesCutShortAreOutsideTheImage() throws {
        try assertCursorThrows([1], .valueOutsideImage) { cursor throws(TplImageError) in _ = try cursor.uint16() }
        try assertCursorThrows([1, 2, 3], .valueOutsideImage) { cursor throws(TplImageError) in _ = try cursor.uint32() }
        try assertCursorThrows([], .valueOutsideImage) { cursor throws(TplImageError) in _ = try cursor.uint16() }
        try assertCursorThrows([1, 0], .valueOutsideImage) { cursor throws(TplImageError) in _ = try cursor.uint16Array() }
        try assertCursorThrows(littleEndian(1, byteCount: 4) + [UInt8](repeating: 0, count: 7), .valueOutsideImage) { cursor throws(TplImageError) in
            _ = try cursor.uint64Array()
        }
    }

    func testBytesLeftAfterTheValuesAreReportedWithTheirCount() throws {
        var cursor = try TplImage(image(format: "v", values: [1, 0, 7, 8, 9])).valueCursor()
        XCTAssertEqual(try cursor.uint16(), 1)
        XCTAssertThrowsError(try cursor.finish()) { error in
            XCTAssertEqual(error as? TplImageError, .bytesLeftAfterValues(byteCount: 3))
        }
        let unread = try TplImage(image(format: "v", values: [1, 0])).valueCursor()
        XCTAssertThrowsError(try unread.finish()) { error in
            XCTAssertEqual(error as? TplImageError, .bytesLeftAfterValues(byteCount: 2))
        }
    }

    // MARK: Fuzzing

    func testRandomDamageToAnImageEndsInATypedErrorOrReadValues() {
        var values: [UInt8] = littleEndian(7, byteCount: 2) + littleEndian(9, byteCount: 4)
        values += littleEndian(2, byteCount: 4) + [1, 0, 2, 0] + littleEndian(1, byteCount: 4) + [1, 0, 0, 0, 2, 0, 0, 0]
        values += littleEndian(1, byteCount: 4) + littleEndian(5, byteCount: 8)
        let validImage = image(format: "vuA(v)A(S(uu))A(f)", values: values)
        var generator = TplImageTestRandomNumberGenerator(seed: 0x5EED_0004)
        var failedCount = 0, succeededCount = 0
        for _ in 0..<5_000 {
            var damaged = validImage
            for _ in 0..<Int.random(in: 1...3, using: &generator) {
                damaged[Int.random(in: 0..<damaged.count, using: &generator)] = UInt8.random(in: 0...255, using: &generator)
            }
            if Bool.random(using: &generator) { damaged.removeLast(Int.random(in: 0..<damaged.count, using: &generator)) }
            do throws(TplImageError) {
                var cursor = try TplImage(damaged).valueCursor()
                _ = try cursor.uint16()
                _ = try cursor.uint32()
                _ = try cursor.uint16Array()
                _ = try cursor.uint32Array(valuesPerElement: 2)
                _ = try cursor.uint64Array()
                try cursor.finish()
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
private struct TplImageTestRandomNumberGenerator: RandomNumberGenerator {
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
