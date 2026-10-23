/// The tokens inside an entity's `{ … }`, as Mermaid's lexer reads them there: whitespace and line breaks only
/// separate them, `PK`, `FK` and `UK` are keys in any case, and a run holding `~` is one word to the last `~` of its
/// line. Where the next `~` and whitespace are is found once and kept until the cursor passes them, so that a long
/// line of short tokens is read in one pass.
struct EntityRelationshipAttributeWords {
    enum Token: Equatable {
        /// A type or a name.
        case word(String)
        case key(EntityRelationshipAttributeKey)
        /// The text between quotation marks, which may run over several lines.
        case comment(String)
        case questionMark
        case comma
        case closingBrace
        case endOfText
        case unexpectedCharacter
    }

    private(set) var cursor: MermaidTextCursor
    /// The line the last token read starts on.
    private(set) var tokenLine: Int
    /// The next whitespace at or after the cursor (the end of the text when there is none), once found.
    private var nextWhitespacePosition = -1
    /// The next `~` at or after the cursor (the end of the text when there is none), once found.
    private var nextTildePosition = -1
    /// Where the line of the last run holding `~` ends, and the position of that line's last `~`.
    private var tildeLineEnd = -1
    private var lastTildeOfLine = -1

    init(cursor: MermaidTextCursor) {
        self.cursor = cursor
        tokenLine = cursor.line
    }

    mutating func next() throws(MermaidDiagramReadError) -> Token {
        skipWhitespaceAndComments()
        tokenLine = cursor.line
        guard let byte = cursor.peek() else { return .endOfText }
        if let key = readKey() { return .key(key) }
        if let word = readRunHoldingTildes() { return .word(word) }
        if characterLength(atOffset: 0, startsWord: true) > 0 { return .word(readWord()) }
        let token: Token
        switch byte {
        case MermaidByte.graveAccent: return .word(readBacktickWord())
        case MermaidByte.quotationMark: return try readComment()
        case MermaidByte.closingBrace: token = .closingBrace
        case Self.questionMark: token = .questionMark
        case MermaidByte.comma: token = .comma
        default: token = .unexpectedCharacter
        }
        cursor.advance()
        return token
    }

    /// Skips whitespace, line breaks, `%%` comments and empty backticks.
    private mutating func skipWhitespaceAndComments() {
        while !cursor.isAtEnd {
            let whitespace = whitespaceLength(at: cursor.position)
            if whitespace > 0 {
                cursor.advance(by: whitespace)
            } else if cursor.hasPrefix(Self.commentStart) {
                cursor.skipToEndOfLine()
            } else if cursor.hasPrefix(Self.emptyBackticks) {
                cursor.advance(by: Self.emptyBackticks.count)
            } else {
                return
            }
        }
    }

    /// `PK`, `FK` or `UK` in any case, when no letter, digit or `_` follows.
    private mutating func readKey() -> EntityRelationshipAttributeKey? {
        guard let first = cursor.peek().map(MermaidByte.lowercased), let second = cursor.peek(1).map(MermaidByte.lowercased),
              second == UInt8(ascii: "k") else { return nil }
        if let following = cursor.peek(2), EntityRelationshipWords.isWordByte(following) { return nil }
        let key: EntityRelationshipAttributeKey
        switch first {
        case UInt8(ascii: "p"): key = .primary
        case UInt8(ascii: "f"): key = .foreign
        case UInt8(ascii: "u"): key = .unique
        default: return nil
        }
        cursor.advance(by: 2)
        return key
    }

    /// A run without whitespace that holds a `~`, taken through the last `~` of its line and on to the next whitespace
    /// (`List~int~`, `Map~K, V~`); nil when the run holds none, or its `~` is the line's last.
    private mutating func readRunHoldingTildes() -> String? {
        let position = cursor.position
        if nextTildePosition < position { nextTildePosition = firstPosition(from: position) { index in cursor.bytes[index] == Self.tilde } }
        if nextWhitespacePosition < position { nextWhitespacePosition = firstPosition(from: position) { index in whitespaceLength(at: index) > 0 } }
        guard nextTildePosition < nextWhitespacePosition else { return nil }
        if tildeLineEnd < position {
            tildeLineEnd = firstPosition(from: position) { index in
                cursor.bytes[index] == MermaidByte.newline || cursor.bytes[index] == MermaidByte.carriageReturn
            }
            lastTildeOfLine = (position..<tildeLineEnd).last { index in cursor.bytes[index] == Self.tilde } ?? -1
        }
        guard lastTildeOfLine > nextTildePosition else { return nil }
        let end = firstPosition(from: lastTildeOfLine + 1) { index in whitespaceLength(at: index) > 0 }
        cursor.advance(by: end - position)
        return cursor.text(from: position, to: end)
    }

