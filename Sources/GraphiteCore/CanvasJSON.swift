import Foundation

/// Why a `.canvas` file could not be read. Each message says the file was left alone,
/// since a canvas Graphite cannot read is never rewritten.
public enum CanvasFileError: Error, LocalizedError, Equatable {
    case oversized
    case notUTF8
    /// - Parameter byteOffset: Where reading stopped, counted from the start of the file.
    case invalidJSON(byteOffset: Int, reason: String)
    case notAnObject
    case nestedTooDeeply
    case tooManyValues
    /// - Parameter listName: `nodes` or `edges`.
    case listIsNotAnArray(listName: String)
    case tooManyCards
    case tooManyConnections
    /// An edit named a card or connection that the file no longer has.
    case missingItem
    /// An edit would have produced a file Graphite could not read back.
    case editNotApplied

    private static let leftUnchanged = " Graphite has left the file as it is."

    public var errorDescription: String? {
        switch self {
        case .oversized: "This canvas is larger than Graphite opens (\(CanvasFile.maximumSourceBytes / 1_048_576) MB)." + Self.leftUnchanged
        case .notUTF8: "This canvas is not UTF-8 text." + Self.leftUnchanged
        case .invalidJSON(let byteOffset, let reason): "This canvas is damaged: \(reason) at byte \(byteOffset)." + Self.leftUnchanged
        case .notAnObject: "This canvas is damaged: it does not start with a JSON object." + Self.leftUnchanged
        case .nestedTooDeeply: "This canvas is nested more deeply than Graphite reads." + Self.leftUnchanged
        case .tooManyValues: "This canvas holds more values than Graphite reads." + Self.leftUnchanged
        case .listIsNotAnArray(let listName): "This canvas is damaged: “\(listName)” is not a list." + Self.leftUnchanged
        case .tooManyCards: "This canvas has more than \(CanvasFile.maximumNodeCount.formatted()) cards, more than Graphite shows." + Self.leftUnchanged
        case .tooManyConnections: "This canvas has more than \(CanvasFile.maximumEdgeCount.formatted()) connections, more than Graphite shows." + Self.leftUnchanged
        case .missingItem: "The card or connection is no longer in this canvas."
        case .editNotApplied: "The change could not be written safely, so the canvas was left as it is."
        }
    }
}

/// One JSON value of a canvas file with the bytes it is written in, so an edit can
/// replace exactly those bytes and leave every other byte of the file as it is.
struct CanvasJSONValue: Sendable {
    indirect enum Content: Sendable {
        case object([Member])
        case array([CanvasJSONValue])
        case string(String)
        case number(Double)
        case boolean(Bool)
        case null
    }

    struct Member: Sendable {
        let key: String
        /// The key's bytes, quotes included.
        let keyRange: Range<Int>
        let value: CanvasJSONValue
    }

    let content: Content
    /// The value's bytes in the file, without the whitespace around it.
    let range: Range<Int>

    var members: [Member]? {
        if case .object(let members) = content { return members }
        return nil
    }

    var elements: [CanvasJSONValue]? {
        if case .array(let elements) = content { return elements }
        return nil
    }

    var string: String? {
        if case .string(let text) = content { return text }
        return nil
    }

    var number: Double? {
        if case .number(let number) = content { return number }
        return nil
    }

    /// The member with this key. When a key is written twice the last one counts, as
    /// JavaScript's `JSON.parse` reads it.
    func member(_ key: String) -> Member? {
        members?.last { member in member.key == key }
    }
}

/// Reads JSON as the standard defines it (RFC 8259), keeping where each value is written.
/// A UTF-8 byte-order mark before the value is allowed and kept.
struct CanvasJSONParser {
    /// Canvas files nest three levels; unknown keys may hold more. A parser that recurses
    /// once per level must not follow a hostile file down the stack.
    static let maximumNestingDepth = 64
    static let maximumValueCount = 2_000_000
    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    private let bytes: [UInt8]
    private var position = 0
    private var valueCount = 0

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// - Parameter bytes: Valid UTF-8; the caller checks that first.
    static func parse(_ bytes: [UInt8]) throws -> CanvasJSONValue {
        var parser = CanvasJSONParser(bytes: bytes)
        if bytes.starts(with: byteOrderMark) { parser.position = byteOrderMark.count }
        parser.skipWhitespace()
        let value = try parser.parseValue(depth: 0)
        parser.skipWhitespace()
        guard parser.position == bytes.count else { throw parser.failure("there is text after the end of the canvas") }
        return value
    }

    private func failure(_ reason: String) -> CanvasFileError {
        .invalidJSON(byteOffset: position, reason: reason)
    }

    private mutating func skipWhitespace() {
        while position < bytes.count {
            let byte = bytes[position]
            guard byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 else { return }
            position += 1
        }
    }

