/// The classes of characters Mermaid's XY chart lexer tests, over UTF-8 bytes: JavaScript's whitespace (`\s`), word
/// characters (`\w`) and the numbers of an axis' range and a series' values.
enum XYChartCharacter {
    /// Whether `byte` is a letter, a digit or an underscore; false past the end.
    static func isWordByte(_ byte: UInt8?) -> Bool {
        guard let byte else { return false }
        return MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
    }

    /// The length in bytes of the whitespace character at `position`, as JavaScript's `\s` reads whitespace: tab, line
    /// break, vertical tab, form feed, carriage return, space and Unicode's spaces; zero for any other character.
    static func spaceLength(in bytes: [UInt8], at position: Int) -> Int {
        guard position < bytes.count else { return 0 }
        let byte = bytes[position]
        if byte == MermaidByte.space || (byte >= MermaidByte.tab && byte <= MermaidByte.carriageReturn) { return 1 }
        guard byte >= 0xC2 else { return 0 }
        for space in unicodeSpaces where position + space.count <= bytes.count && bytes[position..<position + space.count].elementsEqual(space) {
            return space.count
        }
        let isGeneralPunctuationSpace = byte == 0xE2 && position + 2 < bytes.count && bytes[position + 1] == 0x80 && bytes[position + 2] <= 0x8A
            && bytes[position + 2] >= 0x80
        return isGeneralPunctuationSpace ? 3 : 0
    }

    /// The position after the run of whitespace that starts at `position`, line breaks included.
    static func endOfSpaces(in bytes: [UInt8], from position: Int) -> Int {
        var end = position
        while case let length = spaceLength(in: bytes, at: end), length > 0 { end += length }
        return end
    }

    /// The end of the number at `position`, or nil when none is there: a sign, then digits with an optional fraction
    /// (`-45`, `56.6`) or only a fraction (`.33`).
    static func endOfNumber(in bytes: [UInt8], from position: Int) -> Int? {
        func isDigit(at index: Int) -> Bool { index < bytes.count && MermaidByte.isDigit(bytes[index]) }
        func endOfDigits(from index: Int) -> Int {
            var end = index
            while isDigit(at: end) { end += 1 }
            return end
        }
        let signed = position < bytes.count && (bytes[position] == UInt8(ascii: "+") || bytes[position] == MermaidByte.hyphen)
        let digitsStart = signed ? position + 1 : position
        if isDigit(at: digitsStart) {
            let end = endOfDigits(from: digitsStart + 1)
            let hasFraction = end < bytes.count && bytes[end] == MermaidByte.period && isDigit(at: end + 1)
            return hasFraction ? endOfDigits(from: end + 2) : end
        }
        let isFractionOnly = digitsStart < bytes.count && bytes[digitsStart] == MermaidByte.period && isDigit(at: digitsStart + 1)
        return isFractionOnly ? endOfDigits(from: digitsStart + 2) : nil
    }

    /// The length of the character that starts with `leadByte` when Mermaid's second comment rule can take it with
    /// the `%%` after it: one UTF-16 unit in JavaScript, so an ASCII character or one of two or three UTF-8 bytes;
    /// zero for a character beyond the Basic Multilingual Plane, whose second unit JavaScript would reach first.
    static func commentPrefixLength(of leadByte: UInt8) -> Int {
        switch leadByte {
        case 0x00..<0x80: 1
        case 0xC0..<0xE0: 2
        case 0xE0..<0xF0: 3
        default: 0
        }
    }

    /// Unicode's spaces other than U+2000 to U+200A, in UTF-8: no-break space, Ogham space mark, line and paragraph
    /// separators, narrow no-break space, medium mathematical space, ideographic space and the byte order mark.
    private static let unicodeSpaces: [[UInt8]] = [
        [0xC2, 0xA0], [0xE1, 0x9A, 0x80], [0xE2, 0x80, 0xA8], [0xE2, 0x80, 0xA9], [0xE2, 0x80, 0xAF], [0xE2, 0x81, 0x9F], [0xE3, 0x80, 0x80],
        [0xEF, 0xBB, 0xBF],
    ]
}
