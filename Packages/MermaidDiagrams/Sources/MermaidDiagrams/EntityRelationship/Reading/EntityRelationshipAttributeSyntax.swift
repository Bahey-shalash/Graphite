/// Reads the attributes inside an entity's `{ … }` as Mermaid does: each a type and a name (`string? alias`), then
/// keys joined by commas (`PK, FK`) and a comment in quotation marks, with any whitespace between them, line breaks
/// included. A type or name is a word of letters, digits and `_ - * . [ ] ( ) ,` (starting with a letter, `_` or
/// `*`), a run that holds `~` (to the last `~` of its line), or any text in backticks.
struct EntityRelationshipAttributeSyntax {
    private var words: EntityRelationshipAttributeWords
    private let entity: String
    private let openingLine: Int

    /// Reads from just after an entity's `{` through its `}`, and leaves the cursor after the `}`.
    /// - Parameter entity: The entity's name, which an unclosed block is reported with.
    static func readBlock(_ cursor: inout MermaidTextCursor, entity: String) throws(MermaidDiagramReadError) -> [EntityRelationshipAttribute] {
        var syntax = EntityRelationshipAttributeSyntax(words: EntityRelationshipAttributeWords(cursor: cursor), entity: entity, openingLine: cursor.line)
        let attributes = try syntax.readAttributes()
        cursor = syntax.words.cursor
        return attributes
    }

    private mutating func readAttributes() throws(MermaidDiagramReadError) -> [EntityRelationshipAttribute] {
        var attributes: [EntityRelationshipAttribute] = []
        var token = try words.next()
        while token != .closingBrace {
            guard case .word(var type) = token else { throw problem(at: token) }
            token = try words.next()
            if token == .questionMark {
                type += "?"
                token = try words.next()
            }
            guard case .word(let name) = token else { throw problem(at: token) }
            token = try words.next()
            let keys = try readKeys(&token)
            var comment: DiagramLabel?
            if case .comment(let text) = token {
                comment = Self.commentLabel(text)
                token = try words.next()
            }
            attributes.append(EntityRelationshipAttribute(type: EntityRelationshipGenericType.angleBracketed(type),
                                                          name: EntityRelationshipGenericType.angleBracketed(name), keys: keys, comment: comment))
        }
        return attributes
    }

    /// `PK`, `PK, FK`, or none, starting at `token`; leaves `token` at what follows them.
    private mutating func readKeys(_ token: inout EntityRelationshipAttributeWords.Token) throws(MermaidDiagramReadError) -> [EntityRelationshipAttributeKey] {
        guard case .key(let first) = token else { return [] }
        var keys = [first]
        token = try words.next()
        while token == .comma {
            token = try words.next()
            guard case .key(let key) = token else { throw problem(at: token) }
            keys.append(key)
            token = try words.next()
        }
        return keys
    }

    /// A comment drawn as Markdown, as Mermaid draws it: entity codes and `<br>` read, emphasis markers dropped, and
    /// pairs of `~` read as angle brackets, as in a type.
    private static func commentLabel(_ text: String) -> DiagramLabel {
        let label = DiagramLabelDecoder.label(from: text, form: .markdown)
        return DiagramLabel(lines: label.lines.map(EntityRelationshipGenericType.angleBracketed))
    }

    /// The text ending before the `}` is an unclosed block; anything else in the wrong place is no attribute.
    private func problem(at token: EntityRelationshipAttributeWords.Token) -> MermaidDiagramReadError {
        token == .endOfText ? .invalidSyntax(line: openingLine, problem: .unclosedAttributeBlock(entity: entity))
                            : .invalidSyntax(line: words.tokenLine, problem: .expectedAttribute)
    }
}
