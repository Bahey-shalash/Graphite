import Foundation

/// Writes Protocol Buffers wire format for the Goodnotes reader tests.
struct ProtocolBufferWriter {
    private(set) var bytes: [UInt8] = []

    static func varintBytes(_ number: UInt64) -> [UInt8] {
        var remaining = number
        var encoded: [UInt8] = []
        repeat {
            let low = UInt8(remaining & 0x7F)
            remaining >>= 7
            encoded.append(remaining == 0 ? low : low | 0x80)
        } while remaining != 0
        return encoded
    }

    @discardableResult
    mutating func varint(_ fieldNumber: Int, _ number: UInt64) -> ProtocolBufferWriter {
        bytes += Self.varintBytes(UInt64(fieldNumber) << 3) + Self.varintBytes(number)
        return self
    }

    @discardableResult
    mutating func lengthDelimited(_ fieldNumber: Int, _ contents: [UInt8]) -> ProtocolBufferWriter {
        bytes += Self.varintBytes(UInt64(fieldNumber) << 3 | 2) + Self.varintBytes(UInt64(contents.count)) + contents
        return self
    }

    @discardableResult
    mutating func string(_ fieldNumber: Int, _ text: String) -> ProtocolBufferWriter { lengthDelimited(fieldNumber, Array(text.utf8)) }

    @discardableResult
    mutating func message(_ fieldNumber: Int, _ message: ProtocolBufferWriter) -> ProtocolBufferWriter {
        lengthDelimited(fieldNumber, message.bytes)
    }

    @discardableResult
    mutating func float(_ fieldNumber: Int, _ number: Float) -> ProtocolBufferWriter {
        bytes += Self.varintBytes(UInt64(fieldNumber) << 3 | 5) + LittleEndianEncoding.bytes(number.bitPattern)
        return self
    }

    /// Fields built in a closure, for nested messages written inline.
    static func message(_ build: (inout ProtocolBufferWriter) -> Void) -> ProtocolBufferWriter {
        var writer = ProtocolBufferWriter()
        build(&writer)
        return writer
    }
}

/// Little-endian bytes of fixed-width integers.
enum LittleEndianEncoding {
    static func bytes(_ number: UInt16) -> [UInt8] { [UInt8(number & 0xFF), UInt8(number >> 8)] }

    static func bytes(_ number: UInt32) -> [UInt8] { (0..<4).map { byteIndex in UInt8((number >> (8 * UInt32(byteIndex))) & 0xFF) } }

    static func bytes(_ number: UInt64) -> [UInt8] { (0..<8).map { byteIndex in UInt8((number >> (8 * UInt64(byteIndex))) & 0xFF) } }
}

/// Writes a tpl image: `tpl`, flags, total size, the format string and the values the test appends in order.
struct TplImageWriter {
    let formatString: String
    private var values: [UInt8] = []

    init(formatString: String) { self.formatString = formatString }

    mutating func uint16(_ number: UInt16) { values += LittleEndianEncoding.bytes(number) }

    mutating func float(_ number: Float) { values += LittleEndianEncoding.bytes(number.bitPattern) }

    mutating func uint16Array(_ numbers: [UInt16]) {
        values += LittleEndianEncoding.bytes(UInt32(numbers.count))
        for number in numbers { uint16(number) }
    }

    /// `A(u)` or `A(S(u…u))`: `elementCount` elements of floats, flattened.
    mutating func floatArray(_ numbers: [Float], elementCount: Int) {
        values += LittleEndianEncoding.bytes(UInt32(elementCount))
        for number in numbers { float(number) }
    }

    mutating func rawUInt32Array(_ numbers: [UInt32], elementCount: Int) {
        values += LittleEndianEncoding.bytes(UInt32(elementCount))
        for number in numbers { values += LittleEndianEncoding.bytes(number) }
    }

    mutating func doubleArray(_ numbers: [UInt64]) {
        values += LittleEndianEncoding.bytes(UInt32(numbers.count))
        for number in numbers { values += LittleEndianEncoding.bytes(number) }
    }

