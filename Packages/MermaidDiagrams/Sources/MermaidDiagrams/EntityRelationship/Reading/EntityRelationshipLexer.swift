import Foundation

/// Reads the tokens of an entity relationship diagram's statements from its UTF-8 bytes, outside an entity's `{ … }`,
/// as Mermaid's lexer does: accessibility text and `direction` first, then symbols, numbers (where `1` is a
/// cardinality when a name or a line follows it), the words of cardinalities, lines and keywords wherever they stand,
/// and names. Spaces, tabs, carriage returns and `%%` comments are skipped; a line break is a token.
struct EntityRelationshipLexer {
    var cursor: MermaidTextCursor

    /// Skips what separates tokens and reads the token there. `start` is a copy of the cursor at its first byte, for
    /// the line and the text an error reports.
    mutating func readToken() throws(MermaidDiagramReadError) -> (token: EntityRelationshipToken, start: MermaidTextCursor) {
        skipSeparators()
        let start = cursor
        guard let byte = cursor.peek() else { return (.endOfText, start) }
        return (try token(startingWith: byte), start)
    }

    private mutating func skipSeparators() {
        while let byte = cursor.peek() {
            if MermaidByte.isSpace(byte) || byte == MermaidByte.carriageReturn {
                cursor.advance()
            } else if cursor.hasPrefix(Self.commentStart) {
                cursor.skipToEndOfLine()
            } else {
                return
            }
        }
    }

    private mutating func token(startingWith byte: UInt8) throws(MermaidDiagramReadError) -> EntityRelationshipToken {
        if let accessibilityText = try readAccessibilityText() { return accessibilityText }
        if let direction = readDirection() { return .direction(direction) }
        if let symbol = readSymbol(byte) { return symbol }
        if byte == MermaidByte.quotationMark { return try readQuotedText() }
        if MermaidByte.isDigit(byte) { return readNumber(startingWith: byte) }
        if let word = EntityRelationshipWords.readToken(&cursor) { return word }
        guard Self.isNameByte(byte) else {
            cursor.advance()
            return .unexpectedCharacter
        }
        let start = cursor.position
        while let next = cursor.peek(), Self.isNameByte(next) { cursor.advance() }
        return .name(cursor.text(from: start, to: cursor.position), form: .bare)
    }

    /// A line break, a brace, a bracket, `:::`, `:` or `,`; nil for any other byte.
    private mutating func readSymbol(_ byte: UInt8) -> EntityRelationshipToken? {
        let token: EntityRelationshipToken
        switch byte {
        case MermaidByte.newline:
            while cursor.peek() == MermaidByte.newline { cursor.advance() }
            return .lineBreak
        case MermaidByte.openingBrace: token = .openingBrace
        case MermaidByte.openingBracket: token = .openingBracket
        case MermaidByte.closingBracket: token = .closingBracket
        case MermaidByte.comma: token = .comma
        case MermaidByte.colon:
            if cursor.hasPrefix(Self.classSeparator) {
                cursor.advance(by: Self.classSeparator.count)
                return .classSeparator
            }
            token = .colon
        default: return nil
        }
        cursor.advance()
        return token
    }

    /// `accTitle: text` or `accDescr: text` to the end of the line, or `accDescr { text }` over several lines; nil
    /// when the word is not followed by `:` (or `{`), and is a name.
    private mutating func readAccessibilityText() throws(MermaidDiagramReadError) -> EntityRelationshipToken? {
        let isTitle = cursor.hasCaseInsensitivePrefix(Self.accessibilityTitleKeyword)
        guard isTitle || cursor.hasCaseInsensitivePrefix(Self.accessibilityDescriptionKeyword) else { return nil }
        let keywordLine = cursor.line
        var lookahead = cursor
        lookahead.advance(by: isTitle ? Self.accessibilityTitleKeyword.count : Self.accessibilityDescriptionKeyword.count)
        Self.skipWhitespaceAndLineBreaks(&lookahead)
        if lookahead.peek() == MermaidByte.colon {
            lookahead.advance()
            // As in Mermaid, the text after the colon may start on the next line.
            Self.skipWhitespaceAndLineBreaks(&lookahead)
            let text = DiagramLabelDecoder.decodingEntities(lookahead.readRestOfLine().trimmingCharacters(in: .whitespaces))
            cursor = lookahead
            return isTitle ? .accessibilityTitle(text) : .accessibilityDescription(text)
        }
        guard !isTitle, lookahead.peek() == MermaidByte.openingBrace else { return nil }
        lookahead.advance()
        let start = lookahead.position
        while let byte = lookahead.peek(), byte != MermaidByte.closingBrace { lookahead.advance() }
        guard !lookahead.isAtEnd else { throw .invalidSyntax(line: keywordLine, problem: .unclosedAccessibilityDescription) }
        let text = Self.descriptionLines(lookahead.text(from: start, to: lookahead.position))
        lookahead.advance()
        cursor = lookahead
        return .accessibilityDescription(text)
    }

    /// The text of `accDescr { … }` as Mermaid keeps it: trimmed, each line after the first without its indentation,
    /// blank lines dropped.
    private static func descriptionLines(_ text: String) -> String {
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        let laterLines = lines.dropFirst().map { line in String(line.drop(while: \.isWhitespace)) }.filter { line in !line.isEmpty }
        return DiagramLabelDecoder.decodingEntities(([lines[0]] + laterLines).joined(separator: "\n"))
    }

