/// Reads a class diagram's statements after its `classDiagram` or `classDiagram-v2` keyword: classes with their
/// labels, annotations and members (`class Name["Label"] <<interface>> { … }`, `Name : +member`), relations
/// (`A "1" *-- "*" B : label`), annotations (`<<interface>> Name`), notes, namespaces, the direction and the
/// accessibility text, and the statements that only style the diagram or make it clickable, which are counted and
/// left. A statement ends at a line break; `%%` starts a comment.
struct ClassDiagramParser {
    private var cursor: MermaidTextCursor
    private var builder: ClassDiagramBuilder

    /// Reads the class diagram whose keyword ends at the cursor.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> ClassDiagram {
        var parser = ClassDiagramParser(cursor: cursor, builder: ClassDiagramBuilder(limits: limits))
        try parser.expectStatementEnd()
        try parser.readStatements()
        return parser.builder.finished()
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            cursor.skipWhitespace()
            if cursor.isAtEnd { return }
            if cursor.hasPrefix(Self.commentStart) {
                cursor.skipToEndOfLine()
                continue
            }
            try readStatement()
            try expectStatementEnd()
        }
    }

    private mutating func readStatement() throws(MermaidDiagramReadError) {
        if cursor.hasPrefix(Self.annotationStart) { return try readAnnotationStatement() }
        guard let keyword = keywordAtCursor() else { return try readNameStatement() }
        cursor.advance(by: keyword.utf8.count)
        switch keyword {
        case "class": _ = try readClassStatement()
        case "namespace": try readNamespace()
        case "note": try readNote()
        case "direction": readDirection()
        case "accTitle": builder.setAccessibilityTitle(readAccessibilityLine())
        case "accDescr": builder.setAccessibilityDescription(try readAccessibilityDescription())
        default:
            // `style`, `classDef`, `cssClass`, `click`, `link` and `callback`.
            cursor.skipToEndOfLine()
            builder.countUnappliedStatement()
        }
    }

    /// The keyword at the cursor, when a word of `keywords` starts there and no identifier character follows it.
    /// `accTitle` and `accDescr` count only before their `:` or `{`, so that a class may bear another word's name.
    private func keywordAtCursor() -> String? {
        var lookahead = cursor
        guard let word = lookahead.readWord(), Self.keywords.contains(word) else { return nil }
        if let next = lookahead.peek(), MermaidByte.isIdentifierByte(next) { return nil }
        guard word == "accTitle" || word == "accDescr" else { return word }
        lookahead.skipSpaces()
        return lookahead.peek() == MermaidByte.colon || (word == "accDescr" && lookahead.peek() == MermaidByte.openingBrace) ? word : nil
    }

    // MARK: Classes

    /// `class Name~T~["Label"]:::style <<annotation>> { members }`, each part after the name optional. Returns the
    /// class's index.
    private mutating func readClassStatement() throws(MermaidDiagramReadError) -> Int {
        cursor.skipSpaces()
        guard let name = try ClassDiagramNameSyntax.read(&cursor) else { throw .invalidSyntax(line: cursor.line, problem: .expectedName) }
        let index = try builder.classIndex(for: name)
        cursor.skipSpaces()
        if cursor.peek() == MermaidByte.openingBracket { builder.setLabel(try readBracketedLabel(), ofClassAt: index) }
        cursor.skipSpaces()
        if cursor.hasPrefix(Self.styleSeparator) {
            cursor.advance(by: Self.styleSeparator.count)
            _ = cursor.readIdentifier()
            builder.countUnappliedStatement()
            cursor.skipSpaces()
        }
        if cursor.hasPrefix(Self.annotationStart) {
            builder.addAnnotation(try readAnnotation(), toClassAt: index)
            cursor.skipSpaces()
        }
        if cursor.peek() == MermaidByte.openingBrace { try readClassBody(ofClassAt: index, identifier: name.identifier) }
        return index
    }

    /// `["Label"]`, the label quoted inside square brackets.
    private mutating func readBracketedLabel() throws(MermaidDiagramReadError) -> DiagramLabel {
        let openingLine = cursor.line
        cursor.advance()
        cursor.skipSpaces()
        guard cursor.peek() == MermaidByte.quotationMark else { throw .invalidSyntax(line: cursor.line, problem: .expectedQuotedText) }
        let text = try readQuotedText()
        cursor.skipSpaces()
        guard cursor.peek() == MermaidByte.closingBracket else {
            throw .invalidSyntax(line: openingLine, problem: .unclosedShape(closingText: "]"))
        }
        cursor.advance()
        return DiagramLabelDecoder.label(from: text, form: .plain)
    }

    /// `{` members, one per line, `}`. A `{` inside is an error, as in Mermaid; a line that starts with `%%` is a comment.
    private mutating func readClassBody(ofClassAt index: Int, identifier: String) throws(MermaidDiagramReadError) {
        let openingLine = cursor.line
        cursor.advance()
        while true {
            cursor.skipSpaces()
            if cursor.hasPrefix(Self.commentStart) { cursor.skipToEndOfLine() }
            let start = cursor.position
            while let byte = cursor.peek(), byte != MermaidByte.newline, byte != MermaidByte.openingBrace, byte != MermaidByte.closingBrace {
                cursor.advance()
            }
            builder.addMember(cursor.trimmedText(from: start, to: cursor.position), toClassAt: index)
            guard let byte = cursor.peek() else {
                throw .invalidSyntax(line: openingLine, problem: .unclosedClassBody(identifier: identifier))
            }
            if byte == MermaidByte.openingBrace { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
            cursor.advance()
            if byte == MermaidByte.closingBrace { return }
        }
    }

    /// `<<interface>> Name`.
    private mutating func readAnnotationStatement() throws(MermaidDiagramReadError) {
        let annotation = try readAnnotation()
        cursor.skipSpaces()
        guard let name = try ClassDiagramNameSyntax.read(&cursor) else { throw .invalidSyntax(line: cursor.line, problem: .expectedName) }
        builder.addAnnotation(annotation, toClassAt: try builder.classIndex(for: name))
    }

    /// `<<text>>` on one line: the text, trimmed.
    private mutating func readAnnotation() throws(MermaidDiagramReadError) -> String {
        let line = cursor.line
        cursor.advance(by: Self.annotationStart.count)
        let start = cursor.position
        while !cursor.isAtEnd, !cursor.hasPrefix(Self.annotationEnd), cursor.peek() != MermaidByte.newline { cursor.advance() }
        guard cursor.hasPrefix(Self.annotationEnd) else { throw .invalidSyntax(line: line, problem: .unclosedAnnotation) }
        let annotation = cursor.trimmedText(from: start, to: cursor.position)
        cursor.advance(by: Self.annotationEnd.count)
        guard !annotation.isEmpty else { throw .invalidSyntax(line: line, problem: .unexpectedText("<<>>")) }
        return annotation
    }

    // MARK: Members and relations

    /// A statement that starts with a class's name: `Name : member`, a relation, or the name alone, which Mermaid
    /// reads and adds nothing for.
    private mutating func readNameStatement() throws(MermaidDiagramReadError) {
        let line = cursor.line
        guard let name = try ClassDiagramNameSyntax.read(&cursor) else {
            throw .invalidSyntax(line: line, problem: .unexpectedText(cursor.excerpt()))
        }
        cursor.skipSpaces()
        if cursor.peek() == MermaidByte.colon, !cursor.hasPrefix(Self.styleSeparator) {
            cursor.advance()
            cursor.skipSpaces()
            builder.addMember(cursor.readRestOfLine(), toClassAt: try builder.classIndex(for: name))
            return
        }
        if isAtStatementEnd { return }
        try readRelation(from: name)
    }

    /// `A "1" <|-- "*" B : label`, from the first cardinality on.
    private mutating func readRelation(from source: ClassDiagramName) throws(MermaidDiagramReadError) {
        let sourceCardinality = try readCardinality()
        cursor.skipSpaces()
        guard let relationOperator = ClassDiagramRelationSyntax.readOperator(&cursor) else {
            let problem: MermaidSyntaxProblem = sourceCardinality != nil || ClassDiagramRelationSyntax.startsOperator(cursor)
                ? .expectedRelationLine : .unexpectedText(cursor.excerpt())
            throw .invalidSyntax(line: cursor.line, problem: problem)
        }
        cursor.skipSpaces()
        let targetCardinality = try readCardinality()
        cursor.skipSpaces()
        guard let target = try ClassDiagramNameSyntax.read(&cursor) else { throw .invalidSyntax(line: cursor.line, problem: .expectedName) }
        cursor.skipSpaces()
        var label: DiagramLabel?
        if cursor.peek() == MermaidByte.colon {
            cursor.advance()
            cursor.skipSpaces()
            let text = cursor.readRestOfLine()
            label = text.isEmpty ? nil : DiagramLabelDecoder.label(from: text, form: .markdown)
        }
        try builder.addRelation(from: source, to: target, operator: relationOperator, cardinalities: (sourceCardinality, targetCardinality), label: label)
    }

    /// `"1"` at the cursor: its text trimmed with entity codes read, nil when it is empty or there is none.
    private mutating func readCardinality() throws(MermaidDiagramReadError) -> String? {
        guard cursor.peek() == MermaidByte.quotationMark else { return nil }
        let text = ClassDiagramMemberSyntax.trimmed(DiagramLabelDecoder.decodingEntities(try readQuotedText()))
        return text.isEmpty ? nil : text
    }

    // MARK: Notes, namespaces, direction, accessibility

    /// `note "text"` or `note for Name "text"`.
    private mutating func readNote() throws(MermaidDiagramReadError) {
        cursor.skipSpaces()
        var classIdentifier: String?
        if cursor.hasPrefix(Self.forWord), let next = cursor.peek(Self.forWord.count), MermaidByte.isSpace(next) {
            cursor.advance(by: Self.forWord.count)
            cursor.skipSpaces()
            guard let name = try ClassDiagramNameSyntax.read(&cursor) else { throw .invalidSyntax(line: cursor.line, problem: .expectedName) }
            classIdentifier = name.identifier
            cursor.skipSpaces()
        }
        guard cursor.peek() == MermaidByte.quotationMark else { throw .invalidSyntax(line: cursor.line, problem: .expectedQuotedText) }
        try builder.addNote(DiagramLabelDecoder.label(from: try readQuotedText(), form: .markdown), forClassIdentifiedBy: classIdentifier)
    }

    /// `namespace Name["Title"] { … }` with the classes, notes and namespaces inside it, read with the builder's
    /// stack of open namespaces rather than by recursion, so that deep nesting cannot exhaust the thread's stack.
    private mutating func readNamespace() throws(MermaidDiagramReadError) {
        try openNamespace()
        while let innermost = builder.innermostOpenNamespaceIdentifier {
            cursor.skipWhitespace()
            guard let byte = cursor.peek() else { throw .invalidSyntax(line: cursor.line, problem: .unclosedNamespace(identifier: innermost)) }
            if byte == MermaidByte.closingBrace {
                cursor.advance()
                builder.closeNamespace()
                continue
            }
            if cursor.hasPrefix(Self.commentStart) {
                cursor.skipToEndOfLine()
                continue
            }
            let keyword = keywordAtCursor()
            cursor.advance(by: keyword?.utf8.count ?? 0)
            switch keyword ?? "" {
            case "class": builder.addToInnermostNamespace(classAt: try readClassStatement())
            case "note": try readNote()
            case "namespace": try openNamespace()
            default: throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
            }
            cursor.skipSpaces()
            if cursor.peek() != MermaidByte.closingBrace { try expectStatementEnd() }
        }
    }

    /// `Name["Title"] {` after `namespace`.
    private mutating func openNamespace() throws(MermaidDiagramReadError) {
        cursor.skipSpaces()
        guard let name = try ClassDiagramNameSyntax.read(&cursor) else { throw .invalidSyntax(line: cursor.line, problem: .expectedName) }
        cursor.skipSpaces()
        let title = cursor.peek() == MermaidByte.openingBracket ? try readBracketedLabel() : nil
        cursor.skipSpaces()
        guard cursor.peek() == MermaidByte.openingBrace else { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
        cursor.advance()
        builder.openNamespace(named: name.identifier, title: title)
    }

    /// `direction TB`, `BT`, `LR` or `RL`. Mermaid reads any other word after `direction` as part of a class's name
    /// that adds nothing, so the line is left without an error.
    private mutating func readDirection() {
        cursor.skipSpaces()
        let word = cursor.readWord() ?? ""
        if Self.directionKeywords.contains(word), let direction = FlowchartDirection(keyword: word) { builder.setDirection(direction) }
        cursor.skipToEndOfLine()
    }

    /// `accTitle: text`, to the end of the line.
    private mutating func readAccessibilityLine() -> String {
        cursor.skipSpaces()
        if cursor.peek() == MermaidByte.colon { cursor.advance() }
        cursor.skipSpaces()
        return DiagramLabelDecoder.decodingEntities(cursor.readRestOfLine())
    }

    /// `accDescr: text` or `accDescr { lines }`, the lines joined by spaces.
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

    // MARK: Text and statement ends

    /// The text between quotation marks at the cursor, which may hold anything but a quotation mark; moves past it.
    private mutating func readQuotedText() throws(MermaidDiagramReadError) -> String {
        let openingLine = cursor.line
        cursor.advance()
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.quotationMark { cursor.advance() }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedQuotation) }
        let text = cursor.text(from: start, to: cursor.position)
        cursor.advance()
        return text
    }

    /// Whether only spaces, then a line break, a comment or the end of the text, follow.
    private var isAtStatementEnd: Bool {
        var lookahead = cursor
        lookahead.skipSpaces()
        guard let byte = lookahead.peek() else { return true }
        return byte == MermaidByte.newline || byte == MermaidByte.carriageReturn || lookahead.hasPrefix(Self.commentStart)
    }

    /// A statement ends at a line break, a comment or the end of the text; anything else is an error.
    private mutating func expectStatementEnd() throws(MermaidDiagramReadError) {
        guard isAtStatementEnd else {
            cursor.skipSpaces()
            throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
        }
        cursor.skipToEndOfLine()
    }

    private static let keywords: Set<String> = ["class", "namespace", "note", "direction", "accTitle", "accDescr", "style", "classDef", "cssClass",
                                                "click", "link", "callback"]
    private static let directionKeywords: Set<String> = ["TB", "BT", "LR", "RL"]
    private static let commentStart = Array("%%".utf8)
    private static let annotationStart = Array("<<".utf8)
    private static let annotationEnd = Array(">>".utf8)
    private static let styleSeparator = Array(":::".utf8)
    private static let forWord = Array("for".utf8)
}
