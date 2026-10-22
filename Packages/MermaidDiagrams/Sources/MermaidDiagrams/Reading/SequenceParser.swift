/// Reads a sequence diagram's statements after its `sequenceDiagram` keyword, as Mermaid's sequence grammar does:
/// participant declarations, messages, notes, activations, blocks, `autonumber`, `title` and accessibility text.
/// Keywords are read in any case; statements end at a line break or a semicolon; `%%` and `#` start a comment.
struct SequenceParser {
    private var cursor: MermaidTextCursor
    private var builder: SequenceDiagramBuilder

    /// Reads the sequence diagram whose keyword ends at the cursor.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> SequenceDiagram {
        var parser = SequenceParser(cursor: cursor, builder: SequenceDiagramBuilder(limits: limits))
        try parser.readStatements()
        return try parser.builder.finished()
    }

    /// The words that start a statement, lowercased.
    private enum Keyword: String {
        case participant, actor, create, destroy, box, loop, rect, opt, alt, `else`, par, parOver = "par_over", and, critical, option, `break`, end
        case note, activate, deactivate, autonumber, title, accessibilityTitle = "acctitle", accessibilityDescription = "accdescr"
        case link, links, properties, details
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            cursor.skipWhitespace()
            if cursor.peek() == MermaidByte.semicolon {
                cursor.advance()
                continue
            }
            if cursor.isAtEnd { return }
            if isAtComment() {
                cursor.skipToEndOfLine()
                continue
            }
            try readStatement()
            try expectStatementEnd()
        }
    }

    private mutating func readStatement() throws(MermaidDiagramReadError) {
        let line = cursor.line
        var lookahead = cursor
        let keyword = Self.readKeyword(&lookahead)
        if builder.isInsideBox {
            guard let keyword, [.participant, .actor, .destroy, .end].contains(keyword) else {
                throw .invalidSyntax(line: line, problem: .unexpectedText(cursor.excerpt()))
            }
        }
        guard let keyword, Self.startsStatement(keyword, after: lookahead) else {
            try readMessage()
            return
        }
        cursor = lookahead
        try readKeywordStatement(keyword, line: line)
    }

    private mutating func readKeywordStatement(_ keyword: Keyword, line: Int) throws(MermaidDiagramReadError) {
        switch keyword {
        case .participant, .actor: try readDeclaration(kind: keyword == .actor ? .actor : .participant)
        case .create: try readCreation(line: line)
        case .destroy:
            builder.noteStatementNotLaidOut(.participantDestruction)
            _ = try SequenceParticipantSyntax.readName(&cursor)
        case .box:
            _ = SequenceTextSyntax.readText(&cursor)
            builder.openBox(line: line)
        case .loop: try readBlockOpening(.loop, keyword: keyword, line: line)
        case .opt: try readBlockOpening(.optional, keyword: keyword, line: line)
        case .alt: try readBlockOpening(.alternatives, keyword: keyword, line: line)
        case .par, .parOver: try readBlockOpening(.parallel, keyword: keyword, line: line)
        case .critical: try readBlockOpening(.critical, keyword: keyword, line: line)
        case .break: try readBlockOpening(.break, keyword: keyword, line: line)
        case .rect:
            let color = SequenceHighlightColorSyntax.color(from: SequenceTextSyntax.readText(&cursor).text)
            try builder.openBlock(.highlight(color), keyword: keyword.rawValue, label: DiagramLabel(lines: []), line: line)
        case .else, .and, .option: try builder.addSection(keyword: keyword.rawValue, label: SequenceTextSyntax.readText(&cursor).label, line: line)
        case .end: try builder.closeBlock(line: line)
        case .note: try readNote(line: line)
        case .activate: try builder.activate(try SequenceParticipantSyntax.readName(&cursor))
        case .deactivate: try builder.deactivate(try SequenceParticipantSyntax.readName(&cursor), line: line)
        case .autonumber: try readNumbering()
        case .title: readTitle()
        case .accessibilityTitle: builder.setAccessibilityTitle(readAccessibilityLine())
        case .accessibilityDescription: builder.setAccessibilityDescription(try readAccessibilityDescription())
        case .link, .links, .properties, .details:
            builder.noteStatementNotLaidOut(.participantMenu)
            skipStatement()
        }
    }

    // MARK: Participants and messages

    /// `participant A`, `participant A as Alice`, `actor A@{ … }`.
    private mutating func readDeclaration(kind: SequenceParticipantKind) throws(MermaidDiagramReadError) {
        let declaration = try SequenceParticipantSyntax.readDeclaration(&cursor)
        if declaration.hasAttributes { builder.noteStatementNotLaidOut(.participantAttributes) }
        try builder.declareParticipant(declaration.identifier, kind: kind, alias: declaration.alias?.label)
    }

    /// `create participant A` or `create actor A`.
    private mutating func readCreation(line: Int) throws(MermaidDiagramReadError) {
        cursor.skipSpaces()
        var lookahead = cursor
        guard let keyword = Self.readKeyword(&lookahead), keyword == .participant || keyword == .actor else {
            throw .invalidSyntax(line: line, problem: .unexpectedText(cursor.excerpt()))
        }
        cursor = lookahead
        builder.noteStatementNotLaidOut(.participantCreation)
        try readDeclaration(kind: keyword == .actor ? .actor : .participant)
    }

    /// `A->>B: text`, with `+` or `-` before the target to start the target's activation or end the source's, and
    /// `()` at either end for a central connection.
    private mutating func readMessage() throws(MermaidDiagramReadError) {
        let line = cursor.line
        guard let sourceName = SequenceTextSyntax.readParticipantName(&cursor) else {
            throw .invalidSyntax(line: line, problem: .unexpectedText(cursor.excerpt()))
        }
        cursor.skipSpaces()
        let hasSourceConnection = readCentralConnection()
        guard let written = SequenceArrowSyntax.readOperator(&cursor) else {
            let isAtStatementEnd = cursor.peek().map(MermaidByte.endsStatement) ?? true
            throw .invalidSyntax(line: cursor.line, problem: isAtStatementEnd ? .sequence(.expectedArrow) : .unexpectedText(cursor.excerpt()))
        }
        cursor.skipSpaces()
        let mark = cursor.peek()
        let hasTargetConnection = readCentralConnection()
        let activatesTarget = !hasTargetConnection && !hasSourceConnection && mark == SequenceTextSyntax.plusSign
        let deactivatesSource = !hasTargetConnection && !hasSourceConnection && mark == MermaidByte.hyphen
        if activatesTarget || deactivatesSource { cursor.advance() }
        cursor.skipSpaces()
        guard let targetName = SequenceTextSyntax.readParticipantName(&cursor) else {
            throw .invalidSyntax(line: cursor.line, problem: .sequence(.expectedParticipant))
        }
        guard let text = SequenceTextSyntax.readColonText(&cursor) else { throw .invalidSyntax(line: cursor.line, problem: .sequence(.expectedText)) }
        if hasSourceConnection || hasTargetConnection { builder.noteStatementNotLaidOut(.centralConnection) }
        let sourceIndex = try builder.participantIndex(for: sourceName)
        let targetIndex = try builder.participantIndex(for: targetName)
        switch written {
        case .arrow(let arrow):
            try builder.addMessage(SequenceMessage(sourceIndex: sourceIndex, targetIndex: targetIndex, arrow: arrow, text: text.label, wrapsText: text.wraps))
        case .halfArrow:
            builder.noteStatementNotLaidOut(.halfArrow)
        }
        if activatesTarget { try builder.activate(targetName) }
        if deactivatesSource { try builder.deactivate(sourceName, line: line) }
    }

    /// Moves past `()`, and returns whether it was there.
    private mutating func readCentralConnection() -> Bool {
        guard cursor.peek() == SequenceTextSyntax.openingParenthesis, cursor.peek(1) == SequenceTextSyntax.closingParenthesis else { return false }
        cursor.advance(by: 2)
        cursor.skipSpaces()
        return true
    }

    /// `Note left of A: text`, `Note right of A: text`, `Note over A: text` or `Note over A,B: text`.
    private mutating func readNote(line: Int) throws(MermaidDiagramReadError) {
        cursor.skipSpaces()
        enum Side { case left, right, over }
        let side: Side
        if consumeWords("left of") {
            side = .left
        } else if consumeWords("right of") {
            side = .right
        } else if consumeWords("over") {
            side = .over
        } else {
            throw .invalidSyntax(line: line, problem: .sequence(.expectedNotePlacement))
        }
        let firstIndex = try readNoteParticipant()
        var lastIndex = firstIndex
        if side == .over {
            cursor.skipSpaces()
            if cursor.peek() == MermaidByte.comma {
                cursor.advance()
                lastIndex = try readNoteParticipant()
            }
        }
        guard let text = SequenceTextSyntax.readColonText(&cursor) else { throw .invalidSyntax(line: cursor.line, problem: .sequence(.expectedText)) }
        let placement: SequenceNotePlacement = switch side {
        case .left: .leftOf(participantIndex: firstIndex)
        case .right: .rightOf(participantIndex: firstIndex)
        case .over: .over(firstParticipantIndex: firstIndex, lastParticipantIndex: lastIndex)
        }
        try builder.addNote(SequenceNote(placement: placement, text: text.label, wrapsText: text.wraps))
    }

    private mutating func readNoteParticipant() throws(MermaidDiagramReadError) -> Int {
        cursor.skipSpaces()
        guard let name = SequenceTextSyntax.readParticipantName(&cursor) else {
            throw .invalidSyntax(line: cursor.line, problem: .sequence(.expectedParticipant))
        }
        return try builder.participantIndex(for: name)
    }

    // MARK: Blocks, numbering and titles

    /// `loop text`, `alt text`, `opt text`, `par text`, `par_over text`, `critical text` or `break text`.
    private mutating func readBlockOpening(_ kind: SequenceBlockKind, keyword: Keyword, line: Int) throws(MermaidDiagramReadError) {
        try builder.openBlock(kind, keyword: keyword.rawValue, label: SequenceTextSyntax.readText(&cursor).label, line: line)
    }

    /// `autonumber`, `autonumber off`, `autonumber 10` or `autonumber 10 5`; numbers have at most two decimals.
    private mutating func readNumbering() throws(MermaidDiagramReadError) {
        cursor.skipSpaces()
        if consumeWords("off") {
            try builder.addNumbering(SequenceNumbering(firstNumberInHundredths: nil, stepInHundredths: nil, isVisible: false))
            return
        }
        let first = try readNumberInHundredths()
        cursor.skipSpaces()
        let step = first == nil ? nil : try readNumberInHundredths()
        try builder.addNumbering(SequenceNumbering(firstNumberInHundredths: first, stepInHundredths: first == nil ? nil : step ?? 100, isVisible: true))
    }

    /// `12`, `10.5`, `.25`: digits with at most two decimals, followed by a space, a line break or the end. Nil when
    /// no digit or point is at the cursor.
    private mutating func readNumberInHundredths() throws(MermaidDiagramReadError) -> Int? {
        guard let first = cursor.peek(), MermaidByte.isDigit(first) || first == MermaidByte.period else { return nil }
        let start = cursor.position
        var whole = 0
        var wholeDigitCount = 0
        while let byte = cursor.peek(), MermaidByte.isDigit(byte), wholeDigitCount < Self.maximumWholeDigitCount {
            whole = whole * 10 + Int(byte - UInt8(ascii: "0"))
            wholeDigitCount += 1
            cursor.advance()
        }
        var hundredths = whole * 100
        if cursor.peek() == MermaidByte.period, let tenths = cursor.peek(1), MermaidByte.isDigit(tenths) {
            cursor.advance(by: 2)
            hundredths += Int(tenths - UInt8(ascii: "0")) * 10
            if let digit = cursor.peek(), MermaidByte.isDigit(digit) {
                hundredths += Int(digit - UInt8(ascii: "0"))
                cursor.advance()
            }
        }
        let hasDigits = wholeDigitCount > 0 || cursor.position > start + 1
        guard hasDigits, cursor.peek().map(MermaidByte.isWhitespace) ?? true else {
            var end = cursor
            end.skipToEndOfLine()
            throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.trimmedText(from: start, to: end.position)))
        }
        return hundredths
    }

    /// `title text` or `title: text`, to a `#`, a semicolon or the end of the line.
    private mutating func readTitle() {
        if cursor.peek() == MermaidByte.colon { cursor.advance() }
        let title = SequenceTextSyntax.readText(&cursor).text
        builder.setTitle(DiagramLabelDecoder.decodingEntities(title))
    }

    /// `accTitle: text` or `accDescr: text`, to the end of the line.
    private mutating func readAccessibilityLine() -> String {
        cursor.skipSpaces()
        if cursor.peek() == MermaidByte.colon { cursor.advance() }
        cursor.skipSpaces()
        return DiagramLabelDecoder.decodingEntities(cursor.readRestOfLine())
    }

    /// `accDescr: text` or `accDescr { lines }`, whose lines keep their breaks without the spaces that start them.
    private mutating func readAccessibilityDescription() throws(MermaidDiagramReadError) -> String {
        cursor.skipSpaces()
        guard cursor.peek() == MermaidByte.openingBrace else { return readAccessibilityLine() }
        let openingLine = cursor.line
        cursor.advance()
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.closingBrace { cursor.advance() }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedAccessibilityDescription) }
        let lines = cursor.trimmedText(from: start, to: cursor.position).split(separator: "\n", omittingEmptySubsequences: false)
        cursor.advance()
        return lines.map { line in DiagramLabelDecoder.decodingEntities(String(line.drop(while: \.isWhitespace))) }.joined(separator: "\n")
    }

    // MARK: Keywords and statement ends

    /// The keyword at the cursor, read in any case up to the first byte that is not a letter or an underscore, and
    /// moves past it; nil when the word is no keyword or a digit follows it.
    private static func readKeyword(_ cursor: inout MermaidTextCursor) -> Keyword? {
        let start = cursor.position
        while let byte = cursor.peek(), MermaidByte.isLetter(byte) || byte == MermaidByte.underscore { cursor.advance() }
        guard cursor.position > start, cursor.peek().map(MermaidByte.isDigit) != true else { return nil }
        return Keyword(rawValue: cursor.text(from: start, to: cursor.position).lowercased())
    }

    /// Whether a keyword starts a statement where it stands. `title` needs text after it, and `link`, `links`,
    /// `properties` and `details` need spaces and a name, as Mermaid's lexer requires; otherwise the word is a name.
    private static func startsStatement(_ keyword: Keyword, after lookahead: MermaidTextCursor) -> Bool {
        switch keyword {
        case .title:
            var afterColon = lookahead
            if afterColon.peek() == MermaidByte.colon { afterColon.advance() }
            guard let space = afterColon.peek(), MermaidByte.isSpace(space), let text = afterColon.peek(1) else { return false }
            return !MermaidByte.endsStatement(text) && text != SequenceTextSyntax.numberSign
        case .link, .links, .properties, .details:
            guard let space = lookahead.peek(), MermaidByte.isSpace(space) else { return false }
            var name = lookahead
            name.skipSpaces()
            guard let first = name.peek() else { return false }
            return !MermaidByte.isWhitespace(first) && !"/\\+()<>:,;-".utf8.contains(first)
        case .participant, .actor, .create, .destroy, .box, .loop, .rect, .opt, .alt, .else, .par, .parOver, .and, .critical, .option, .break,
             .end, .note, .activate, .deactivate, .autonumber, .accessibilityTitle, .accessibilityDescription:
            return true
        }
    }

    /// Moves past `words` (lowercase, one space between words) in any case when no letter, digit or underscore
    /// follows them, and returns whether they were there.
    private mutating func consumeWords(_ words: String) -> Bool {
        let bytes = Array(words.utf8)
        guard cursor.hasCaseInsensitivePrefix(bytes) else { return false }
        if let following = cursor.peek(bytes.count), MermaidByte.isIdentifierByte(following), following < 0x80 { return false }
        cursor.advance(by: bytes.count)
        return true
    }

    private func isAtComment() -> Bool {
        cursor.hasPrefix(Self.commentStart) || cursor.peek() == SequenceTextSyntax.numberSign
    }

    /// Moves to the end of a statement that is not read: the next line break or semicolon.
    private mutating func skipStatement() {
        while let byte = cursor.peek(), !MermaidByte.endsStatement(byte) || byte == MermaidByte.carriageReturn { cursor.advance() }
    }

    /// A statement ends at a line break, a semicolon, a comment or the end of the text; anything else is an error.
    private mutating func expectStatementEnd() throws(MermaidDiagramReadError) {
        cursor.skipSpaces()
        guard let byte = cursor.peek(), !MermaidByte.endsStatement(byte) else { return }
        if isAtComment() {
            cursor.skipToEndOfLine()
            return
        }
        throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
    }

    private static let commentStart = Array("%%".utf8)
    /// More whole digits than this in an `autonumber` number is not a number the counting can hold.
    private static let maximumWholeDigitCount = 12
}