    /// `direction` and whitespace, then `TB`, `BT`, `RL` or `LR` in any case; the rest of the line goes with it. Nil
    /// when the word is not followed by one of the four, and is a name.
    private mutating func readDirection() -> FlowchartDirection? {
        guard cursor.hasCaseInsensitivePrefix(Self.directionKeyword) else { return nil }
        var lookahead = cursor
        lookahead.advance(by: Self.directionKeyword.count)
        guard let separator = lookahead.peek(), Self.isWhitespace(separator) else { return nil }
        Self.skipWhitespaceAndLineBreaks(&lookahead)
        guard let direction = Self.directionsByKeyword.first(where: { keyword, _ in lookahead.hasCaseInsensitivePrefix(keyword) })?.1 else {
            return nil
        }
        lookahead.skipToEndOfLine()
        cursor = lookahead
        return direction
    }

    /// Text between quotation marks: a name when it is not empty and holds no `%`, `\`, line break, vertical tab or
    /// backspace, else text only a label may be. It may run over several lines.
    private mutating func readQuotedText() throws(MermaidDiagramReadError) -> EntityRelationshipToken {
        let openingLine = cursor.line
        cursor.advance()
        let start = cursor.position
        var isName = true
        while let byte = cursor.peek(), byte != MermaidByte.quotationMark {
            if Self.bytesNoQuotedNameHolds.contains(byte) { isName = false }
            cursor.advance()
        }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedQuotation) }
        let text = cursor.text(from: start, to: cursor.position)
        cursor.advance()
        return isName && !text.isEmpty ? .name(text, form: .quoted) : .quotedText(text)
    }

    /// `1+` and `0+`; a number with a decimal part; `1` as exactly one where a name, a quotation or a line follows it,
    /// or alone as a name; else the digits, which name an entity.
    private mutating func readNumber(startingWith first: UInt8) -> EntityRelationshipToken {
        let next = cursor.peek(1)
        if next == Self.plus, first == Self.digitOne || first == Self.digitZero {
            cursor.advance(by: 2)
            return .cardinality(first == Self.digitOne ? .oneOrMore : .zeroOrMore)
        }
        var length = 1
        while let byte = cursor.peek(length), MermaidByte.isDigit(byte) { length += 1 }
        if cursor.peek(length) == MermaidByte.period, let decimal = cursor.peek(length + 1), MermaidByte.isDigit(decimal) {
            length += 2
            while let byte = cursor.peek(length), MermaidByte.isDigit(byte) { length += 1 }
        } else if first == Self.digitOne, oneIsACardinality() {
            cursor.advance()
            return .cardinality(.exactlyOne)
        } else if first == Self.digitOne, next.map(EntityRelationshipWords.isWordByte) != true {
            length = 1
        }
        let start = cursor.position
        cursor.advance(by: length)
        return .name(cursor.text(from: start, to: cursor.position), form: .number)
    }

    /// Whether the `1` at the cursor is followed by whitespace and then a letter, a digit, `_` or a quotation mark,
    /// or by a line (`--`, `..`, `.-`, `-.`).
    private func oneIsACardinality() -> Bool {
        guard let next = cursor.peek(1) else { return false }
        if Self.isWhitespace(next) {
            var offset = 2
            while let byte = cursor.peek(offset), Self.isWhitespace(byte) { offset += 1 }
            guard let following = cursor.peek(offset) else { return false }
            return EntityRelationshipWords.isWordByte(following) || following == MermaidByte.quotationMark || following == Self.apostrophe
        }
        guard next == MermaidByte.hyphen || next == MermaidByte.period, let following = cursor.peek(2) else { return false }
        return following == MermaidByte.hyphen || following == MermaidByte.period
    }

    /// A byte of a bare name: a letter, a digit, `_`, `-`, `*`, `.`, or any byte of a character beyond ASCII.
    static func isNameByte(_ byte: UInt8) -> Bool {
        EntityRelationshipWords.isWordByte(byte) || byte == MermaidByte.hyphen || byte == asterisk || byte == MermaidByte.period || byte >= 0x80
    }

    /// A space, a tab, a line break, a vertical tab, a form feed or a carriage return.
    static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == MermaidByte.space || (byte >= MermaidByte.tab && byte <= MermaidByte.carriageReturn)
    }

    private static func skipWhitespaceAndLineBreaks(_ cursor: inout MermaidTextCursor) {
        while let byte = cursor.peek(), isWhitespace(byte) { cursor.advance() }
    }

    private static let commentStart = Array("%%".utf8)
    private static let classSeparator = Array(":::".utf8)
    private static let accessibilityTitleKeyword = Array("acctitle".utf8)
    private static let accessibilityDescriptionKeyword = Array("accdescr".utf8)
    private static let directionKeyword = Array("direction".utf8)
    private static let directionsByKeyword: [([UInt8], FlowchartDirection)] = [
        (Array("tb".utf8), .topToBottom), (Array("bt".utf8), .bottomToTop), (Array("rl".utf8), .rightToLeft), (Array("lr".utf8), .leftToRight),
    ]
    private static let bytesNoQuotedNameHolds: Set<UInt8> = [UInt8(ascii: "%"), UInt8(ascii: "\\"), MermaidByte.carriageReturn, MermaidByte.newline,
                                                             0x0B, 0x08]
    private static let plus = UInt8(ascii: "+")
    private static let asterisk = UInt8(ascii: "*")
    private static let apostrophe = UInt8(ascii: "'")
    private static let digitZero = UInt8(ascii: "0")
    private static let digitOne = UInt8(ascii: "1")
}
