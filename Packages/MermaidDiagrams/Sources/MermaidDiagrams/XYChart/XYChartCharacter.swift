/// The classes of characters Mermaid's XY chart lexer tests, over UTF-8 bytes, besides whitespace (`JavaScriptWhitespace`):
/// word characters (`\w`) and the numbers of an axis' range and a series' values.
enum XYChartCharacter {
    /// Whether `byte` is a letter, a digit or an underscore; false past the end.
    static func isWordByte(_ byte: UInt8?) -> Bool {
        guard let byte else { return false }
        return MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
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
}
