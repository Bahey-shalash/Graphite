/// An accessibility statement as the mindmap and the timeline read it: `accTitle: text`, `accDescr: text` or
/// `accDescr { lines }`, the keyword in any case.
enum MermaidAccessibilityStatement: Equatable {
    /// The short name a screen reader gives the diagram.
    case title(String)
    /// The longer description a screen reader reads, its lines joined by spaces.
    case description(String)

    /// Reads the statement that starts at the cursor and moves past it, or returns nil and leaves the cursor where it
    /// was when none starts there: a keyword is a statement only when a colon follows it, or a brace after `accDescr`.
    static func read(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> MermaidAccessibilityStatement? {
        let isDescription = cursor.hasCaseInsensitivePrefix(descriptionKeyword)
        guard isDescription || cursor.hasCaseInsensitivePrefix(titleKeyword) else { return nil }
        var lookahead = cursor
        lookahead.advance(by: titleKeyword.count)
        lookahead.skipSpaces()
        if lookahead.peek() == MermaidByte.colon {
            lookahead.advance()
            lookahead.skipSpaces()
            let text = DiagramLabelDecoder.decodingEntities(lookahead.readRestOfLine())
            cursor = lookahead
            return isDescription ? .description(text) : .title(text)
        }
        guard isDescription, lookahead.peek() == MermaidByte.openingBrace else { return nil }
        let openingLine = lookahead.line
        lookahead.advance()
        let start = lookahead.position
        while let byte = lookahead.peek(), byte != MermaidByte.closingBrace { lookahead.advance() }
        guard !lookahead.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedAccessibilityDescription) }
        let written = lookahead.text(from: start, to: lookahead.position)
        lookahead.advance()
        cursor = lookahead
        return .description(DiagramLabelDecoder.label(from: written, form: .plain).spokenText)
    }

    /// Both keywords are eight letters long, lowercased for a comparison without regard to case.
    private static let titleKeyword = Array("acctitle".utf8)
    private static let descriptionKeyword = Array("accdescr".utf8)
}