    private mutating func parseValue(depth: Int) throws -> CanvasJSONValue {
        guard depth <= Self.maximumNestingDepth else { throw CanvasFileError.nestedTooDeeply }
        valueCount += 1
        guard valueCount <= Self.maximumValueCount else { throw CanvasFileError.tooManyValues }
        guard position < bytes.count else { throw failure("the file ends where a value is expected") }
        let start = position
        switch bytes[position] {
        case UInt8(ascii: "{"):
            return try parseObject(depth: depth)
        case UInt8(ascii: "["):
            return try parseArray(depth: depth)
        case UInt8(ascii: "\""):
            let text = try parseString()
            return CanvasJSONValue(content: .string(text), range: start..<position)
        case UInt8(ascii: "t"):
            try consume(literal: "true")
            return CanvasJSONValue(content: .boolean(true), range: start..<position)
        case UInt8(ascii: "f"):
            try consume(literal: "false")
            return CanvasJSONValue(content: .boolean(false), range: start..<position)
        case UInt8(ascii: "n"):
            try consume(literal: "null")
            return CanvasJSONValue(content: .null, range: start..<position)
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            let number = try parseNumber()
            return CanvasJSONValue(content: .number(number), range: start..<position)
        default:
            throw failure("a value is expected")
        }
    }

    private mutating func consume(literal: StaticString) throws {
        let literalBytes = UnsafeBufferPointer(start: literal.utf8Start, count: literal.utf8CodeUnitCount)
        guard position + literalBytes.count <= bytes.count, bytes[position..<position + literalBytes.count].elementsEqual(literalBytes) else {
            throw failure("a value is expected")
        }
        position += literalBytes.count
    }

    private mutating func parseObject(depth: Int) throws -> CanvasJSONValue {
        let start = position
        position += 1
        var members: [CanvasJSONValue.Member] = []
        skipWhitespace()
        if position < bytes.count, bytes[position] == UInt8(ascii: "}") {
            position += 1
            return CanvasJSONValue(content: .object(members), range: start..<position)
        }
        while true {
            skipWhitespace()
            guard position < bytes.count, bytes[position] == UInt8(ascii: "\"") else { throw failure("a key in quotes is expected") }
            let keyStart = position
            let key = try parseString()
            let keyRange = keyStart..<position
            skipWhitespace()
            guard position < bytes.count, bytes[position] == UInt8(ascii: ":") else { throw failure("a colon is expected after a key") }
            position += 1
            skipWhitespace()
            let value = try parseValue(depth: depth + 1)
            members.append(CanvasJSONValue.Member(key: key, keyRange: keyRange, value: value))
            skipWhitespace()
            guard position < bytes.count else { throw failure("the file ends inside an object") }
            if bytes[position] == UInt8(ascii: ",") { position += 1; continue }
            guard bytes[position] == UInt8(ascii: "}") else { throw failure("a comma or a closing brace is expected") }
            position += 1
            return CanvasJSONValue(content: .object(members), range: start..<position)
        }
    }

    private mutating func parseArray(depth: Int) throws -> CanvasJSONValue {
        let start = position
        position += 1
        var elements: [CanvasJSONValue] = []
        skipWhitespace()
        if position < bytes.count, bytes[position] == UInt8(ascii: "]") {
            position += 1
            return CanvasJSONValue(content: .array(elements), range: start..<position)
        }
        while true {
            skipWhitespace()
            elements.append(try parseValue(depth: depth + 1))
            skipWhitespace()
            guard position < bytes.count else { throw failure("the file ends inside a list") }
            if bytes[position] == UInt8(ascii: ",") { position += 1; continue }
            guard bytes[position] == UInt8(ascii: "]") else { throw failure("a comma or a closing bracket is expected") }
            position += 1
            return CanvasJSONValue(content: .array(elements), range: start..<position)
        }
    }

    private mutating func parseNumber() throws -> Double {
        let start = position
        if bytes[position] == UInt8(ascii: "-") { position += 1 }
        let integerStart = position
        skipDigits()
        guard position > integerStart else { throw failure("a digit is expected") }
        // JSON writes no leading zeros.
        guard bytes[integerStart] != UInt8(ascii: "0") || position == integerStart + 1 else { throw failure("a number cannot start with 0") }
        if position < bytes.count, bytes[position] == UInt8(ascii: ".") {
            position += 1
            let fractionStart = position
            skipDigits()
            guard position > fractionStart else { throw failure("a digit is expected after the decimal point") }
        }
        if position < bytes.count, bytes[position] == UInt8(ascii: "e") || bytes[position] == UInt8(ascii: "E") {
            position += 1
            if position < bytes.count, bytes[position] == UInt8(ascii: "+") || bytes[position] == UInt8(ascii: "-") { position += 1 }
            let exponentStart = position
            skipDigits()
            guard position > exponentStart else { throw failure("a digit is expected in the exponent") }
        }
        guard let number = Double(String(decoding: bytes[start..<position], as: UTF8.self)) else { throw failure("the number cannot be read") }
        return number
    }

    private mutating func skipDigits() {
        while position < bytes.count, bytes[position] >= UInt8(ascii: "0"), bytes[position] <= UInt8(ascii: "9") { position += 1 }
    }

