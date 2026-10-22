/// Reads the names and texts of a sequence diagram's statements, as Mermaid's sequence grammar delimits them.
enum SequenceTextSyntax {
    /// Text read to the end of a statement, without its `wrap:` or `nowrap:` prefix.
    struct WrittenText {
        let text: String
        /// True after `wrap:`, false after `nowrap:` or without a prefix (Mermaid's default).
        let wraps: Bool

        var label: DiagramLabel {
            DiagramLabelDecoder.label(from: text, form: .plain)
        }
    }

    static let numberSign = UInt8(ascii: "#")
    static let plusSign = UInt8(ascii: "+")
    static let openingParenthesis = UInt8(ascii: "(")
    static let closingParenthesis = UInt8(ascii: ")")
    static let slash = UInt8(ascii: "/")
    static let backslash = UInt8(ascii: "\\")

    /// A participant's name where a message or a note names it: a first character that is no operator, then text up
    /// to an arrow, a `+`, `<`, `>`, `:`, `,`, `;` or line break. Inner hyphens are kept where no arrow starts, so that
    /// `Alice-in-Wonderland` is one name. Spaces inside are kept and spaces around dropped. Nil when there is no name.
    static func readParticipantName(_ cursor: inout MermaidTextCursor) -> String? {
        guard let first = cursor.peek(), canStartName(first) else { return nil }
        let start = cursor.position
        cursor.advance()
        while let byte = cursor.peek(), canStartName(byte) { cursor.advance() }
        while !isAtArrow(cursor) {
            var lookahead = cursor
            while lookahead.peek() == MermaidByte.hyphen { lookahead.advance() }
            guard let byte = lookahead.peek(), canContinueName(byte) else { break }
            while let byte = lookahead.peek(), canContinueName(byte) { lookahead.advance() }
            cursor = lookahead
        }
        return cursor.trimmedText(from: start, to: cursor.position)
    }

    /// Reads the text of a statement to its end: a line break, a `;`, or a `#` that starts a comment. Mermaid keeps
    /// its entity codes (`#9829;`, `#quot;`) whole, so a `#` that starts one is text. A `wrap:` or `nowrap:` prefix
    /// says whether the text wraps.
    static func readText(_ cursor: inout MermaidTextCursor) -> WrittenText {
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.newline, byte != MermaidByte.semicolon {
            if byte == numberSign {
                guard let length = entityCodeLength(at: cursor) else { break }
                cursor.advance(by: length)
                continue
            }
            cursor.advance()
        }
        return withoutWrapPrefix(cursor.trimmedText(from: start, to: cursor.position))
    }

    /// `:` and the text after it, as a message or a note ends. Nil when no colon follows.
    static func readColonText(_ cursor: inout MermaidTextCursor) -> WrittenText? {
        cursor.skipSpaces()
        guard cursor.peek() == MermaidByte.colon else { return nil }
        cursor.advance()
        return readText(&cursor)
    }

    /// The text without a leading `wrap:`, `:wrap:`, `nowrap:` or `:nowrap:`, and whether it wraps.
    static func withoutWrapPrefix(_ text: String) -> WrittenText {
        let unprefixed = text.hasPrefix(":") ? text.dropFirst() : Substring(text)
        for (prefix, wraps) in [("wrap:", true), ("nowrap:", false)] where unprefixed.hasPrefix(prefix) {
            return WrittenText(text: unprefixed.dropFirst(prefix.count).trimmingSpaces(), wraps: wraps)
        }
        return WrittenText(text: text, wraps: false)
    }

    /// Whether an arrow starts at the cursor, so that a name stops before it: `-x`, `-)`, `--`, the half arrows
    /// (`-|\`, `-\\`, `/|-`, `//-`, …) and `()`.
    static func isAtArrow(_ cursor: MermaidTextCursor) -> Bool {
        guard let first = cursor.peek(), let second = cursor.peek(1) else { return false }
        switch first {
        case MermaidByte.hyphen:
            if [MermaidByte.letterX, UInt8(ascii: "X"), closingParenthesis, backslash, slash, MermaidByte.hyphen].contains(second) { return true }
            return second == MermaidByte.verticalBar && (cursor.peek(2) == backslash || cursor.peek(2) == slash)
        case slash, backslash:
            return (second == MermaidByte.verticalBar || second == first) && cursor.peek(2) == MermaidByte.hyphen
        case openingParenthesis:
            return second == closingParenthesis
        default:
            return false
        }
    }

    /// The length of an entity code (`#` then letters, digits or underscores, then `;`) at the cursor, or nil.
    private static func entityCodeLength(at cursor: MermaidTextCursor) -> Int? {
        var offset = 1
        while let byte = cursor.peek(offset), MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore { offset += 1 }
        return offset > 1 && cursor.peek(offset) == MermaidByte.semicolon ? offset + 1 : nil
    }

    /// A name's first characters: anything but `/ \ + ( ) < - > : , ;` and line breaks.
    private static func canStartName(_ byte: UInt8) -> Bool {
        switch byte {
        case slash, backslash, plusSign, openingParenthesis, closingParenthesis, MermaidByte.lessThan, MermaidByte.hyphen,
             MermaidByte.greaterThan, MermaidByte.colon, MermaidByte.newline, MermaidByte.comma, MermaidByte.semicolon:
            false
        default:
            true
        }
    }

    /// A name's later characters: anything but `+ < - > : , ;` and line breaks.
    private static func canContinueName(_ byte: UInt8) -> Bool {
        switch byte {
        case plusSign, MermaidByte.lessThan, MermaidByte.hyphen, MermaidByte.greaterThan, MermaidByte.colon, MermaidByte.newline, MermaidByte.comma,
             MermaidByte.semicolon:
            false
        default:
            true
        }
    }
}

extension Substring {
    /// The text without the spaces and tabs at either end.
    fileprivate func trimmingSpaces() -> String {
        var trimmed = self
        while let first = trimmed.first, first == " " || first == "\t" { trimmed = trimmed.dropFirst() }
        while let last = trimmed.last, last == " " || last == "\t" { trimmed = trimmed.dropLast() }
        return String(trimmed)
    }
}
