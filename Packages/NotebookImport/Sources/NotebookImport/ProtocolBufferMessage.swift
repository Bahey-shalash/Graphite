import Foundation

/// Why bytes could not be read as Protocol Buffers wire format.
public enum ProtocolBufferError: Error, Hashable, Sendable {
    /// A varint runs past ten bytes or past 64 bits.
    case varintMalformed
    /// A field or a length-prefixed record runs past the end of the bytes that hold it.
    case truncated
    case fieldNumberZero
    /// Groups (wire types 3 and 4) and the unassigned wire types 6 and 7.
    case wireTypeNotSupported(Int)
    /// A field holds another wire type than its meaning needs, such as a number where a message belongs.
    case unexpectedWireType(fieldNumber: Int)
    case textNotUTF8(fieldNumber: Int)
}

/// One field value as the wire format stores it, without a schema to say what it means.
enum ProtocolBufferValue: Hashable, Sendable {
    case varint(UInt64)
    case fixed64(UInt64)
    case fixed32(UInt32)
    case lengthDelimited(ArraySlice<UInt8>)
}

struct ProtocolBufferField: Hashable, Sendable {
    let number: Int
    let value: ProtocolBufferValue
}

/// A Protocol Buffers message read without a schema: its fields in file order, repeated fields kept. Accessors take
/// the last occurrence of a field, as protobuf does for a field that is not repeated, and read an absent field as its
/// default (zero, empty), as proto3 leaves defaults out. Slices share the bytes they were read from.
struct ProtocolBufferMessage: Sendable {
    private static let maximumVarintBytes = 10

    let fields: [ProtocolBufferField]

    static let empty = ProtocolBufferMessage(fields: [])

    private init(fields: [ProtocolBufferField]) {
        self.fields = fields
    }

    init(parsing bytes: ArraySlice<UInt8>) throws(ProtocolBufferError) {
        var fields: [ProtocolBufferField] = []
        var offset = bytes.startIndex
        while offset < bytes.endIndex {
            let key = try Self.varint(in: bytes, at: &offset)
            let fieldNumber = Int(truncatingIfNeeded: key >> 3)
            guard fieldNumber != 0 else { throw ProtocolBufferError.fieldNumberZero }
            fields.append(ProtocolBufferField(number: fieldNumber, value: try Self.value(wireType: Int(key & 7), in: bytes, at: &offset)))
        }
        self.fields = fields
    }

    /// The messages of a file in which each is preceded by its length as a varint. Reading stops at the first record
    /// that runs past the end; the records before it are returned with the failure.
    static func lengthPrefixedRecords(in bytes: ArraySlice<UInt8>) -> (records: [ArraySlice<UInt8>], failure: ProtocolBufferError?) {
        var records: [ArraySlice<UInt8>] = []
        var offset = bytes.startIndex
        while offset < bytes.endIndex {
            do throws(ProtocolBufferError) {
                let length = try varint(in: bytes, at: &offset)
                guard length <= UInt64(bytes.endIndex - offset) else { throw ProtocolBufferError.truncated }
                records.append(bytes[offset..<(offset + Int(length))])
                offset += Int(length)
            } catch {
                return (records, error)
            }
        }
        return (records, nil)
    }

    var fieldNumbers: Set<Int> { Set(fields.map(\.number)) }

    func contains(_ fieldNumber: Int) -> Bool { fields.contains { field in field.number == fieldNumber } }

    func lastValue(_ fieldNumber: Int) -> ProtocolBufferValue? {
        fields.last { field in field.number == fieldNumber }?.value
    }

    func values(_ fieldNumber: Int) -> [ProtocolBufferValue] {
        fields.compactMap { field in field.number == fieldNumber ? field.value : nil }
    }

    /// The bytes of a length-delimited field, or nil when the field is absent.
    func bytes(_ fieldNumber: Int) throws(ProtocolBufferError) -> ArraySlice<UInt8>? {
        guard let value = lastValue(fieldNumber) else { return nil }
        return try Self.bytes(of: value, fieldNumber: fieldNumber)
    }

    /// The embedded message of a field; an absent field is an empty message.
    func message(_ fieldNumber: Int) throws(ProtocolBufferError) -> ProtocolBufferMessage {
        guard let bytes = try bytes(fieldNumber) else { return .empty }
        return try ProtocolBufferMessage(parsing: bytes)
    }