    /// Reads the string that starts at the opening quote and leaves `position` after the
    /// closing quote.
    private mutating func parseString() throws -> String {
        position += 1
        let contentStart = position
        var hasEscape = false
        while position < bytes.count {
            let byte = bytes[position]
            if byte == UInt8(ascii: "\"") { break }
            if byte == UInt8(ascii: "\\") {
                hasEscape = true
                position += 1
                guard position < bytes.count else { break }
            } else if byte < 0x20 {
                throw failure("a line break or control character is inside a string")
            }
            position += 1
        }
        guard position < bytes.count else { throw failure("the file ends inside a string") }
        let contentEnd = position
        position += 1
        guard hasEscape else { return String(decoding: bytes[contentStart..<contentEnd], as: UTF8.self) }
        return try decodeEscapedString(contentStart..<contentEnd)
    }

    private func decodeEscapedString(_ contentRange: Range<Int>) throws -> String {
        var decodedBytes: [UInt8] = []
        decodedBytes.reserveCapacity(contentRange.count)
        var index = contentRange.lowerBound
        func escapeFailure(_ reason: String) -> CanvasFileError { .invalidJSON(byteOffset: index, reason: reason) }
        while index < contentRange.upperBound {
            let byte = bytes[index]
            guard byte == UInt8(ascii: "\\") else {
                decodedBytes.append(byte)
                index += 1
                continue
            }
            guard index + 1 < contentRange.upperBound else { throw escapeFailure("a string ends inside an escape") }
            let escaped = bytes[index + 1]
            index += 2
            switch escaped {
            case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): decodedBytes.append(escaped)
            case UInt8(ascii: "b"): decodedBytes.append(0x08)
            case UInt8(ascii: "f"): decodedBytes.append(0x0C)
            case UInt8(ascii: "n"): decodedBytes.append(0x0A)
            case UInt8(ascii: "r"): decodedBytes.append(0x0D)
            case UInt8(ascii: "t"): decodedBytes.append(0x09)
            case UInt8(ascii: "u"):
                guard let codeUnit = hexadecimalCodeUnit(at: index, before: contentRange.upperBound) else { throw escapeFailure("four hexadecimal digits are expected after \\u") }
                index += 4
                var scalarValue = UInt32(codeUnit)
                if (0xD800...0xDBFF).contains(codeUnit), index + 1 < contentRange.upperBound,
                   bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u"),
                   let lowSurrogate = hexadecimalCodeUnit(at: index + 2, before: contentRange.upperBound), (0xDC00...0xDFFF).contains(lowSurrogate) {
                    scalarValue = 0x10000 + ((UInt32(codeUnit) - 0xD800) << 10) + (UInt32(lowSurrogate) - 0xDC00)
                    index += 6
                }
                // Half of a surrogate pair on its own names no character; it reads as the
                // replacement character, and the file keeps what was written.
                let scalar = Unicode.Scalar(scalarValue) ?? "\u{FFFD}"
                decodedBytes.append(contentsOf: Array(String(scalar).utf8))
            default:
                throw escapeFailure("an unknown escape is inside a string")
            }
        }
        return String(decoding: decodedBytes, as: UTF8.self)
    }

    private func hexadecimalCodeUnit(at start: Int, before end: Int) -> UInt16? {
        guard start + 4 <= end else { return nil }
        var codeUnit: UInt16 = 0
        for byte in bytes[start..<start + 4] {
            let digit: UInt16
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt16(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt16(byte - UInt8(ascii: "a")) + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt16(byte - UInt8(ascii: "A")) + 10
            default: return nil
            }
            codeUnit = codeUnit << 4 | digit
        }
        return codeUnit
    }
}

/// Writes the values Graphite adds to a canvas as Obsidian writes them, which is what
/// JavaScript's `JSON.stringify` produces.
enum CanvasJSONWriter {
    /// A string in quotes. Only the quote, the backslash and control characters are
    /// escaped; every other character, non-ASCII included, is written as it is.
    static func string(_ text: String) -> [UInt8] {
        var output: [UInt8] = [UInt8(ascii: "\"")]
        output.reserveCapacity(text.utf8.count + 2)
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "\""): output += [UInt8(ascii: "\\"), UInt8(ascii: "\"")]
            case UInt8(ascii: "\\"): output += [UInt8(ascii: "\\"), UInt8(ascii: "\\")]
            case 0x08: output += Array("\\b".utf8)
            case 0x0C: output += Array("\\f".utf8)
            case 0x0A: output += Array("\\n".utf8)
            case 0x0D: output += Array("\\r".utf8)
            case 0x09: output += Array("\\t".utf8)
            case 0x00..<0x20: output += Array(String(format: "\\u%04x", byte).utf8)
            default: output.append(byte)
            }
        }
        output.append(UInt8(ascii: "\""))
        return output
    }

    /// A position or size in whole pixels, as the format asks.
    static func integer(_ number: Double) -> [UInt8] {
        Array(String(wholeNumber(number)).utf8)
    }

    /// `number` rounded to a whole number that a canvas coordinate can hold.
    static func wholeNumber(_ number: Double) -> Int {
        guard number.isFinite else { return 0 }
        return Int(min(max(number.rounded(), -CanvasFile.maximumCoordinate), CanvasFile.maximumCoordinate))
    }
}
