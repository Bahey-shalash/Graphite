/// Reads a mindmap's lines after its `mindmap` keyword, the rest of the keyword's own line included. A line holds one
/// statement: a node, indented to show its place in the tree; an icon (`::icon(…)`) or classes (`:::…`) for the
/// node above it, read and not drawn; or accessibility text. Blank lines and `%%` comments are skipped, and a `%%`
/// comment may end a line. Mermaid's mindmap grammar has no accessibility text: its `accTitle` and `accDescr` would
/// be nodes, and here they are read for a screen reader, as the other types read them.
struct MindmapParser {
    private var cursor: MermaidTextCursor
    private var builder: MindmapTreeBuilder

    /// Reads the mindmap whose keyword ends at the cursor. A mindmap without a node is an error, as in Mermaid.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> MindmapDiagram {
        var parser = MindmapParser(cursor: cursor, builder: MindmapTreeBuilder(limits: limits))
        try parser.readLines()
        guard !parser.builder.diagram.nodes.isEmpty else { throw .invalidSyntax(line: parser.cursor.line, problem: .expectedNode) }
        return parser.builder.diagram
    }

    private mutating func readLines() throws(MermaidDiagramReadError) {
        while !cursor.isAtEnd {
            let indentation = readIndentation()
            if isAtLineEnd {
                skipLineEnd()
                continue
            }
            if cursor.hasPrefix(Self.commentStart) {
                cursor.skipToEndOfLine()
                continue
            }
            try readStatement(indentation: indentation)
            try expectLineEnd()
        }
    }

    /// Moves past the spaces and tabs that start a line and returns how many there were.
    private mutating func readIndentation() -> Int {
        let start = cursor.position
        cursor.skipSpaces()
        return cursor.position - start
    }

    private mutating func readStatement(indentation: Int) throws(MermaidDiagramReadError) {
        let line = cursor.line
        if let statement = try MermaidAccessibilityStatement.read(&cursor) {
            builder.apply(statement)
        } else if cursor.hasPrefix(Self.classMarker) {
            cursor.skipToEndOfLine()
            builder.countUnappliedDecoration()
        } else if cursor.hasCaseInsensitivePrefix(Self.iconStart) {
            try readIcon()
        } else {
            try builder.addNode(MindmapNodeSyntax.readNode(&cursor), indentation: indentation, line: line)
        }
    }

    /// `::icon(name)`: the name runs to the closing parenthesis.
    private mutating func readIcon() throws(MermaidDiagramReadError) {
        let openingLine = cursor.line
        cursor.advance(by: Self.iconStart.count)
        while let byte = cursor.peek(), byte != Self.closingParenthesis { cursor.advance() }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedIcon) }
        cursor.advance()
        builder.countUnappliedDecoration()
    }

    private var isAtLineEnd: Bool {
        guard let byte = cursor.peek() else { return true }
        return byte == MermaidByte.newline || byte == MermaidByte.carriageReturn
    }

    /// Moves past a line break, `\n` or `\r\n`.
    private mutating func skipLineEnd() {
        if cursor.peek() == MermaidByte.carriageReturn { cursor.advance() }
        if cursor.peek() == MermaidByte.newline { cursor.advance() }
    }

    /// A statement is followed by spaces, an optional `%%` comment and the end of its line; anything else is an error.
    private mutating func expectLineEnd() throws(MermaidDiagramReadError) {
        cursor.skipSpaces()
        if cursor.hasPrefix(Self.commentStart) { cursor.skipToEndOfLine() }
        guard isAtLineEnd else { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
        skipLineEnd()
    }

    private static let commentStart = Array("%%".utf8)
    private static let classMarker = Array(":::".utf8)
    /// Lowercased, for a comparison without regard to case.
    private static let iconStart = Array("::icon(".utf8)
    private static let closingParenthesis = UInt8(ascii: ")")
}
