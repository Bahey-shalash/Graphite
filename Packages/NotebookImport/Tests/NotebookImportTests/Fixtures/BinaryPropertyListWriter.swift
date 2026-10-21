import Foundation

/// Writes small binary property lists (`bplist00`) for the reader tests, one object at a time, so a test can build
/// any object graph, cycles and damaged objects included. Integers are written in the fewest bytes, references and
/// offsets in the fewest bytes that hold them.
struct BinaryPropertyListWriter {
    enum Object {
        case null
        case boolean(Bool)
        case integer(Int64)
        case real(Double)
        case float(Float)
        case date(secondsSince2001: Double)
        case data([UInt8])
        /// ASCII when every character is ASCII, else UTF-16 big-endian.
        case string(String)
        case uid(Int)
        case array([Int])
        case set([Int])
        case dictionary(keys: [Int], values: [Int])
        /// Bytes written as they are, for damaged objects.
        case raw([UInt8])
    }

    /// A plain value tree, written with `add(tree:)`.
    indirect enum Tree {
        case integer(Int64)
        case real(Double)
        case boolean(Bool)
        case string(String)
        case data([UInt8])
        case array([Tree])
        case dictionary([(String, Tree)])
    }

    private(set) var objects: [Object] = []

    mutating func add(_ object: Object) -> Int {
        objects.append(object)
        return objects.count - 1
    }

    mutating func replace(_ objectIndex: Int, with object: Object) {
        objects[objectIndex] = object
    }

    mutating func add(tree: Tree) -> Int {
        switch tree {
        case .integer(let integer): return add(.integer(integer))
        case .real(let real): return add(.real(real))
        case .boolean(let flag): return add(.boolean(flag))
        case .string(let string): return add(.string(string))
        case .data(let bytes): return add(.data(bytes))
        case .array(let members):
            let memberIndices = members.map { member in add(tree: member) }
            return add(.array(memberIndices))
        case .dictionary(let entries):
            let keyIndices = entries.map { entry in add(.string(entry.0)) }
            let valueIndices = entries.map { entry in add(tree: entry.1) }
            return add(.dictionary(keys: keyIndices, values: valueIndices))
        }
    }

    /// The whole list with this top object.
    func bytes(topObjectIndex: Int) -> [UInt8] {
        let referenceByteCount = Self.byteCount(holding: UInt64(max(objects.count - 1, 0)))
        var output = Array("bplist00".utf8)
        var offsets: [Int] = []
        for object in objects {
            offsets.append(output.count)
            output += Self.encoded(object, referenceByteCount: referenceByteCount)
        }
        let offsetTableOffset = output.count
        let offsetByteCount = Self.byteCount(holding: UInt64(offsetTableOffset))
        for offset in offsets { output += Self.bigEndian(UInt64(offset), byteCount: offsetByteCount) }
        output += [0, 0, 0, 0, 0, 0, UInt8(offsetByteCount), UInt8(referenceByteCount)]
        output += Self.bigEndian(UInt64(objects.count), byteCount: 8)
        output += Self.bigEndian(UInt64(topObjectIndex), byteCount: 8)
        output += Self.bigEndian(UInt64(offsetTableOffset), byteCount: 8)
        return output
    }

    private static func encoded(_ object: Object, referenceByteCount: Int) -> [UInt8] {
        func references(_ indices: [Int]) -> [UInt8] { indices.flatMap { index in bigEndian(UInt64(index), byteCount: referenceByteCount) } }
        switch object {
        case .null: return [0x00]
        case .boolean(let flag): return [flag ? 0x09 : 0x08]
        case .integer(let integer): return encodedInteger(integer)
        case .real(let real): return [0x23] + bigEndian(real.bitPattern, byteCount: 8)
        case .float(let float): return [0x22] + bigEndian(UInt64(float.bitPattern), byteCount: 4)
        case .date(let seconds): return [0x33] + bigEndian(seconds.bitPattern, byteCount: 8)
        case .data(let bytes): return header(0x40, count: bytes.count) + bytes
        case .string(let string) where string.utf8.allSatisfy({ byte in byte < 0x80 }):
            return header(0x50, count: string.utf8.count) + Array(string.utf8)
        case .string(let string):
            return header(0x60, count: string.utf16.count) + string.utf16.flatMap { unit in bigEndian(UInt64(unit), byteCount: 2) }
        case .uid(let uid):
            let byteCount = byteCount(holding: UInt64(uid))
            return [0x80 | UInt8(byteCount - 1)] + bigEndian(UInt64(uid), byteCount: byteCount)
        case .array(let members): return header(0xA0, count: members.count) + references(members)
        case .set(let members): return header(0xC0, count: members.count) + references(members)
        case .dictionary(let keys, let values): return header(0xD0, count: keys.count) + references(keys) + references(values)
        case .raw(let bytes): return bytes
        }
    }

    private static func encodedInteger(_ integer: Int64) -> [UInt8] {
        guard integer >= 0 else { return [0x13] + bigEndian(UInt64(bitPattern: integer), byteCount: 8) }
        let byteCount = byteCount(holding: UInt64(integer))
        let exponent: UInt8 = byteCount == 1 ? 0 : byteCount == 2 ? 1 : byteCount <= 4 ? 2 : 3
        return [0x10 | exponent] + bigEndian(UInt64(integer), byteCount: 1 << Int(exponent))
    }

    private static func header(_ marker: UInt8, count: Int) -> [UInt8] {
        count < 15 ? [marker | UInt8(count)] : [marker | 0x0F] + encodedInteger(Int64(count))
    }

    static func byteCount(holding number: UInt64) -> Int {
        number < 0x100 ? 1 : number < 0x1_0000 ? 2 : number < 0x1_0000_0000 ? 4 : 8
    }

    static func bigEndian(_ number: UInt64, byteCount: Int) -> [UInt8] {
        (0..<byteCount).map { byteIndex in UInt8(truncatingIfNeeded: number >> (8 * UInt64(byteCount - 1 - byteIndex))) }
    }
}
