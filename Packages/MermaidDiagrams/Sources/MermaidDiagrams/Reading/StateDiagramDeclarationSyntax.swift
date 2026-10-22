import Foundation

/// What a `state` statement declares.
enum StateDiagramDeclaration: Equatable {
    /// `state Id <<fork>>`, `<<join>>`, `<<choice>>`, or the same in double brackets (`[[choice]]`).
    case stereotyped(identifier: String, kind: StateDiagramStateKind)
    /// `state "text" as Id`, or `state "text" as Id:more text`, which gives the state a second description.
    case described(identifier: String, descriptions: [DiagramLabel], opensBody: Bool)
    /// `state Id {`: a composite state whose body follows.
    case composite(identifier: String)
    /// `state Id` alone, which declares nothing in Mermaid: a state is made by naming it in another statement.
    case nothing
}

/// Reads what follows the keyword `state`.
enum StateDiagramDeclarationSyntax {
    /// Reads from the cursor, after `state` and its space, to the end of the declaration; for one that opens a body,
    /// the cursor ends past the `{`.
    static func readDeclaration(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> StateDiagramDeclaration {
        cursor.skipSpaces()
        let line = cursor.line
        if let (identifier, kind) = readStereotyped(&cursor) {
            guard !identifier.isEmpty else { throw .invalidSyntax(line: line, problem: .expectedState) }
            return .stereotyped(identifier: identifier, kind: kind)
        }
        if let description = try StateDiagramTextSyntax.readQuotedText(&cursor) {
            return try readDescribed(&cursor, description: description)
        }
        let start = cursor.position
        while let byte = cursor.peek(), !MermaidByte.isWhitespace(byte), byte != MermaidByte.openingBrace { cursor.advance() }
        let identifier = cursor.text(from: start, to: cursor.position)
        guard !identifier.isEmpty else { throw .invalidSyntax(line: line, problem: .expectedState) }
        cursor.skipSpaces()
        if cursor.peek() == MermaidByte.openingBrace {
            cursor.advance()
            return .composite(identifier: identifier)
        }
        // More words on the line declare nothing, unless a brace follows them: a composite's name is one word.
        let wordsStart = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.newline, byte != MermaidByte.semicolon, byte != MermaidByte.openingBrace,
              !cursor.hasPrefix(StateDiagramTextSyntax.commentStart) {
            cursor.advance()
        }
        if cursor.peek() == MermaidByte.openingBrace {
            let words = identifier + " " + cursor.trimmedText(from: wordsStart, to: cursor.position)
            throw .invalidSyntax(line: line, problem: .stateNameNotOneWord(words))
        }
        return .nothing
    }

    /// `Id <<kind>>` on the rest of the line: the text before the stereotype, trimmed, and the kind; the cursor moves
    /// past the stereotype. Nil when the line holds none before a line break or a comment.
    private static func readStereotyped(_ cursor: inout MermaidTextCursor) -> (String, StateDiagramStateKind)? {
        var lookahead = cursor
        let start = lookahead.position
        while let byte = lookahead.peek(), byte != MermaidByte.newline, !lookahead.hasPrefix(StateDiagramTextSyntax.commentStart) {
            if let (kind, length) = stereotype(at: lookahead) {
                let identifier = lookahead.trimmedText(from: start, to: lookahead.position)
                lookahead.advance(by: length)
                cursor = lookahead
                return (identifier, kind)
            }
            lookahead.advance()
        }
        return nil
    }

    /// The stereotype at the cursor and its length in bytes, or nil.
    private static func stereotype(at cursor: MermaidTextCursor) -> (StateDiagramStateKind, Int)? {
        let isAngled = cursor.hasPrefix(angledOpening)
        guard isAngled || cursor.hasPrefix(bracketedOpening) else { return nil }
        let closing = isAngled ? angledClosing : bracketedClosing
        for (kind, name) in stereotypeNames {
            var nameCursor = cursor
            nameCursor.advance(by: angledOpening.count)
            guard nameCursor.hasCaseInsensitivePrefix(name) else { continue }
            nameCursor.advance(by: name.count)
            if nameCursor.hasPrefix(closing) { return (kind, angledOpening.count + name.count + closing.count) }
        }
        return nil
    }

    /// `"text" as Id`, `"text" as Id:more` or `"text" as Id {`, after the quoted text.
    private static func readDescribed(_ cursor: inout MermaidTextCursor, description: String) throws(MermaidDiagramReadError) -> StateDiagramDeclaration {
        cursor.skipWhitespace()
        guard StateDiagramTextSyntax.isAtKeyword(cursor, asKeyword) else {
            throw .invalidSyntax(line: cursor.line, problem: cursor.isAtEnd ? .expectedState : .unexpectedText(cursor.excerpt()))
        }
        cursor.advance(by: asKeyword.count)
        cursor.skipSpaces()
        let line = cursor.line
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.newline, byte != MermaidByte.openingBrace,
              !cursor.hasPrefix(StateDiagramTextSyntax.commentStart) {
            cursor.advance()
        }
        var identifier = cursor.trimmedText(from: start, to: cursor.position)
        var descriptions = [StateDiagramTextSyntax.label(from: description.trimmingCharacters(in: .whitespacesAndNewlines))]
        if let colon = identifier.firstIndex(of: ":") {
            descriptions.append(StateDiagramTextSyntax.label(from: identifier[identifier.index(after: colon)...].trimmingCharacters(in: .whitespaces)))
            identifier = identifier[..<colon].trimmingCharacters(in: .whitespaces)
        }
        guard !identifier.isEmpty else { throw .invalidSyntax(line: line, problem: .expectedState) }
        let opensBody = cursor.peek() == MermaidByte.openingBrace
        if opensBody { cursor.advance() }
        return .described(identifier: identifier, descriptions: descriptions.filter { label in !label.isEmpty }, opensBody: opensBody)
    }

    /// The kinds a stereotype names, by their names in lowercase.
    private static let stereotypeNames: [(StateDiagramStateKind, [UInt8])] = [(.fork, Array("fork".utf8)), (.join, Array("join".utf8)),
                                                                             (.choice, Array("choice".utf8))]
    private static let asKeyword = Array("as".utf8)
    private static let angledOpening = Array("<<".utf8)
    private static let angledClosing = Array(">>".utf8)
    private static let bracketedOpening = Array("[[".utf8)
    private static let bracketedClosing = Array("]]".utf8)
}
