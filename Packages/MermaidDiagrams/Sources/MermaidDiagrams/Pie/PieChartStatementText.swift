import Foundation

/// The pieces of a pie chart's statements, read as the tokens of Mermaid's pie grammar: keywords, quoted strings with
/// their escapes, numbers, the text of a line, accessibility descriptions, and the spaces and comments between them.
enum PieChartStatementText {
    static let apostrophe = UInt8(ascii: "'")
    private static let backslash = UInt8(ascii: "\\")
    private static let zero = UInt8(ascii: "0")
    private static let commentStart = Array("%%".utf8)
    private static let directiveStart = Array("%%{".utf8)
    private static let directiveEnd = Array("}%%".utf8)
    /// The characters a backslash in a string stands for: `\n` is a line break; any other escaped character is itself.
    private static let escapes: [UInt8: UInt8] = [
        UInt8(ascii: "b"): 0x08, UInt8(ascii: "f"): 0x0C, UInt8(ascii: "n"): MermaidByte.newline, UInt8(ascii: "r"): MermaidByte.carriageReturn,
        UInt8(ascii: "t"): MermaidByte.tab, UInt8(ascii: "v"): 0x0B, UInt8(ascii: "0"): 0x00,
    ]

    /// Whether `keyword` is at the cursor and ends there: a space, a line break, a comment or the end of the text follows.
    static func isAtKeyword(_ keyword: [UInt8], _ cursor: MermaidTextCursor) -> Bool {
        guard cursor.hasPrefix(keyword) else { return false }
        guard let next = cursor.peek(keyword.count) else { return true }
        return MermaidByte.isWhitespace(next) || (next == MermaidByte.percent && cursor.peek(keyword.count + 1) == MermaidByte.percent)
    }

    /// Skips spaces, tabs, `%%` comments to the end of their line, and `%%{ … }%%` directives, which may span lines.
    static func skipSpacesAndComments(_ cursor: inout MermaidTextCursor) {
        while true {
            cursor.skipSpaces()
            if cursor.hasPrefix(directiveStart), skipDirective(&cursor) { continue }
            guard cursor.hasPrefix(commentStart) else { return }
            cursor.skipToEndOfLine()
        }
    }

    /// Moves past `%%{ … }%%` and returns true, or returns false when it has no end and is then a comment.
    private static func skipDirective(_ cursor: inout MermaidTextCursor) -> Bool {
        var lookahead = cursor
        while !lookahead.isAtEnd {
            if lookahead.hasPrefix(directiveEnd) {
                lookahead.advance(by: directiveEnd.count)
                cursor = lookahead
                return true
            }
            lookahead.advance()
        }
        return false
    }

    /// The rest of the line up to a comment, without the spaces at either end and with runs of spaces made one.
    static func readLineValue(_ cursor: inout MermaidTextCursor) -> String {
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.newline, byte != MermaidByte.carriageReturn, !cursor.hasPrefix(commentStart) {
            cursor.advance()
        }
        return collapsingSpaces(cursor.trimmedText(from: start, to: cursor.position))
    }

    /// After `accDescr`: `: text` to the end of the line, or `{ lines }`, each line trimmed and the empty ones left out,
    /// joined by line breaks. Nil when neither follows.
    static func readAccessibilityDescription(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> String? {
        cursor.skipSpaces()
        if cursor.peek() == MermaidByte.colon {
            cursor.advance()
            return readLineValue(&cursor)
        }
        cursor.skipWhitespace()
        guard cursor.peek() == MermaidByte.openingBrace else { return nil }
        let openingLine = cursor.line
        cursor.advance()
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.closingBrace { cursor.advance() }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedAccessibilityDescription) }
        let lines = cursor.text(from: start, to: cursor.position).split(whereSeparator: \.isNewline)
            .map { line in collapsingSpaces(line.trimmingCharacters(in: .whitespaces)) }
        cursor.advance()
        return lines.filter { line in !line.isEmpty }.joined(separator: "\n")
    }

    /// A string between quotation marks or apostrophes, which may span lines, with a backslash escaping the next
    /// character. The cursor is on the opening mark.
    static func readString(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> String {
        guard let quotation = cursor.peek() else { throw .invalidSyntax(line: cursor.line, problem: .unclosedQuotation) }
        let openingLine = cursor.line
        cursor.advance()
        var bytes: [UInt8] = []
        while let byte = cursor.peek(), byte != quotation {
            cursor.advance()
            guard byte == backslash, let escaped = cursor.peek() else {
                bytes.append(byte)
                continue
            }
            cursor.advance()
            bytes.append(escapes[escaped] ?? escaped)
        }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedQuotation) }
        cursor.advance()
        return String(decoding: bytes, as: UTF8.self)
    }

    /// A number as Mermaid's pie grammar reads one: an optional `-`, then a decimal number (`42.96`), `0`, or a whole
    /// number that does not start with 0; a `.` may not follow. Nil, with the cursor where it was, when there is none.
    static func readNumber(_ cursor: inout MermaidTextCursor) -> Double? {
        var lookahead = cursor
        let start = lookahead.position
        if lookahead.peek() == MermaidByte.hyphen { lookahead.advance() }
        let integerStart = lookahead.position
        skipDigits(&lookahead)
        let integerDigitCount = lookahead.position - integerStart
        guard integerDigitCount > 0 else { return nil }
        if lookahead.peek() == MermaidByte.period, let next = lookahead.peek(1), MermaidByte.isDigit(next) {
            lookahead.advance()
            skipDigits(&lookahead)
        } else if integerDigitCount > 1, lookahead.bytes[integerStart] == zero {
            return nil
        }
        guard lookahead.peek() != MermaidByte.period, let number = Double(lookahead.text(from: start, to: lookahead.position)) else { return nil }
        cursor = lookahead
        return number
    }

    private static func skipDigits(_ cursor: inout MermaidTextCursor) {
        while let byte = cursor.peek(), MermaidByte.isDigit(byte) { cursor.advance() }
    }

    private static func collapsingSpaces(_ text: String) -> String {
        guard text.contains("  ") || text.contains("\t") else { return text }
        return text.split(whereSeparator: { character in character == " " || character == "\t" }).joined(separator: " ")
    }
}
