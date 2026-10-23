import Foundation

/// A state as a statement names it: `[*]`, which is a start or an end by where it stands, or an identifier.
enum StateDiagramStateReference: Equatable {
    case startOrEnd
    case named(String)
}

/// Reads the pieces of a state diagram's statements: state references, the text after a colon, and quoted text. An
/// identifier runs to a space, a line break, a colon, a hyphen, a brace or a semicolon, and stops before `%%`, which
/// starts a comment, as in Mermaid's grammar (so `step-1` is not one identifier). Text is Markdown, where `<br>`, a
/// line break and the two characters `\n` all end a line.
enum StateDiagramTextSyntax {
    /// `[*]` or an identifier at the cursor, or nil when there is neither.
    static func readReference(_ cursor: inout MermaidTextCursor) -> StateDiagramStateReference? {
        if cursor.hasPrefix(startOrEndMarker) {
            cursor.advance(by: startOrEndMarker.count)
            return .startOrEnd
        }
        return readIdentifier(&cursor).map(StateDiagramStateReference.named)
    }

    /// An identifier at the cursor, or nil when the cursor is at a byte that ends one.
    static func readIdentifier(_ cursor: inout MermaidTextCursor) -> String? {
        let start = cursor.position
        while let byte = cursor.peek(), !endsIdentifier(byte), !cursor.hasPrefix(commentStart) { cursor.advance() }
        return cursor.position > start ? cursor.text(from: start, to: cursor.position) : nil
    }

    /// Whether `byte` ends an identifier.
    static func endsIdentifier(_ byte: UInt8) -> Bool {
        MermaidByte.isWhitespace(byte) || byte == MermaidByte.colon || byte == MermaidByte.hyphen || byte == MermaidByte.openingBrace
            || byte == MermaidByte.semicolon
    }

    /// The text after a colon at the cursor (`A : text`, `A --> B : text`), to the end of the line or a semicolon,
    /// or nil when no colon is there or nothing but spaces follows it. Only the first colon is taken off: the text
    /// may hold others (`error (ex: timeout)`).
    static func readColonText(_ cursor: inout MermaidTextCursor) -> DiagramLabel? {
        guard cursor.peek() == MermaidByte.colon else { return nil }
        cursor.advance()
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.newline, byte != MermaidByte.semicolon { cursor.advance() }
        let text = cursor.trimmedText(from: start, to: cursor.position)
        return text.isEmpty ? nil : label(from: text)
    }

    /// Text between quotation marks at the cursor, which may run over several lines; the cursor moves past the
    /// closing mark. Nil when the cursor is not at a quotation mark.
    static func readQuotedText(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> String? {
        guard cursor.peek() == MermaidByte.quotationMark else { return nil }
        let openingLine = cursor.line
        cursor.advance()
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.quotationMark { cursor.advance() }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedQuotation) }
        let text = cursor.text(from: start, to: cursor.position)
        cursor.advance()
        return text
    }

    /// Whether the word at the cursor is `word` in any case, followed by a space, a line break or the end, so that
    /// `assemble` is not `as` and `classroom` is not `class`. `word` is lowercase.
    static func isAtKeyword(_ cursor: MermaidTextCursor, _ word: [UInt8]) -> Bool {
        guard cursor.hasCaseInsensitivePrefix(word) else { return false }
        guard let next = cursor.peek(word.count) else { return true }
        return MermaidByte.isWhitespace(next)
    }

    /// The drawn lines of text written for a state, a transition or a note.
    static func label(from text: String) -> DiagramLabel {
        let withLineBreaks = text.contains("\\n") ? text.replacingOccurrences(of: "\\n", with: "\n") : text
        // Without emphasis markers, Markdown text reads as plain text, which skips the decoder when it is one plain line.
        let hasEmphasisMarkers = withLineBreaks.utf8.contains { byte in byte == UInt8(ascii: "*") || byte == MermaidByte.underscore }
        return DiagramLabelDecoder.label(from: withLineBreaks, form: hasEmphasisMarkers ? .markdown : .plain)
    }

    static let startOrEndMarker = Array("[*]".utf8)
    static let commentStart = Array("%%".utf8)
}
