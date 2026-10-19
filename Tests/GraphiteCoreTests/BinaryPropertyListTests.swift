import XCTest
@testable import GraphiteCore

final class BinaryPropertyListTests: XCTestCase {
    private func propertyList(_ build: (inout BinaryPropertyListWriter) -> Int) throws -> BinaryPropertyList {
        var writer = BinaryPropertyListWriter()
        let top = build(&writer)
        return try BinaryPropertyList(bytes: writer.bytes(topObjectIndex: top)[...])
    }

    private func expectError(_ expected: BinaryPropertyListError, _ body: () throws(BinaryPropertyListError) -> Void,
                             file: StaticString = #filePath, line: UInt = #line) {
        do throws(BinaryPropertyListError) {
            try body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    func testEveryObjectKindIsDecoded() throws {
        var indices: [Int] = []
        let list = try propertyList { writer in
            indices = [writer.add(.null), writer.add(.boolean(true)), writer.add(.boolean(false)), writer.add(.integer(7)),
                       writer.add(.integer(70_000)), writer.add(.integer(-3)), writer.add(.real(2.5)), writer.add(.float(0.25)),
                       writer.add(.date(secondsSince2001: 814_000_000.5)), writer.add(.data([1, 2, 3])), writer.add(.string("ascii")),
                       writer.add(.string("é ✓ 𝄞")), writer.add(.uid(300)), writer.add(.array([3, 4])), writer.add(.set([4])),
                       writer.add(.dictionary(keys: [10], values: [3]))]
            return indices[13]
        }
        let expected: [BinaryPropertyListObject] = [
            .null, .boolean(true), .boolean(false), .integer(7), .integer(70_000), .integer(-3), .real(2.5), .real(0.25),
            .date(secondsSince2001: 814_000_000.5), .data([1, 2, 3]), .string("ascii"), .string("é ✓ 𝄞"), .uid(300),
            .array(memberIndices: [3, 4]), .set(memberIndices: [4]), .dictionary(keyIndices: [10], valueIndices: [3]),
        ]
        for (objectIndex, expectedObject) in zip(indices, expected) {
            XCTAssertEqual(try list.object(at: objectIndex), expectedObject)
        }
        XCTAssertEqual(list.topObjectIndex, indices[13])
    }

    func testLongDataAndStringsUseAFollowingLengthAndStaySlices() throws {
        let bytes = [UInt8](repeating: 9, count: 300)
        let list = try propertyList { writer in writer.add(.data(bytes)) }
        guard case .data(let slice) = try list.object(at: 0) else { return XCTFail("not data") }
        XCTAssertEqual(Array(slice), bytes)
        XCTAssertEqual(slice.startIndex, 8 + 4, "the slice indexes the list's own bytes after the marker and the 3-byte length")
    }

    func testWrongMagicAndShortInputAreNotPropertyLists() {
        expectError(.notBinaryPropertyList) { () throws(BinaryPropertyListError) in _ = try BinaryPropertyList(bytes: [UInt8](repeating: 0, count: 64)[...]) }
        expectError(.notBinaryPropertyList) { () throws(BinaryPropertyListError) in _ = try BinaryPropertyList(bytes: Array("bplist00".utf8)[...]) }
        var writer = BinaryPropertyListWriter()
        let topObjectIndex = writer.add(.integer(1))
        var bytes = writer.bytes(topObjectIndex: topObjectIndex)
        bytes[7] = UInt8(ascii: "1")
        expectError(.notBinaryPropertyList) { () throws(BinaryPropertyListError) in _ = try BinaryPropertyList(bytes: bytes[...]) }
    }

    func testTrailerWithImpossibleSizesIsRefused() {
        var writer = BinaryPropertyListWriter()
        let topObjectIndex = writer.add(.integer(1))
        let valid = writer.bytes(topObjectIndex: topObjectIndex)
        let trailerStart = valid.count - 32
        var hugeObjectCount = valid
        hugeObjectCount.replaceSubrange((trailerStart + 8)..<(trailerStart + 16), with: BinaryPropertyListWriter.bigEndian(UInt64(1) << 62, byteCount: 8))
        hugeObjectCount.replaceSubrange((trailerStart + 16)..<(trailerStart + 24), with: BinaryPropertyListWriter.bigEndian(0, byteCount: 8))
        expectError(.offsetTableOutsideFile) { () throws(BinaryPropertyListError) in _ = try BinaryPropertyList(bytes: hugeObjectCount[...]) }
        var maximumObjectCount = valid
        maximumObjectCount.replaceSubrange((trailerStart + 8)..<(trailerStart + 16), with: [UInt8](repeating: 0xFF, count: 8))
        expectError(.offsetTableOutsideFile) { () throws(BinaryPropertyListError) in _ = try BinaryPropertyList(bytes: maximumObjectCount[...]) }
        for offsetByteCount: UInt8 in [0, 9, 255] {
            var damaged = valid
            damaged[trailerStart + 6] = offsetByteCount
            expectError(.trailerDamaged) { () throws(BinaryPropertyListError) in _ = try BinaryPropertyList(bytes: damaged[...]) }
        }
        var topOutside = valid
        topOutside[trailerStart + 23] = 5
        expectError(.trailerDamaged) { () throws(BinaryPropertyListError) in _ = try BinaryPropertyList(bytes: topOutside[...]) }
        var tableOutside = valid
        tableOutside.replaceSubrange((trailerStart + 24)..<(trailerStart + 32), with: BinaryPropertyListWriter.bigEndian(UInt64(valid.count), byteCount: 8))
        expectError(.offsetTableOutsideFile) { () throws(BinaryPropertyListError) in _ = try BinaryPropertyList(bytes: tableOutside[...]) }
    }

    func testObjectOffsetOutsideTheObjectsIsRefused() throws {
        var writer = BinaryPropertyListWriter()
        let topObjectIndex = writer.add(.integer(1))
        var bytes = writer.bytes(topObjectIndex: topObjectIndex)
        let offsetTableOffset = bytes.count - 32 - 1
        bytes[offsetTableOffset] = UInt8(offsetTableOffset)
        let list = try BinaryPropertyList(bytes: bytes[...])
        expectError(.objectOffsetOutsideObjects(objectIndex: 0)) { () throws(BinaryPropertyListError) in _ = try list.object(at: 0) }
        expectError(.objectIndexOutOfRange(objectIndex: 1, objectCount: 1)) { () throws(BinaryPropertyListError) in _ = try list.object(at: 1) }
        expectError(.objectIndexOutOfRange(objectIndex: -1, objectCount: 1)) { () throws(BinaryPropertyListError) in _ = try list.object(at: -1) }
    }

    func testAnnouncedLengthsBeyondTheBytesAreRefusedBeforeAllocation() throws {
        let hugeLength = [0x13] + BinaryPropertyListWriter.bigEndian(UInt64(Int64.max), byteCount: 8)
        for marker: UInt8 in [0x4F, 0x5F, 0x6F, 0xAF, 0xCF, 0xDF] {
            let list = try propertyList { writer in writer.add(.raw([marker] + hugeLength)) }
            expectError(.objectTruncated(objectIndex: 0)) { () throws(BinaryPropertyListError) in _ = try list.object(at: 0) }
        }
        let negativeLength = try propertyList { writer in writer.add(.raw([0x4F, 0x13] + BinaryPropertyListWriter.bigEndian(UInt64.max, byteCount: 8))) }
        expectError(.objectTruncated(objectIndex: 0)) { () throws(BinaryPropertyListError) in _ = try negativeLength.object(at: 0) }
        let shortInteger = try propertyList { writer in writer.add(.raw([0x13, 1, 2])) }
        expectError(.objectTruncated(objectIndex: 0)) { () throws(BinaryPropertyListError) in _ = try shortInteger.object(at: 0) }
    }

    func testWideIntegersUnknownMarkersAndBadStringsAreTypedErrors() throws {
        let smallWideInteger = try propertyList { writer in writer.add(.raw([0x14] + [UInt8](repeating: 0, count: 15) + [3])) }
        XCTAssertEqual(try smallWideInteger.object(at: 0), .integer(3), "Foundation writes small numbers in 16 bytes too")
        let negativeWideInteger = try propertyList { writer in writer.add(.raw([0x14] + [UInt8](repeating: 0xFF, count: 16))) }
        XCTAssertEqual(try negativeWideInteger.object(at: 0), .integer(-1))
        let wideInteger = try propertyList { writer in writer.add(.raw([0x14, 1] + [UInt8](repeating: 0, count: 15))) }
        expectError(.integerTooWide(objectIndex: 0, byteCount: 16)) { () throws(BinaryPropertyListError) in _ = try wideInteger.object(at: 0) }
        let wideUID = try propertyList { writer in writer.add(.raw([0x8F] + [UInt8](repeating: 0, count: 16))) }
        expectError(.integerTooWide(objectIndex: 0, byteCount: 16)) { () throws(BinaryPropertyListError) in _ = try wideUID.object(at: 0) }
        for marker: UInt8 in [0x0F, 0x21, 0x34, 0x70, 0x90, 0xE0, 0xF0] {
            let list = try propertyList { writer in writer.add(.raw([marker, 0, 0, 0, 0, 0, 0, 0, 0])) }
            expectError(.objectMarkerUnknown(objectIndex: 0, marker: marker)) { () throws(BinaryPropertyListError) in _ = try list.object(at: 0) }
        }
        let highASCII = try propertyList { writer in writer.add(.raw([0x51, 0xC3])) }
        expectError(.stringNotDecodable(objectIndex: 0)) { () throws(BinaryPropertyListError) in _ = try highASCII.object(at: 0) }
        let loneSurrogate = try propertyList { writer in writer.add(.raw([0x61, 0xD8, 0x00])) }
        expectError(.stringNotDecodable(objectIndex: 0)) { () throws(BinaryPropertyListError) in _ = try loneSurrogate.object(at: 0) }
    }

    func testTruncationAtEveryByteNeverTraps() throws {
        var writer = BinaryPropertyListWriter()
        let tree = BinaryPropertyListWriter.Tree.dictionary([("numbers", .array([.integer(1), .real(2.5), .string("three")])),
                                                             ("data", .data([1, 2, 3, 4])), ("text", .string("ünïcode"))])
        let topObjectIndex = writer.add(tree: tree)
        let complete = writer.bytes(topObjectIndex: topObjectIndex)
        var refusedCutCount = 0
        for cut in 0..<complete.count {
            do throws(BinaryPropertyListError) {
                let list = try BinaryPropertyList(bytes: complete[..<cut])
                _ = try list.plainValue(ofObjectAt: list.topObjectIndex, maximumNestingDepth: 8)
            } catch {
                refusedCutCount += 1
            }
        }
        XCTAssertEqual(refusedCutCount, complete.count, "a list without its own trailer is never read")
    }

    func testPlainValueExpandsATree() throws {
        var writer = BinaryPropertyListWriter()
        let top = writer.add(tree: .dictionary([("kinds", .array([.string("line"), .string("line")])), ("width", .real(2))]))
        let list = try BinaryPropertyList(bytes: writer.bytes(topObjectIndex: top)[...])
        let value = try list.plainValue(ofObjectAt: top, maximumNestingDepth: 4)
        XCTAssertEqual(value.dictionary?.keys, ["kinds", "width"])
        XCTAssertEqual(value.dictionary?["kinds"], .array([.string("line"), .string("line")]))
        XCTAssertEqual(value.dictionary?["width"]?.number, 2)
    }

    func testAnArrayThatContainsItselfIsACycle() throws {
        var writer = BinaryPropertyListWriter()
        let array = writer.add(.null)
        writer.replace(array, with: .array([array]))
        let list = try BinaryPropertyList(bytes: writer.bytes(topObjectIndex: array)[...])
        expectError(.containerCycle(objectIndex: array)) { () throws(BinaryPropertyListError) in
            _ = try list.plainValue(ofObjectAt: array, maximumNestingDepth: 64)
        }
        let dictionary = writer.add(.null)
        let key = writer.add(.string("again"))
        writer.replace(dictionary, with: .dictionary(keys: [key], values: [dictionary]))
        let dictionaryList = try BinaryPropertyList(bytes: writer.bytes(topObjectIndex: dictionary)[...])
        expectError(.containerCycle(objectIndex: dictionary)) { () throws(BinaryPropertyListError) in
            _ = try dictionaryList.plainValue(ofObjectAt: dictionary, maximumNestingDepth: 64)
        }
    }

    func testNestingBeyondTheLimitIsRefused() throws {
        var writer = BinaryPropertyListWriter()
        var innermost = writer.add(.integer(1))
        for _ in 0..<10 { innermost = writer.add(.array([innermost])) }
        let list = try BinaryPropertyList(bytes: writer.bytes(topObjectIndex: innermost)[...])
        XCTAssertNoThrow(try list.plainValue(ofObjectAt: innermost, maximumNestingDepth: 10))
        expectError(.nestingTooDeep(limit: 9)) { () throws(BinaryPropertyListError) in _ = try list.plainValue(ofObjectAt: innermost, maximumNestingDepth: 9) }
    }

    func testSharedMembersThatWouldExpandExponentiallyStopAtTheBudget() throws {
        var writer = BinaryPropertyListWriter()
        var level = writer.add(.integer(1))
        for _ in 0..<40 { level = writer.add(.array([level, level])) }
        let bytes = writer.bytes(topObjectIndex: level)
        let list = try BinaryPropertyList(bytes: bytes[...])
        expectError(.valueCountOverBudget(budget: bytes.count)) { () throws(BinaryPropertyListError) in
            _ = try list.plainValue(ofObjectAt: level, maximumNestingDepth: 64)
        }
    }

    func testDictionaryKeysMustBeStrings() throws {
        var writer = BinaryPropertyListWriter()
        let key = writer.add(.integer(3))
        let dictionary = writer.add(.dictionary(keys: [key], values: [key]))
        let list = try BinaryPropertyList(bytes: writer.bytes(topObjectIndex: dictionary)[...])
        expectError(.dictionaryKeyNotString(objectIndex: key)) { () throws(BinaryPropertyListError) in
            _ = try list.plainValue(ofObjectAt: dictionary, maximumNestingDepth: 4)
        }
    }

    func testXMLDocumentsAreReadAndDeepNestingIsRefusedBeforeParsing() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>b</key><array><integer>2</integer><true/></array>\
        <key>a</key><real>1.5</real><key>c</key><data>AQID</data></dict></plist>
        """
        let value = try PropertyListDocument.plainValue(of: Array(xml.utf8)[...], maximumNestingDepth: 4)
        XCTAssertEqual(value.dictionary?.keys, ["a", "b", "c"])
        XCTAssertEqual(value.dictionary?["b"], .array([.integer(2), .boolean(true)]))
        XCTAssertEqual(value.dictionary?["c"], .data([1, 2, 3]))
        let deep = "<plist>" + String(repeating: "<array>", count: 100) + String(repeating: "</array>", count: 100) + "</plist>"
        XCTAssertThrowsError(try PropertyListDocument.plainValue(of: Array(deep.utf8)[...], maximumNestingDepth: 64)) { error in
            XCTAssertEqual(error as? PropertyListDocumentError, .nestingTooDeep(limit: 64))
        }
        XCTAssertThrowsError(try PropertyListDocument.plainValue(of: Array("<plist><dict>".utf8)[...], maximumNestingDepth: 64)) { error in
            XCTAssertEqual(error as? PropertyListDocumentError, .xmlNotReadable)
        }
    }
}