    var bytes: [UInt8] {
        let header = Array("tpl".utf8) + [0]
        let format = Array(formatString.utf8) + [0]
        return header + LittleEndianEncoding.bytes(UInt32(8 + format.count + values.count)) + format + values
    }
}

/// Apple's LZ4 framing with one stored block, which the decoder reads like a compressed one.
func appleLZ4StoredPayload(_ contents: [UInt8]) -> [UInt8] {
    Array("bv4-".utf8) + LittleEndianEncoding.bytes(UInt32(contents.count)) + contents + Array("bv4$".utf8)
}

/// Goodnotes record shapes.
enum GoodnotesRecord {
    static func point(_ x: Float, _ y: Float) -> ProtocolBufferWriter {
        ProtocolBufferWriter.message { message in
            message.float(1, x)
            message.float(2, y)
        }
    }

    static func color(_ red: Float, _ green: Float, _ blue: Float, _ alpha: Float) -> ProtocolBufferWriter {
        ProtocolBufferWriter.message { message in
            message.float(1, red)
            message.float(2, green)
            message.float(3, blue)
            message.float(4, alpha)
        }
    }

    static func clock(counter: UInt64, replica: UInt64) -> ProtocolBufferWriter {
        ProtocolBufferWriter.message { message in
            message.varint(1, counter)
            message.varint(2, replica)
        }
    }

    /// A drawing position `{1: clock}`.
    static func position(counter: UInt64, replica: UInt64) -> ProtocolBufferWriter {
        ProtocolBufferWriter.message { message in message.message(1, clock(counter: counter, replica: replica)) }
    }

    static func register(text: String, counter: UInt64) -> ProtocolBufferWriter {
        ProtocolBufferWriter.message { message in
            message.string(1, text)
            message.message(2, clock(counter: counter, replica: 1))
        }
    }

    static func register(number: UInt64, counter: UInt64) -> ProtocolBufferWriter {
        ProtocolBufferWriter.message { message in
            message.varint(1, number)
            message.message(2, clock(counter: counter, replica: 1))
        }
    }

    /// An event `{1: entity, <kind>: body}`.
    static func event(entity: String, kind: Int, body: ProtocolBufferWriter) -> [UInt8] {
        ProtocolBufferWriter.message { message in
            message.string(1, entity)
            message.message(kind, body)
        }.bytes
    }

    /// An element header `{1: id, 2: clock, 3: deleted, 6: order id, 16: schema}`.
    static func header(_ elementIdentifier: String, isDeleted: Bool = false, orderIdentifier: String? = nil) -> [UInt8] {
        ProtocolBufferWriter.message { message in
            message.string(1, elementIdentifier)
            message.message(2, clock(counter: 1, replica: 1))
            if isDeleted { message.varint(3, 1) }
            if let orderIdentifier { message.string(6, orderIdentifier) }
            message.varint(16, 24)
        }.bytes
    }

    /// An element body `{<kind>: fields}`.
    static func body(kind: Int, _ fields: ProtocolBufferWriter) -> [UInt8] {
        ProtocolBufferWriter.message { message in message.message(kind, fields) }.bytes
    }

    static func lengthPrefixed(_ records: [[UInt8]]) -> [UInt8] {
        records.flatMap { record in ProtocolBufferWriter.varintBytes(UInt64(record.count)) + record }
    }

