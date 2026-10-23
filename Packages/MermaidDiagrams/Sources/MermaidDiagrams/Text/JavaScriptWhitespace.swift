/// JavaScript's whitespace (`\s`) over UTF-8 bytes, as the lexers Mermaid generates and Pele's read it: tab, line
/// feed, vertical tab, form feed, carriage return, space, and Unicode's spaces (no-break space, Ogham space mark,
/// U+2000 to U+200A, line and paragraph separators, narrow no-break space, medium mathematical space, ideographic
/// space, and the byte order mark).
enum JavaScriptWhitespace {
    /// The length in bytes of the whitespace character at `position`, or zero for any other character or past the end.
    static func length<Bytes: RandomAccessCollection<UInt8>>(in bytes: Bytes, at position: Bytes.Index) -> Int where Bytes.Index == Int {
        guard position >= bytes.startIndex, position < bytes.endIndex else { return 0 }
        let byte = bytes[position]
        if byte == MermaidByte.space || (byte >= MermaidByte.tab && byte <= MermaidByte.carriageReturn) { return 1 }
        guard byte >= 0xC2 else { return 0 }
        for space in unicodeSpaces where position + space.count <= bytes.endIndex && bytes[position..<position + space.count].elementsEqual(space) {
            return space.count
        }
        let isGeneralPunctuationSpace = byte == 0xE2 && position + 2 < bytes.endIndex && bytes[position + 1] == 0x80
            && (0x80...0x8A).contains(bytes[position + 2])
        return isGeneralPunctuationSpace ? 3 : 0
    }

    /// The position after the run of whitespace that starts at `position`.
    static func endOfRun<Bytes: RandomAccessCollection<UInt8>>(in bytes: Bytes, from position: Bytes.Index) -> Int where Bytes.Index == Int {
        var end = position
        while case let characterLength = length(in: bytes, at: end), characterLength > 0 { end += characterLength }
        return end
    }

    /// Whether `bytes` hold whitespace only, or nothing.
    static func isBlank<Bytes: RandomAccessCollection<UInt8>>(_ bytes: Bytes) -> Bool where Bytes.Index == Int {
        endOfRun(in: bytes, from: bytes.startIndex) == bytes.endIndex
    }

    /// The length of the whitespace character that ends `bytes`, or zero.
    static func lengthOfLast<Bytes: RandomAccessCollection<UInt8>>(in bytes: Bytes) -> Int where Bytes.Index == Int {
        guard let last = bytes.last else { return 0 }
        if last < 0x80 { return length(in: bytes, at: bytes.endIndex - 1) }
        for characterLength in 2...3 where bytes.count >= characterLength
            && length(in: bytes, at: bytes.endIndex - characterLength) == characterLength {
            return characterLength
        }
        return 0
    }

    /// `bytes` without the whitespace at either end, as JavaScript's `trim` leaves a string.
    static func trimmed(_ bytes: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        var trimmed = bytes[endOfRun(in: bytes, from: bytes.startIndex)...]
        while case let length = lengthOfLast(in: trimmed), length > 0 { trimmed = trimmed.dropLast(length) }
        return trimmed
    }

    /// Unicode's spaces other than U+2000 to U+200A, in UTF-8.
    private static let unicodeSpaces: [[UInt8]] = [
        [0xC2, 0xA0], [0xE1, 0x9A, 0x80], [0xE2, 0x80, 0xA8], [0xE2, 0x80, 0xA9], [0xE2, 0x80, 0xAF], [0xE2, 0x81, 0x9F], [0xE3, 0x80, 0x80],
        [0xEF, 0xBB, 0xBF],
    ]
}
