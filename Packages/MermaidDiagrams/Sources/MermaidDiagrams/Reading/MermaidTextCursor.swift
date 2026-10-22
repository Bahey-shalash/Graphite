/// A position in a diagram's UTF-8 bytes, with the line it is on. Readers move it forward only; a lookahead copies it.
struct MermaidTextCursor {
    let bytes: [UInt8]
    private(set) var position: Int
    /// The 1-based line of `position` in the diagram's text.
    private(set) var line: Int

    init(bytes: [UInt8]) {
        self.bytes = bytes
        self.position = 0
        self.line = 1
    }

    var isAtEnd: Bool { position >= bytes.count }

    /// The byte `offset` places ahead, or nil past the end.
    func peek(_ offset: Int = 0) -> UInt8? {
        let index = position + offset
        return index < bytes.count ? bytes[index] : nil
    }

    mutating func advance(by count: Int = 1) {
        let end = min(bytes.count, position + count)
        while position < end {
            if bytes[position] == MermaidByte.newline { line += 1 }
            position += 1
        }
    }

    /// Whether the bytes at the position are `literal`, compared exactly.
    func hasPrefix(_ literal: [UInt8]) -> Bool {
        guard position + literal.count <= bytes.count else { return false }
        for (offset, byte) in literal.enumerated() where bytes[position + offset] != byte { return false }
        return true
    }

    /// Whether the bytes at the position are `literal` with ASCII letters compared without regard to case.
    func hasCaseInsensitivePrefix(_ literal: [UInt8]) -> Bool {
        guard position + literal.count <= bytes.count else { return false }
        for (offset, byte) in literal.enumerated() where MermaidByte.lowercased(bytes[position + offset]) != byte { return false }
        return true
    }

    /// Skips spaces and tabs, never a line break.
    mutating func skipSpaces() {
        while let byte = peek(), MermaidByte.isSpace(byte) { advance() }
    }

    /// Skips spaces, tabs, carriage returns and line breaks.
    mutating func skipWhitespace() {
        while let byte = peek(), MermaidByte.isSpace(byte) || byte == MermaidByte.newline || byte == MermaidByte.carriageReturn { advance() }
    }

    /// Moves to the line break that ends the current line, or to the end.
    mutating func skipToEndOfLine() {
        while let byte = peek(), byte != MermaidByte.newline { advance() }
    }

    /// The text of the bytes from `start` to `end`.
    func text(from start: Int, to end: Int) -> String {
        String(decoding: bytes[start..<end], as: UTF8.self)
    }

    /// The text of the bytes from `start` to `end` without the spaces, tabs and line breaks at either end.
    func trimmedText(from start: Int, to end: Int) -> String {
        var first = start
        var last = end
        while first < last, MermaidByte.isWhitespace(bytes[first]) { first += 1 }
        while last > first, MermaidByte.isWhitespace(bytes[last - 1]) { last -= 1 }
        return text(from: first, to: last)
    }

    /// The text from the position to the end of its line, without the line break and trailing spaces; moves past it.
    mutating func readRestOfLine() -> String {
        let start = position
        skipToEndOfLine()
        var end = position
        while end > start, MermaidByte.isSpace(bytes[end - 1]) || bytes[end - 1] == MermaidByte.carriageReturn { end -= 1 }
        return text(from: start, to: end)
    }

    /// Reads a run of identifier bytes (`MermaidByte.isIdentifierByte`), with a `-` kept only where a letter, digit or
    /// underscore follows it, so that `step-1` is one identifier and `A-->B` stops before the link. Nil when there is none.
    mutating func readIdentifier() -> String? {
        let start = position
        while let byte = peek() {
            if MermaidByte.isIdentifierByte(byte) {
                advance()
            } else if byte == MermaidByte.hyphen, position > start, let next = peek(1), MermaidByte.isIdentifierByte(next) {
                advance()
            } else {
                break
            }
        }
        return position > start ? text(from: start, to: position) : nil
    }

    /// Reads ASCII letters only, for a keyword. Nil when there is none.
    mutating func readWord() -> String? {
        let start = position
        while let byte = peek(), MermaidByte.isLetter(byte) { advance() }
        return position > start ? text(from: start, to: position) : nil
    }

    /// The first characters at the position, for an error that shows what could not be read.
    func excerpt(maximumBytes: Int = 24) -> String {
        var end = min(bytes.count, position + maximumBytes)
        if let lineEnd = bytes[position..<end].firstIndex(of: MermaidByte.newline) { end = lineEnd }
        // Never cut a character in two.
        while end < bytes.count, end > position, bytes[end] & 0xC0 == 0x80 { end -= 1 }
        return text(from: position, to: end)
    }
}
