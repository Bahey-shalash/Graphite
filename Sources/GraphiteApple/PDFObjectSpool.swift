import Foundation

/// PDF objects written to a file as they are made, before their object numbers are known: each object is numbered by
/// its place in the spool, from 0, and refers to other spooled objects by that place. `PDFAnnotationAppending` gives
/// them their numbers when it writes them after another file's objects. A writer that makes a page's objects at a time
/// so holds none of them in memory once the page is done.
///
/// The spool's format is its own and private to one write: per object, its part count, then each part, either bytes
/// (a length and the bytes) or a reference (the place of the object it refers to).
struct PDFObjectSpool {
    /// A piece of an object's text.
    enum Part {
        case bytes(Data)
        /// `<number> 0 R` of the spooled object at this place.
        case reference(Int)
    }

    enum SpoolError: Error, Equatable {
        case damaged
    }

    private static let bytesKind: UInt8 = 0
    private static let referenceKind: UInt8 = 1
    private static let bufferByteCount = 1_048_576

    let location: URL
    private let handle: FileHandle
    private var buffer = Data()
    private(set) var objectCount = 0

    /// Creates the spool's file, which must not exist.
    init(location: URL) throws {
        guard FileManager.default.createFile(atPath: location.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        self.location = location
        handle = try FileHandle(forWritingTo: location)
    }

    /// The place the next object will have.
    var nextPlace: Int { objectCount }

    /// Adds an object (its value, the text between `obj` and `endobj`, stream included) and returns its place.
    @discardableResult
    mutating func add(_ parts: [Part]) throws -> Int {
        appendInteger(UInt32(parts.count))
        for part in parts {
            switch part {
            case .bytes(let bytes):
                buffer.append(Self.bytesKind)
                appendInteger(UInt32(bytes.count))
                buffer.append(bytes)
            case .reference(let place):
                buffer.append(Self.referenceKind)
                appendInteger(UInt32(place))
            }
        }
        objectCount += 1
        if buffer.count >= Self.bufferByteCount { try flush() }
        return objectCount - 1
    }

    /// Writes what is buffered and closes the file; the spool is then read with `forEachObject`.
    mutating func finish() throws {
        try flush()
        try handle.close()
    }

    private mutating func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    private mutating func appendInteger(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { bytes in buffer.append(contentsOf: bytes) }
    }

    /// Calls `body` with each object's place and parts, in order, reading the finished spool memory-mapped.
    static func forEachObject(in location: URL, _ body: (Int, [Part]) throws -> Void) throws {
        let bytes = try Data(contentsOf: location, options: .alwaysMapped)
        var position = bytes.startIndex
        func integer() throws -> Int {
            guard bytes.endIndex - position >= 4 else { throw SpoolError.damaged }
            var value: UInt32 = 0
            withUnsafeMutableBytes(of: &value) { target in target.copyBytes(from: bytes[position..<(position + 4)]) }
            position += 4
            return Int(UInt32(littleEndian: value))
        }
        var place = 0
        while position < bytes.endIndex {
            let partCount = try integer()
            var parts: [Part] = []
            parts.reserveCapacity(partCount)
            for _ in 0..<partCount {
                guard position < bytes.endIndex else { throw SpoolError.damaged }
                let kind = bytes[position]
                position += 1
                let value = try integer()
                if kind == referenceKind {
                    parts.append(.reference(value))
                } else {
                    guard kind == bytesKind, bytes.endIndex - position >= value else { throw SpoolError.damaged }
                    parts.append(.bytes(bytes[position..<(position + value)]))
                    position += value
                }
            }
            try body(place, parts)
            place += 1
        }
    }
}
