/// Reads the participant named after `participant`, `actor`, `destroy`, `activate` and `deactivate`, as Mermaid's
/// sequence grammar does: a name, then `as` and an alias, or `@{ … }` attributes.
enum SequenceParticipantSyntax {
    struct Declaration {
        let identifier: String
        /// The text after `as`, or nil.
        let alias: SequenceTextSyntax.WrittenText?
        /// Whether `@{ … }` follows the name: attributes that set a shape or an alias, which are not laid out.
        let hasAttributes: Bool
    }

    /// Reads a name with its alias or attributes. A name without either runs to the end of the statement and may hold
    /// spaces (`participant Web server`); before `as` or `@{` it holds none.
    static func readDeclaration(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> Declaration {
        cursor.skipSpaces()
        guard let first = cursor.peek(), !MermaidByte.endsStatement(first), first != SequenceTextSyntax.numberSign else {
            throw .invalidSyntax(line: cursor.line, problem: .sequence(.expectedParticipant))
        }
        guard !cursor.hasPrefix(attributesStart) else { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
        if let declaration = try readShortNameWithAliasOrAttributes(&cursor) { return declaration }
        return Declaration(identifier: try readWideName(&cursor), alias: nil, hasAttributes: false)
    }

    /// Reads a name that nothing may follow but the statement's end, for `destroy`, `activate` and `deactivate`.
    static func readName(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> String {
        let line = cursor.line
        let declaration = try readDeclaration(&cursor)
        guard declaration.alias == nil, !declaration.hasAttributes else { throw .invalidSyntax(line: line, problem: .unexpectedText(declaration.identifier)) }
        return declaration.identifier
    }

    /// `A as Alice`, `A@{ … }` or `A@{ … } as Alice`; nil, with the cursor unmoved, when the name is followed by neither.
    private static func readShortNameWithAliasOrAttributes(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> Declaration? {
        var lookahead = cursor
        let start = lookahead.position
        while let byte = lookahead.peek(), !MermaidByte.isWhitespace(byte), !isNameDelimiter(byte) { lookahead.advance() }
        guard lookahead.position > start else { return nil }
        let identifier = lookahead.text(from: start, to: lookahead.position)
        var afterName = lookahead
        afterName.skipSpaces()
        let hasAttributes = afterName.hasPrefix(attributesStart)
        if hasAttributes {
            try skipAttributes(&afterName)
            lookahead = afterName
            afterName.skipSpaces()
        }
        guard afterName.position > lookahead.position, isAtAlias(afterName) else {
            guard hasAttributes else { return nil }
            cursor = lookahead
            return Declaration(identifier: identifier, alias: nil, hasAttributes: true)
        }
        afterName.advance(by: aliasKeyword.count)
        afterName.skipSpaces()
        let alias = SequenceTextSyntax.readText(&afterName)
        cursor = afterName
        return Declaration(identifier: identifier, alias: alias, hasAttributes: hasAttributes)
    }

    /// A name to the end of the statement, spaces included. Before any of `< > : , @` the name must end at a `#` that
    /// starts a comment, as in Mermaid; otherwise the text is not a name.
    private static func readWideName(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> String {
        let start = cursor.position
        var end = cursor
        while let byte = end.peek(), !isNameDelimiter(byte) { end.advance() }
        if let byte = end.peek(), !MermaidByte.endsStatement(byte) {
            guard let commentStart = cursor.bytes[start..<end.position].lastIndex(of: SequenceTextSyntax.numberSign), commentStart > start else {
                throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
            }
            let name = cursor.trimmedText(from: start, to: commentStart)
            cursor.advance(by: commentStart - start)
            return name
        }
        cursor = end
        return cursor.trimmedText(from: start, to: end.position)
    }

    /// Moves past `@{ … }`.
    private static func skipAttributes(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) {
        let openingLine = cursor.line
        while let byte = cursor.peek(), byte != MermaidByte.closingBrace { cursor.advance() }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedAttributes) }
        cursor.advance()
    }

    /// `as` in any case, then a space, a tab, a line break or the end of the text.
    private static func isAtAlias(_ cursor: MermaidTextCursor) -> Bool {
        guard cursor.hasCaseInsensitivePrefix(aliasKeyword) else { return false }
        guard let following = cursor.peek(aliasKeyword.count) else { return true }
        return MermaidByte.isWhitespace(following)
    }

    /// The bytes no participant name holds: `< > : , ; @` and line breaks.
    private static func isNameDelimiter(_ byte: UInt8) -> Bool {
        byte == MermaidByte.lessThan || byte == MermaidByte.greaterThan || byte == MermaidByte.colon || byte == MermaidByte.comma
            || byte == MermaidByte.semicolon || byte == MermaidByte.atSign || byte == MermaidByte.newline
    }

    private static let attributesStart = Array("@{".utf8)
    private static let aliasKeyword = Array("as".utf8)
}