    /// Every occurrence of a repeated message field, in file order.
    func messages(_ fieldNumber: Int) throws(ProtocolBufferError) -> [ProtocolBufferMessage] {
        var messages: [ProtocolBufferMessage] = []
        for value in values(fieldNumber) { messages.append(try ProtocolBufferMessage(parsing: Self.bytes(of: value, fieldNumber: fieldNumber))) }
        return messages
    }

    /// A UTF-8 string field; an absent field is the empty string.
    func string(_ fieldNumber: Int) throws(ProtocolBufferError) -> String {
        guard let bytes = try bytes(fieldNumber) else { return "" }
        return try Self.string(from: bytes, fieldNumber: fieldNumber)
    }

    /// A varint field, or nil when the field is absent.
    func varint(_ fieldNumber: Int) throws(ProtocolBufferError) -> UInt64? {
        guard let value = lastValue(fieldNumber) else { return nil }
        guard case .varint(let number) = value else { throw ProtocolBufferError.unexpectedWireType(fieldNumber: fieldNumber) }
        return number
    }

    /// A 32-bit float field; an absent or empty field is 0.
    func float(_ fieldNumber: Int) throws(ProtocolBufferError) -> Double {
        switch lastValue(fieldNumber) {
        case nil:
            return 0
        case .fixed32(let bits):
            return Double(Float(bitPattern: bits))
        case .lengthDelimited(let bytes) where bytes.isEmpty:
            return 0
        case .varint, .fixed64, .lengthDelimited:
            throw ProtocolBufferError.unexpectedWireType(fieldNumber: fieldNumber)
        }
    }

    static func string(from bytes: ArraySlice<UInt8>, fieldNumber: Int) throws(ProtocolBufferError) -> String {
        guard let text = String(validating: bytes, as: UTF8.self) else { throw ProtocolBufferError.textNotUTF8(fieldNumber: fieldNumber) }
        return text
    }

    static func bytes(of value: ProtocolBufferValue, fieldNumber: Int) throws(ProtocolBufferError) -> ArraySlice<UInt8> {
        guard case .lengthDelimited(let bytes) = value else { throw ProtocolBufferError.unexpectedWireType(fieldNumber: fieldNumber) }
        return bytes
    }

    private static func value(wireType: Int, in bytes: ArraySlice<UInt8>, at offset: inout Int) throws(ProtocolBufferError) -> ProtocolBufferValue {
        switch wireType {
        case 0:
            return .varint(try varint(in: bytes, at: &offset))
        case 1:
            return .fixed64(try littleEndianInteger(UInt64.self, in: bytes, at: &offset))
        case 5:
            return .fixed32(try littleEndianInteger(UInt32.self, in: bytes, at: &offset))
        case 2:
            let length = try varint(in: bytes, at: &offset)
            guard length <= UInt64(bytes.endIndex - offset) else { throw ProtocolBufferError.truncated }
            defer { offset += Int(length) }
            return .lengthDelimited(bytes[offset..<(offset + Int(length))])
        default:
            throw ProtocolBufferError.wireTypeNotSupported(wireType)
        }
    }

    private static func varint(in bytes: ArraySlice<UInt8>, at offset: inout Int) throws(ProtocolBufferError) -> UInt64 {
        var number: UInt64 = 0
        for byteIndex in 0..<maximumVarintBytes {
            guard offset < bytes.endIndex else { throw ProtocolBufferError.truncated }
            let byte = bytes[offset]
            offset += 1
            let payload = UInt64(byte & 0x7F)
            // The tenth byte holds bit 63 only.
            guard byteIndex < maximumVarintBytes - 1 || payload <= 1 else { throw ProtocolBufferError.varintMalformed }
            number |= payload << (7 * UInt64(byteIndex))
            if byte & 0x80 == 0 { return number }
        }
        throw ProtocolBufferError.varintMalformed
    }

    private static func littleEndianInteger<Integer: FixedWidthInteger>(_ type: Integer.Type, in bytes: ArraySlice<UInt8>,
                                                                       at offset: inout Int) throws(ProtocolBufferError) -> Integer {
        guard let number = LittleEndianInteger.read(type, in: bytes, at: offset) else { throw ProtocolBufferError.truncated }
        offset += MemoryLayout<Integer>.size
        return number
    }
}
