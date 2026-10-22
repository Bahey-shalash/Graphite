/// Reads a flowchart's statements after its `flowchart` or `graph` keyword: the direction, then chains of nodes and
/// links (`A & B --> C -->|yes| D`), groups (`subgraph … end`), accessibility text, and the statements that only
/// style the diagram, which are counted and left. Statements end at a line break or a semicolon; `%%` starts a comment.
struct FlowchartParser {
    private var cursor: MermaidTextCursor
    private var builder: FlowchartDiagramBuilder

    /// Reads the flowchart whose keyword ends at the cursor.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> FlowchartDiagram {
        var parser = FlowchartParser(cursor: cursor, builder: FlowchartDiagramBuilder(limits: limits))
        try parser.readDirection()
        try parser.readStatements()
        return parser.builder.diagram
    }

    private mutating func readDirection() throws(MermaidDiagramReadError) {
        cursor.skipSpaces()
        guard let byte = cursor.peek(), !MermaidByte.endsStatement(byte), !cursor.hasPrefix(Self.commentStart) else { return }
        let start = cursor.position
        if MermaidByte.isLetter(byte) { _ = cursor.readWord() } else { cursor.advance() }
        let keyword = cursor.text(from: start, to: cursor.position)
        guard let direction = FlowchartDirection(keyword: keyword) else {
            throw .invalidSyntax(line: cursor.line, problem: .unknownDirection(keyword))
        }
        builder.setDirection(direction)
        try expectStatementEnd()
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            cursor.skipWhitespace()
            while cursor.peek() == MermaidByte.semicolon {
                cursor.advance()
                cursor.skipWhitespace()
            }
            if cursor.isAtEnd { break }
            if cursor.hasPrefix(Self.commentStart) {
                cursor.skipToEndOfLine()
                continue
            }
            if try readKeywordStatement() { continue }
            try readChain()
            try expectStatementEnd()
        }
        if let identifier = builder.innermostOpenSubgraphIdentifier {
            throw .invalidSyntax(line: cursor.line, problem: .unclosedSubgraph(identifier: identifier))
        }
    }

    /// Reads a statement that starts with a keyword, and returns whether there was one. A word is a keyword only when
    /// a space, a colon, a brace or the statement's end follows it, so that `classes --> B` is a chain.
    private mutating func readKeywordStatement() throws(MermaidDiagramReadError) -> Bool {
        var lookahead = cursor
        guard let word = lookahead.readWord(), Self.keywords.contains(word) else { return false }
        if let next = lookahead.peek(), !MermaidByte.isSpace(next), !MermaidByte.endsStatement(next),
           next != MermaidByte.colon, next != MermaidByte.openingBrace { return false }
        let statementLine = cursor.line
        cursor = lookahead
        switch word {
        case "subgraph": readSubgraphOpening()
        case "end":
            guard builder.closeSubgraph() else { throw .invalidSyntax(line: statementLine, problem: .endWithoutSubgraph) }
            try expectStatementEnd()
        case "accTitle": builder.setAccessibilityTitle(readAccessibilityLine())
        case "accDescr": builder.setAccessibilityDescription(try readAccessibilityDescription())
        default:
            // `direction` inside a group, `classDef`, `class`, `style`, `linkStyle` and `click`.
            skipStatement()
            builder.countUnappliedStatement()
        }
        return true
    }

    /// `A & B --> C -->|text| D`: node groups joined by links, each link making an edge from every node before it to
    /// every node after it.
    private mutating func readChain() throws(MermaidDiagramReadError) {
        guard let firstGroup = try readNodeGroup() else { return }
        var previousGroup = firstGroup
        while true {
            cursor.skipSpaces()
            guard let link = try FlowchartLinkSyntax.readLink(&cursor) else { return }
            if let identifier = link.identifier { builder.recordEdgeIdentifier(identifier) }
            cursor.skipSpaces()
            guard let nextGroup = try readNodeGroup() else { throw .invalidSyntax(line: cursor.line, problem: .expectedNode) }
            try builder.addEdges(from: previousGroup, to: nextGroup, link: link)
            previousGroup = nextGroup
        }
    }

    /// `A & B & C`: the indexes of the nodes, or nil for an edge's attributes (`e1@{ … }`), which name no node.
    private mutating func readNodeGroup() throws(MermaidDiagramReadError) -> [Int]? {
        var indices: [Int] = []
        repeat {
            if !indices.isEmpty {
                cursor.advance()
                cursor.skipSpaces()
            }
            guard let index = try readNode() else { return indices.isEmpty ? nil : indices }
            indices.append(index)
            cursor.skipSpaces()
        } while cursor.peek() == MermaidByte.ampersand
        return indices
    }

    /// A node: its identifier, then its shape and text or its attributes, then any `:::class`.
    private mutating func readNode() throws(MermaidDiagramReadError) -> Int? {
        let line = cursor.line
        guard let identifier = cursor.readIdentifier() else {
            throw .invalidSyntax(line: line, problem: cursor.isAtEnd ? .expectedNode : .unexpectedText(cursor.excerpt()))
        }
        if FlowchartNodeSyntax.isAtAttributes(cursor), builder.isEdgeIdentifier(identifier) {
            _ = try FlowchartNodeSyntax.readAttributes(&cursor)
            builder.countUnappliedStatement()
            return nil
        }
        let index = try builder.nodeIndex(for: identifier)
        if FlowchartNodeSyntax.isAtAttributes(cursor) {
            builder.define(nodeAt: index, as: try FlowchartNodeSyntax.readAttributes(&cursor))
        } else if let definition = try FlowchartNodeSyntax.readShape(&cursor) {
            builder.define(nodeAt: index, as: definition)
        }
        while cursor.hasPrefix(Self.classMarker) {
            cursor.advance(by: Self.classMarker.count)
            _ = cursor.readIdentifier()
            builder.countUnappliedStatement()
        }
        return index
    }

    /// `subgraph id[title]`, `subgraph id ["title"]`, `subgraph "title"` or `subgraph title words`.
    private mutating func readSubgraphOpening() {
        cursor.skipSpaces()
        var lookahead = cursor
        if let identifier = lookahead.readIdentifier() {
            lookahead.skipSpaces()
            if lookahead.peek() == MermaidByte.openingBracket, let title = Self.bracketedTitle(&lookahead) {
                cursor = lookahead
                builder.openSubgraph(identifier: identifier, title: title)
                return
            }
        }
        let written = FlowchartTextSyntax.unquoted(cursor.readRestOfLine())
        let title = DiagramLabelDecoder.label(from: written.text, form: written.form)
        let isOneWord = !written.text.isEmpty && !written.text.contains(where: \.isWhitespace)
        builder.openSubgraph(identifier: isOneWord ? written.text : "subGraph\(builder.subgraphCount)", title: title)
    }

    /// `[title]` after a group's identifier, or nil when the brackets do not close: the line is then read as words.
    private static func bracketedTitle(_ cursor: inout MermaidTextCursor) -> DiagramLabel? {
        cursor.advance()
        let closings = [[MermaidByte.closingBracket]]
        let title = try? FlowchartTextSyntax.readText(&cursor, closedByAnyOf: closings, openingLine: cursor.line) // Unclosed: read as words.
        return title?.0
    }

    /// `accTitle: text`, to the end of the line.
    private mutating func readAccessibilityLine() -> String {
        cursor.skipSpaces()
        if cursor.peek() == MermaidByte.colon { cursor.advance() }
        cursor.skipSpaces()
        return DiagramLabelDecoder.decodingEntities(cursor.readRestOfLine())
    }

    /// `accDescr: text` or `accDescr { lines }`.
    private mutating func readAccessibilityDescription() throws(MermaidDiagramReadError) -> String {
        cursor.skipSpaces()
        guard cursor.peek() == MermaidByte.openingBrace else { return readAccessibilityLine() }
        let openingLine = cursor.line
        cursor.advance()
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.closingBrace { cursor.advance() }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedAccessibilityDescription) }
        let description = cursor.text(from: start, to: cursor.position)
        cursor.advance()
        return DiagramLabelDecoder.label(from: description, form: .plain).lines.filter { line in !line.isEmpty }.joined(separator: " ")
    }

    /// Moves to the end of a statement that is not read: the next line break, or semicolon outside quotation marks.
    private mutating func skipStatement() {
        var isInsideQuotation = false
        while let byte = cursor.peek(), byte != MermaidByte.newline {
            if byte == MermaidByte.quotationMark { isInsideQuotation.toggle() }
            if byte == MermaidByte.semicolon, !isInsideQuotation { return }
            cursor.advance()
        }
    }

    /// A statement ends at a line break, a semicolon, a comment or the end of the text; anything else is an error.
    private mutating func expectStatementEnd() throws(MermaidDiagramReadError) {
        cursor.skipSpaces()
        guard let byte = cursor.peek(), !MermaidByte.endsStatement(byte) else { return }
        if cursor.hasPrefix(Self.commentStart) {
            cursor.skipToEndOfLine()
            return
        }
        throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
    }

    private static let keywords: Set<String> = ["subgraph", "end", "direction", "classDef", "class", "style", "linkStyle", "click",
                                                "accTitle", "accDescr"]
    private static let commentStart = Array("%%".utf8)
    private static let classMarker = Array(":::".utf8)
}