    /// A constant-width path image: the given subpaths of quadratic curves, a width and a dash pattern.
    static func constantWidthPath(width: Float, subpaths: [(start: (Float, Float), curves: [(Float, Float, Float, Float)])],
                                  dashPattern: [Float] = []) -> [UInt8] {
        var image = TplImageWriter(formatString: "vuA(v)A(S(uu))A(S(uuuu))vA(f)")
        image.uint16(2)
        image.float(width)
        image.uint16Array(subpaths.flatMap { subpath in [0] + Array(repeating: 1, count: subpath.curves.count) })
        image.floatArray(subpaths.flatMap { subpath in [subpath.start.0, subpath.start.1] }, elementCount: subpaths.count)
        let curves = subpaths.flatMap(\.curves)
        image.floatArray(curves.flatMap { curve in [curve.0, curve.1, curve.2, curve.3] }, elementCount: curves.count)
        image.uint16(1)
        image.doubleArray(dashPattern.map { length in UInt64(length.bitPattern) })
        return image.bytes
    }

    /// A stroke body: path, colour and position, with optional fields added by `extra`.
    static func stroke(_ identifier: String, path: [UInt8], position: (UInt64, UInt64),
                       extra: (inout ProtocolBufferWriter) -> Void = { _ in }) -> [UInt8] {
        body(kind: 7, ProtocolBufferWriter.message { message in
            message.string(1, identifier)
            message.lengthDelimited(2, appleLZ4StoredPayload(path))
            message.message(4, color(0, 0, 0, 1))
            message.message(7, GoodnotesRecord.position(counter: position.0, replica: position.1))
            extra(&message)
        })
    }
}

/// A Goodnotes notebook archive built entry by entry.
struct GoodnotesNotebookBuilder {
    var schemaVersion: UInt64? = 24
    var events: [[UInt8]] = []
    var layers: [String: [[UInt8]]] = [:]
    var attachments: [String: [UInt8]] = [:]

    func archiveBytes() -> Data {
        var archive = ZipArchiveBuilder()
        let schema = schemaVersion.map { version in ProtocolBufferWriter.message { message in message.varint(1, version) }.bytes } ?? []
        archive.addEntry(named: "schema.pb", contents: schema)
        archive.addEntry(named: "index.events.pb", contents: GoodnotesRecord.lengthPrefixed(events))
        for (layerIdentifier, records) in layers.sorted(by: { left, right in left.key < right.key }) {
            archive.addEntry(named: "notes/\(layerIdentifier)", contents: GoodnotesRecord.lengthPrefixed(records))
        }
        for (fileIdentifier, contents) in attachments.sorted(by: { left, right in left.key < right.key }) {
            archive.addEntry(named: "attachments/\(fileIdentifier)", contents: contents, compression: .stored)
        }
        return archive.archiveBytes()
    }

    /// A page created with a paper and a position.
    mutating func addPage(_ pageIdentifier: String, position: String, paper: String, counter: UInt64 = 1) {
        events.append(GoodnotesRecord.event(entity: pageIdentifier, kind: 54, body: ProtocolBufferWriter.message { message in
            message.string(1, "DOCUMENT")
            message.string(2, pageIdentifier)
            message.message(3, GoodnotesRecord.register(text: paper, counter: counter))
            message.message(4, GoodnotesRecord.register(text: position, counter: counter))
        }))
    }

    mutating func addPaper(_ paperIdentifier: String, attachment: String, width: Float, height: Float, template: String) {
        events.append(GoodnotesRecord.event(entity: paperIdentifier, kind: 2, body: ProtocolBufferWriter.message { message in
            message.string(4, attachment)
            message.varint(5, 1)
            message.message(8, GoodnotesRecord.point(width, height))
            message.string(9, template)
        }))
    }

    mutating func addAttachment(_ attachmentIdentifier: String, fileIdentifier: String, contents: [UInt8], pdfPageCount: UInt64?) {
        events.append(GoodnotesRecord.event(entity: attachmentIdentifier, kind: 6, body: ProtocolBufferWriter.message { message in
            message.string(1, attachmentIdentifier)
            message.string(2, fileIdentifier)
            message.varint(5, UInt64(contents.count))
            if let pdfPageCount {
                message.message(12, ProtocolBufferWriter.message { count in
                    count.varint(1, 1)
                    count.varint(2, pdfPageCount)
                })
            }
        }))
        attachments[fileIdentifier] = contents
    }
}
