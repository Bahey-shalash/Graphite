import CoreGraphics
import Foundation

/// A version clock, `{1: counter, 2: replica hash}`. Last-writer-wins registers compare counters; elements are
/// drawn in the order of their position clocks.
struct GoodnotesClock: Hashable, Sendable {
    let counter: UInt64
    let replica: UInt64
}

/// A last-writer-wins register, `{1: value, 2: clock}`. The value's meaning depends on the register.
struct GoodnotesRegister: Sendable {
    let value: ProtocolBufferValue?
    let clock: GoodnotesClock

    /// The register that holds after `newer` is applied: the higher counter, or the later record when the counters
    /// are equal.
    static func latest(_ current: GoodnotesRegister?, _ newer: GoodnotesRegister) -> GoodnotesRegister {
        guard let current, current.clock.counter > newer.clock.counter else { return newer }
        return current
    }

    /// The value as a varint; nil when it is absent or another wire type.
    var varintValue: UInt64? {
        guard case .varint(let number) = value else { return nil }
        return number
    }

    /// The value as bytes; nil when it is absent or another wire type.
    var bytesValue: ArraySlice<UInt8>? {
        guard case .lengthDelimited(let bytes) = value else { return nil }
        return bytes
    }
}

/// A Goodnotes record: a protobuf message read in the shapes the format gives its values (points, sizes, colours,
/// clocks, registers, compressed payloads), with every failure reported as a `GoodnotesReadingError`. Absent fields
/// read as their defaults, as the reference reader reads them.
struct GoodnotesRecordFields: Sendable {
    let message: ProtocolBufferMessage

    static let empty = GoodnotesRecordFields(message: .empty)

    init(message: ProtocolBufferMessage) {
        self.message = message
    }

    init(parsing bytes: ArraySlice<UInt8>) throws(GoodnotesReadingError) {
        do throws(ProtocolBufferError) { message = try ProtocolBufferMessage(parsing: bytes) } catch { throw .protocolBuffer(error) }
    }

    var fieldNumbers: Set<Int> { message.fieldNumbers }

    func contains(_ fieldNumber: Int) -> Bool { message.contains(fieldNumber) }

    func varint(_ fieldNumber: Int) throws(GoodnotesReadingError) -> UInt64? {
        do throws(ProtocolBufferError) { return try message.varint(fieldNumber) } catch { throw .protocolBuffer(error) }
    }

    func string(_ fieldNumber: Int) throws(GoodnotesReadingError) -> String {
        do throws(ProtocolBufferError) { return try message.string(fieldNumber) } catch { throw .protocolBuffer(error) }
    }

    /// A string field, or nil when it is absent or empty.
    func nonEmptyString(_ fieldNumber: Int) throws(GoodnotesReadingError) -> String? {
        let text = try string(fieldNumber)
        return text.isEmpty ? nil : text
    }

    func bytes(_ fieldNumber: Int) throws(GoodnotesReadingError) -> ArraySlice<UInt8>? {
        do throws(ProtocolBufferError) { return try message.bytes(fieldNumber) } catch { throw .protocolBuffer(error) }
    }

    /// Whether the field is present with at least one byte: how the format marks an optional embedded message.
    func hasNonEmptyBytes(_ fieldNumber: Int) throws(GoodnotesReadingError) -> Bool {
        guard let bytes = try bytes(fieldNumber) else { return false }
        return !bytes.isEmpty
    }

    func fields(_ fieldNumber: Int) throws(GoodnotesReadingError) -> GoodnotesRecordFields {
        do throws(ProtocolBufferError) { return GoodnotesRecordFields(message: try message.message(fieldNumber)) } catch { throw .protocolBuffer(error) }
    }

    func repeatedFields(_ fieldNumber: Int) throws(GoodnotesReadingError) -> [GoodnotesRecordFields] {
        do throws(ProtocolBufferError) { return try message.messages(fieldNumber).map(GoodnotesRecordFields.init(message:)) } catch {
            throw .protocolBuffer(error)
        }
    }

    func float(_ fieldNumber: Int) throws(GoodnotesReadingError) -> Double {
        do throws(ProtocolBufferError) { return try message.float(fieldNumber) } catch { throw .protocolBuffer(error) }
    }

    /// `{1: x, 2: y}`.
    func point(_ fieldNumber: Int) throws(GoodnotesReadingError) -> CGPoint {
        try fields(fieldNumber).pointValue()
    }

    /// This record read as `{1: x, 2: y}`.
    func pointValue() throws(GoodnotesReadingError) -> CGPoint {
        CGPoint(x: try float(GoodnotesPointField.horizontal), y: try float(GoodnotesPointField.vertical))
    }

    /// `{1: width, 2: height}`.
    func size(_ fieldNumber: Int) throws(GoodnotesReadingError) -> CGSize {
        let size = try point(fieldNumber)
        return CGSize(width: size.x, height: size.y)
    }

    /// `{1: x, 2: y}` as a displacement.
    func vector(_ fieldNumber: Int) throws(GoodnotesReadingError) -> CGVector {
        let offset = try point(fieldNumber)
        return CGVector(dx: offset.x, dy: offset.y)
    }

    /// `{1: origin, 2: size}`.
    func rectangle(_ fieldNumber: Int) throws(GoodnotesReadingError) -> CGRect {
        let rectangle = try fields(fieldNumber)
        return CGRect(origin: try rectangle.point(GoodnotesRectangleField.origin), size: try rectangle.size(GoodnotesRectangleField.size))
    }

    /// `{1: red, 2: green, 3: blue, 4: alpha}`, each 0 to 1.
    func color(_ fieldNumber: Int) throws(GoodnotesReadingError) -> NotebookImportColor {
        let color = try fields(fieldNumber)
        return NotebookImportColor(red: try color.float(GoodnotesColorField.red), green: try color.float(GoodnotesColorField.green),
                                   blue: try color.float(GoodnotesColorField.blue), alpha: try color.float(GoodnotesColorField.alpha))
    }

    func clock(_ fieldNumber: Int) throws(GoodnotesReadingError) -> GoodnotesClock {
        let clock = try fields(fieldNumber)
        return GoodnotesClock(counter: try clock.varint(GoodnotesClockField.counter) ?? 0,
                              replica: try clock.varint(GoodnotesClockField.replica) ?? 0)
    }

    func register(_ fieldNumber: Int) throws(GoodnotesReadingError) -> GoodnotesRegister {
        let register = try fields(fieldNumber)
        return GoodnotesRegister(value: register.message.lastValue(GoodnotesRegisterField.value.rawValue),
                                 clock: try register.clock(GoodnotesRegisterField.clock))
    }

    /// A payload in Apple's LZ4 framing, decoded; an absent field decodes as an empty payload would, to an error.
    func compressedPayload(_ fieldNumber: Int, limits: NotebookImportLimits) throws(GoodnotesReadingError) -> [UInt8] {
        let payload = try bytes(fieldNumber) ?? []
        do throws(AppleLZ4Error) {
            return try AppleLZ4Decoder.decode(payload, maximumDecodedBytes: limits.maximumDecodedPayloadBytes)
        } catch {
            throw .compressedPayload(error)
        }
    }
}
