import XCTest
@testable import GraphiteCore

final class KeyedArchiveTests: XCTestCase {
    private let limits = NotebookImportLimits.standard

    private func archive(_ builder: KeyedArchiveBuilder, rootUID: Int, archiver: String = "GLKeyedArchiver",
                         rootKey: String = "$0") throws(KeyedArchiveError) -> KeyedArchive {
        try KeyedArchive(archiveBytes: builder.archiveBytes(rootUID: rootUID, archiver: archiver, rootKey: rootKey)[...], limits: limits)
    }

    private func expectError(_ expected: KeyedArchiveError, _ body: () throws(KeyedArchiveError) -> Void,
                             file: StaticString = #filePath, line: UInt = #line) {
        do throws(KeyedArchiveError) {
            try body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    func testRootIsFoundUnderDollarZeroOrRootWithEitherArchiver() throws {
        var builder = KeyedArchiveBuilder()
        let root = builder.object(className: "Root", [("answer", .integer(42))])
        for (archiver, rootKey) in [("GLKeyedArchiver", "$0"), ("NSKeyedArchiver", "root")] {
            let keyedArchive = try archive(builder, rootUID: root, archiver: archiver, rootKey: rootKey)
            guard case .object(let object) = try keyedArchive.rootValue() else { return XCTFail("root is not an object") }
            XCTAssertEqual(object.className, "Root")
            XCTAssertEqual(object.fields.keys, ["answer"])
            XCTAssertEqual(try keyedArchive.integer(keyedArchive.requiredValue(named: "answer", in: object.fields)), 42)
        }
        XCTAssertEqual(try archive(builder, rootUID: root, archiver: "NSKeyedArchiver").archiver, .nsKeyedArchiver)
    }

    func testOtherArchiversMissingRootsAndNonArchivesAreRefused() throws {
        var builder = KeyedArchiveBuilder()
        let root = builder.object(className: "Root", [])
        expectError(.archiverNotSupported(name: "OtherArchiver")) { () throws(KeyedArchiveError) in
            _ = try archive(builder, rootUID: root, archiver: "OtherArchiver")
        }
        expectError(.rootMissing) { () throws(KeyedArchiveError) in _ = try archive(builder, rootUID: root, rootKey: "elsewhere") }
        var writer = BinaryPropertyListWriter()
        let topObjectIndex = writer.add(tree: .dictionary([("kinds", .array([]))]))
        let plain = writer.bytes(topObjectIndex: topObjectIndex)
        expectError(.notKeyedArchive) { () throws(KeyedArchiveError) in _ = try KeyedArchive(archiveBytes: plain[...], limits: limits) }
        expectError(.propertyList(.notBinaryPropertyList)) { () throws(KeyedArchiveError) in
            _ = try KeyedArchive(archiveBytes: Array("not a plist at all, just some words here".utf8)[...], limits: limits)
        }
    }

    func testFoundationClassesAreReadByTheirTypedAccessors() throws {
        var builder = KeyedArchiveBuilder()
        let plainString = builder.string("plain")
        let mutableString = builder.object(className: "NSMutableString", [("NS.bytes", .data(Array("bytes ü".utf8)))])
        let wrappedString = builder.object(className: "NSString", [("NS.string", .string("wrapped"))])
        let data = builder.object(className: "NSMutableData", [("NS.data", .data([7, 8]))])
        let date = builder.object(className: "NSDate", [("NS.time", .real(814_059_731.25))])
        let uuidBytes: [UInt8] = Array(0..<16)
        let uuid = builder.object(className: "NSUUID", [("NS.uuidbytes", .data(uuidBytes))])
        let array = builder.array([plainString, mutableString], className: "NSMutableSet")
        let dictionary = builder.dictionary([("first", .integer(1)), ("second", .uid(wrappedString))], className: "NSMutableDictionary")
        let root = builder.object(className: "Root", [
            ("plain", .uid(plainString)), ("mutable", .uid(mutableString)), ("wrapped", .uid(wrappedString)), ("data", .uid(data)),
            ("rawData", .data([1])), ("date", .uid(date)), ("uuid", .uid(uuid)), ("array", .uid(array)), ("dictionary", .uid(dictionary)),
            ("real", .float(0.5)), ("flag", .boolean(true)), ("nothing", .uid(KeyedArchiveBuilder.nullUID)),
        ])
        let keyedArchive = try archive(builder, rootUID: root)
        let fields = try keyedArchive.fields(of: keyedArchive.rootValue())
        func value(_ key: String) throws -> KeyedArchiveValue { try keyedArchive.requiredValue(named: key, in: fields) }
        XCTAssertEqual(try keyedArchive.string(value("plain")), "plain")
        XCTAssertEqual(try keyedArchive.string(value("mutable")), "bytes ü")
        XCTAssertEqual(try keyedArchive.string(value("wrapped")), "wrapped")
        XCTAssertEqual(Array(try keyedArchive.data(value("data"))), [7, 8])
        XCTAssertEqual(Array(try keyedArchive.data(value("rawData"))), [1])
        XCTAssertEqual(try keyedArchive.date(value("date")), 814_059_731.25)
        XCTAssertEqual(try keyedArchive.uuid(value("uuid")), UUID(uuidString: "00010203-0405-0607-0809-0A0B0C0D0E0F"))
        XCTAssertEqual(try keyedArchive.number(value("real")), 0.5)
        XCTAssertEqual(try keyedArchive.boolean(value("flag")), true)
        XCTAssertEqual(try value("nothing"), .null)
        XCTAssertNil(try keyedArchive.nonNullValue(named: "nothing", in: fields))
        XCTAssertNil(try keyedArchive.value(named: "absent", in: fields))
        let members = try keyedArchive.members(of: value("array")).map { reference in try keyedArchive.string(keyedArchive.value(of: reference)) }
        XCTAssertEqual(members, ["plain", "bytes ü"])
        let entries = try keyedArchive.fields(of: value("dictionary"))
        XCTAssertEqual(entries.keys, ["first", "second"])
        XCTAssertEqual(try keyedArchive.string(keyedArchive.requiredValue(named: "second", in: entries)), "wrapped")
    }

    func testAccessorsOfTheWrongKindAndMissingKeysAreTypedErrors() throws {
        var builder = KeyedArchiveBuilder()
        let root = builder.object(className: "Root", [("number", .integer(3))])
        let keyedArchive = try archive(builder, rootUID: root)
        let fields = try keyedArchive.fields(of: keyedArchive.rootValue())
        let number = try keyedArchive.requiredValue(named: "number", in: fields)
        expectError(.valueNotOfExpectedKind(expected: .string, objectIndex: number.objectIndex)) { () throws(KeyedArchiveError) in
            _ = try keyedArchive.string(number)
        }
        expectError(.valueNotOfExpectedKind(expected: .array, objectIndex: number.objectIndex)) { () throws(KeyedArchiveError) in
            _ = try keyedArchive.members(of: number)
        }
        expectError(.valueNotOfExpectedKind(expected: .object, objectIndex: number.objectIndex)) { () throws(KeyedArchiveError) in
            _ = try keyedArchive.fields(of: number)
        }
        expectError(.keyMissing(key: "absent")) { () throws(KeyedArchiveError) in _ = try keyedArchive.requiredValue(named: "absent", in: fields) }
    }

    func testAChainOfUIDsThatComesBackIsACycle() throws {
        var builder = KeyedArchiveBuilder()
        let looping = builder.archive(.null)
        builder.replaceArchivedObject(looping, with: .uid(looping))
        let root = builder.object(className: "Root", [("loop", .uid(looping))])
        let keyedArchive = try archive(builder, rootUID: root)
        let fields = try keyedArchive.fields(of: keyedArchive.rootValue())
        XCTAssertThrowsError(try keyedArchive.value(named: "loop", in: fields)) { error in
            guard case .referenceCycle? = error as? KeyedArchiveError else { return XCTFail("\(error)") }
        }
    }

    func testAChainOfUIDsLongerThanTheLimitIsRefused() throws {
        var builder = KeyedArchiveBuilder()
        var link = builder.string("end")
        for _ in 0..<10 { link = builder.archive(.uid(link)) }
        let root = builder.object(className: "Root", [("chain", .uid(link))])
        var shortLimits = limits
        shortLimits.maximumArchiveReferenceDepth = 5
        let keyedArchive = try KeyedArchive(archiveBytes: builder.archiveBytes(rootUID: root)[...], limits: shortLimits)
        let fields = try keyedArchive.fields(of: keyedArchive.rootValue())
        expectError(.referenceChainTooLong(limit: 5)) { () throws(KeyedArchiveError) in _ = try keyedArchive.value(named: "chain", in: fields) }
        let roomyArchive = try archive(builder, rootUID: root)
        XCTAssertEqual(try roomyArchive.string(roomyArchive.requiredValue(named: "chain", in: roomyArchive.fields(of: roomyArchive.rootValue()))), "end")
    }

    func testAUIDPastTheObjectsIsRefused() throws {
        var builder = KeyedArchiveBuilder()
        let root = builder.object(className: "Root", [("far", .uid(9_999))])
        let keyedArchive = try archive(builder, rootUID: root)
        let fields = try keyedArchive.fields(of: keyedArchive.rootValue())
        XCTAssertThrowsError(try keyedArchive.value(named: "far", in: fields)) { error in
            guard case .referenceOutOfRange(uid: 9_999, _)? = error as? KeyedArchiveError else { return XCTFail("\(error)") }
        }
    }

    func testAClassThatNamesItsOwnObjectEndsWithoutAClassName() throws {
        var builder = KeyedArchiveBuilder()
        let selfClassed = builder.reserveObject()
        let classKey = builder.propertyListObject(.string("$class"))
        let classReference = builder.propertyListObject(.uid(selfClassed))
        builder.replaceArchivedObject(selfClassed, with: .dictionary(keys: [classKey], values: [classReference]))
        let root = builder.object(className: "Root", [("strange", .uid(selfClassed))])
        let keyedArchive = try archive(builder, rootUID: root)
        let fields = try keyedArchive.fields(of: keyedArchive.rootValue())
        XCTAssertThrowsError(try keyedArchive.value(named: "strange", in: fields)) { error in
            guard case .classNameMissing? = error as? KeyedArchiveError else { return XCTFail("\(error)") }
        }
    }

    func testCyclicGraphsAreNavigatedOneLevelAtATime() throws {
        var builder = KeyedArchiveBuilder()
        let parent = builder.reserveObject()
        let child = builder.object(className: "Child", [("parent", .uid(parent))])
        builder.replaceObject(parent, className: "Parent", [("child", .uid(child))])
        let selfContaining = builder.reserveObject()
        let member = builder.propertyListObject(.uid(selfContaining))
        builder.replaceObject(selfContaining, className: "NSArray", [("NS.objects", .object(.array([member])))])
        let root = builder.object(className: "Root", [("parent", .uid(parent)), ("array", .uid(selfContaining))])
        let keyedArchive = try archive(builder, rootUID: root)
        let rootFields = try keyedArchive.fields(of: keyedArchive.rootValue())
        var fields = rootFields
        for step in 0..<100 {
            fields = try keyedArchive.fields(of: keyedArchive.requiredValue(named: step.isMultiple(of: 2) ? "parent" : "child", in: fields))
        }
        XCTAssertEqual(fields.keys, ["parent"], "the hundredth step is a child")
        var array = try keyedArchive.requiredValue(named: "array", in: rootFields)
        for _ in 0..<100 {
            let members = try keyedArchive.members(of: array)
            XCTAssertEqual(members.count, 1)
            array = try keyedArchive.value(of: members[0])
        }
        guard case .object(let arrayObject) = array else { return XCTFail("not an object") }
        XCTAssertEqual(arrayObject.className, "NSArray")
    }
}