    /// A word that starts with a letter, `_`, `*` or a character from U+00C0, and goes on with letters, digits and
    /// `_ - * . [ ] ( ) ,`.
    private mutating func readWord() -> String {
        let start = cursor.position
        var length = characterLength(atOffset: 0, startsWord: true)
        while length > 0 {
            cursor.advance(by: length)
            length = characterLength(atOffset: 0, startsWord: false)
        }
        return cursor.text(from: start, to: cursor.position)
    }

    /// Text in backticks, which may hold any character; without its closing backtick it runs to the end of the text.
    private mutating func readBacktickWord() -> String {
        cursor.advance()
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.graveAccent { cursor.advance() }
        let word = cursor.text(from: start, to: cursor.position)
        if !cursor.isAtEnd { cursor.advance() }
        return word
    }

    private mutating func readComment() throws(MermaidDiagramReadError) -> Token {
        let openingLine = cursor.line
        cursor.advance()
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.quotationMark { cursor.advance() }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedQuotation) }
        let text = cursor.text(from: start, to: cursor.position)
        cursor.advance()
        return .comment(text)
    }

    /// The length in bytes of a word's character at `offset` from the cursor, 0 when there is none there. Beyond
    /// ASCII, Mermaid's pattern takes the characters from U+00C0, and µ.
    private func characterLength(atOffset offset: Int, startsWord: Bool) -> Int {
        guard let byte = cursor.peek(offset) else { return 0 }
        if byte < 0x80 {
            let isWordByte = MermaidByte.isLetter(byte) || byte == MermaidByte.underscore || byte == Self.asterisk
            if startsWord { return isWordByte ? 1 : 0 }
            return isWordByte || MermaidByte.isDigit(byte) || Self.laterWordBytes.contains(byte) ? 1 : 0
        }
        if byte == Self.leadByteBelowU00C0 { return cursor.peek(offset + 1) == Self.microSignSecondByte ? 2 : 0 }
        guard byte > Self.leadByteBelowU00C0, byte & 0xC0 != 0x80 else { return 0 }
        var length = 1
        while let continuation = cursor.peek(offset + length), continuation & 0xC0 == 0x80 { length += 1 }
        return length
    }

    /// 1 or 2 for whitespace at `index` (ASCII whitespace, or a no-break space), 0 otherwise.
    private func whitespaceLength(at index: Int) -> Int {
        let bytes = cursor.bytes
        guard index < bytes.count else { return 0 }
        if EntityRelationshipLexer.isWhitespace(bytes[index]) { return 1 }
        return bytes[index] == Self.leadByteBelowU00C0 && index + 1 < bytes.count && bytes[index + 1] == Self.noBreakSpaceSecondByte ? 2 : 0
    }

    /// The first index from `start` that `matches`, or the end of the text.
    private func firstPosition(from start: Int, where matches: (Int) -> Bool) -> Int {
        var index = start
        while index < cursor.bytes.count, !matches(index) { index += 1 }
        return index
    }

    private static let commentStart = Array("%%".utf8)
    private static let emptyBackticks = Array("``".utf8)
    private static let tilde = UInt8(ascii: "~")
    private static let questionMark = UInt8(ascii: "?")
    private static let asterisk = UInt8(ascii: "*")
    /// After a word's first character: `-`, `.`, brackets, parentheses and commas, as in `public.geometry(point,4326)`.
    private static let laterWordBytes: Set<UInt8> = [MermaidByte.hyphen, MermaidByte.period, MermaidByte.openingBracket, MermaidByte.closingBracket,
                                                     UInt8(ascii: "("), UInt8(ascii: ")"), MermaidByte.comma]
    /// The UTF-8 lead byte of the characters U+0080 to U+00BF.
    private static let leadByteBelowU00C0: UInt8 = 0xC2
    private static let microSignSecondByte: UInt8 = 0xB5
    private static let noBreakSpaceSecondByte: UInt8 = 0xA0
}
