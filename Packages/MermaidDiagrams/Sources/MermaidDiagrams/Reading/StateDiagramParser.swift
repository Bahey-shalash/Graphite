import Foundation

/// Reads a state diagram's statements after its `stateDiagram` or `stateDiagram-v2` keyword, as Mermaid's grammar
/// does: states named alone or with a text (`A : text`), transitions (`A --> B : text`), `[*]` starts and ends,
/// declarations (`state …`), notes, composite bodies (`{ … }`, divided by `--`), the direction, accessibility text,
/// and the statements that only style the diagram, which are counted and left. A statement may follow another on the
/// same line, as in Mermaid (`a --> b class a done`); a line break, or a semicolon, ends a text. `%%` and `#` start a
/// comment.
struct StateDiagramParser {
    private var cursor: MermaidTextCursor
    private var builder: StateDiagramBuilder

    /// Reads the state diagram whose keyword ends at the cursor.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> StateDiagram {
        var parser = StateDiagramParser(cursor: cursor, builder: StateDiagramBuilder(limits: limits))
        try parser.readStatements()
        return parser.builder.diagram
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            cursor.skipWhitespace()
            guard let byte = cursor.peek() else { break }
            if byte == MermaidByte.semicolon {
                cursor.advance()
            } else if cursor.hasPrefix(StateDiagramTextSyntax.commentStart) || byte == Self.numberSign {
                cursor.skipToEndOfLine()
            } else if try readKeywordStatement() {
                continue
            } else if try readBodyPunctuation() {
                continue
            } else {
                try readStateStatement()
            }
        }
        if let identifier = builder.innermostOpenCompositeIdentifier {
            throw .invalidSyntax(line: cursor.line, problem: .unclosedCompositeState(identifier: identifier))
        }
    }

    /// Reads a statement that starts with a keyword, and returns whether there was one.
    private mutating func readKeywordStatement() throws(MermaidDiagramReadError) -> Bool {
        let keywordLine = cursor.line
        guard let (keyword, afterKeyword) = keywordAtCursor() else { return false }
        cursor = afterKeyword
        switch keyword {
        case .state: try readDeclaration()
        case .note:
            if let note = try StateDiagramNoteSyntax.readNote(&cursor, keywordLine: keywordLine) {
                let stateIndex = try builder.stateIndex(for: note.state, isFirst: true)
                try builder.addNote(toStateAt: stateIndex, side: note.side, text: note.text)
            }
        case .direction: try readDirection()
        case .accessibilityTitle: builder.setAccessibilityTitle(readAccessibilityLine())
        case .accessibilityDescription: builder.setAccessibilityDescription(try readAccessibilityDescription())
        case .classDefinition, .classAssignment, .style, .click:
            cursor.skipToEndOfLine()
            builder.countUnappliedStatement()
        case .scale, .hide:
            // `scale 350 width` and `hide empty description` change nothing in Mermaid's drawing.
            cursor.skipToEndOfLine()
        }
        return true
    }

    /// The keyword at the cursor and the cursor past it, or nil. A word is a keyword only when a space or a line break
    /// follows it, so that `classes` and `notes --> B` name states; `accTitle` and `accDescr` need a colon (or, for
    /// `accDescr`, a brace), `direction` a word after it, and `hide` is only `hide empty description`.
    private func keywordAtCursor() -> (Keyword, MermaidTextCursor)? {
        var lookahead = cursor
        guard let word = lookahead.readWord(), let keyword = Self.keywordsByLowercasedWord[word.lowercased()] else { return nil }
        switch keyword {
        case .accessibilityTitle, .accessibilityDescription:
            var afterSpaces = lookahead
            afterSpaces.skipSpaces()
            guard let next = afterSpaces.peek(),
                  next == MermaidByte.colon || (next == MermaidByte.openingBrace && keyword == .accessibilityDescription) else { return nil }
        case .hide:
            guard cursor.hasCaseInsensitivePrefix(Self.hideEmptyDescription) else { return nil }
            lookahead = cursor
            lookahead.advance(by: Self.hideEmptyDescription.count)
            if let next = lookahead.peek(), MermaidByte.isIdentifierByte(next) { return nil }
        case .direction:
            var afterSpaces = lookahead
            afterSpaces.skipSpaces()
            guard afterSpaces.position > lookahead.position, let next = afterSpaces.peek(), MermaidByte.isLetter(next) else { return nil }
        case .state, .note, .classDefinition, .classAssignment, .style, .click, .scale:
            guard let next = lookahead.peek(), MermaidByte.isWhitespace(next) else { return nil }
        }
        return (keyword, lookahead)
    }

    /// `}`, which closes a composite's body, and `--`, which divides it into concurrent regions. Returns whether one
    /// was read.
    private mutating func readBodyPunctuation() throws(MermaidDiagramReadError) -> Bool {
        let line = cursor.line
        if cursor.peek() == MermaidByte.closingBrace {
            guard builder.closeBody() else { throw .invalidSyntax(line: line, problem: .closingBraceWithoutCompositeState) }
            cursor.advance()
            return true
        }
        guard cursor.hasPrefix(Self.regionDivider), !cursor.hasPrefix(Self.transitionArrow) else { return false }
        guard builder.startRegion() else { throw .invalidSyntax(line: line, problem: .unexpectedText(cursor.excerpt())) }
        cursor.advance(by: Self.regionDivider.count)
        return true
    }

    /// `A`, `A : text`, `A --> B` or `A --> B : text`, each state optionally followed by `:::class`.
    private mutating func readStateStatement() throws(MermaidDiagramReadError) {
        let line = cursor.line
        guard cursor.peek() != MermaidByte.quotationMark, let first = readReference() else {
            throw .invalidSyntax(line: line, problem: .unexpectedText(cursor.excerpt()))
        }
        cursor.skipSpaces()
        guard cursor.hasPrefix(Self.transitionArrow) else {
            let stateIndex = try builder.stateIndex(for: first, isFirst: true)
            if let description = StateDiagramTextSyntax.readColonText(&cursor) { builder.addDescriptions([description], toStateAt: stateIndex) }
            return
        }
        cursor.advance(by: Self.transitionArrow.count)
        cursor.skipSpaces()
        guard let second = readReference() else { throw .invalidSyntax(line: cursor.line, problem: .expectedState) }
        let sourceIndex = try builder.stateIndex(for: first, isFirst: true)
        let targetIndex = try builder.stateIndex(for: second, isFirst: false)
        cursor.skipSpaces()
        try builder.addTransition(from: sourceIndex, to: targetIndex, label: StateDiagramTextSyntax.readColonText(&cursor))
    }

    /// A state reference and any `:::class` after it, which is counted and not applied.
    private mutating func readReference() -> StateDiagramStateReference? {
        guard let reference = StateDiagramTextSyntax.readReference(&cursor) else { return nil }
        while cursor.hasPrefix(Self.classMarker) {
            cursor.advance(by: Self.classMarker.count)
            _ = StateDiagramTextSyntax.readIdentifier(&cursor)
            builder.countUnappliedStatement()
        }
        return reference
    }

    /// What follows `state`: a stereotype, a description, a composite's body, or nothing.
    private mutating func readDeclaration() throws(MermaidDiagramReadError) {
        switch try StateDiagramDeclarationSyntax.readDeclaration(&cursor) {
        case .stereotyped(let identifier, let kind):
            _ = try builder.stateIndex(for: .named(identifier), isFirst: true, kind: kind)
        case .described(let identifier, let descriptions, let opensBody):
            let stateIndex = try builder.stateIndex(for: .named(identifier), isFirst: true)
            builder.addDescriptions(descriptions, toStateAt: stateIndex)
            if opensBody { builder.openBody(ofStateAt: stateIndex) }
        case .composite(let identifier):
            builder.openBody(ofStateAt: try builder.stateIndex(for: .named(identifier), isFirst: true))
        case .nothing:
            break
        }
    }

    /// `direction TB`, `BT`, `LR` or `RL`, for the body it is written in or the whole diagram.
    private mutating func readDirection() throws(MermaidDiagramReadError) {
        cursor.skipSpaces()
        let line = cursor.line
        let word = cursor.readWord() ?? ""
        guard let direction = FlowchartDirection(keyword: word) else { throw .invalidSyntax(line: line, problem: .unknownDirection(word)) }
        builder.setDirection(direction)
        cursor.skipToEndOfLine()
    }

    /// `accTitle: text`, to the end of the line.
    private mutating func readAccessibilityLine() -> String {
        cursor.skipSpaces()
        if cursor.peek() == MermaidByte.colon { cursor.advance() }
        cursor.skipSpaces()
        return DiagramLabelDecoder.decodingEntities(cursor.readRestOfLine())
    }

    /// `accDescr: text` or `accDescr { lines }`, whose lines are kept without their indentation and blank lines.
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
        let lines = description.split(separator: "\n").map { line in line.trimmingCharacters(in: .whitespaces) }
        return DiagramLabelDecoder.decodingEntities(lines.filter { line in !line.isEmpty }.joined(separator: "\n"))
    }

    private enum Keyword {
        case state, note, direction, accessibilityTitle, accessibilityDescription, classDefinition, classAssignment, style, click, scale, hide
    }

    /// The keywords by their lowercased words: Mermaid reads them in any case. `hide` is only `hide empty description`.
    private static let keywordsByLowercasedWord: [String: Keyword] = [
        "state": .state, "note": .note, "direction": .direction, "acctitle": .accessibilityTitle, "accdescr": .accessibilityDescription,
        "classdef": .classDefinition, "class": .classAssignment, "style": .style, "click": .click, "scale": .scale, "hide": .hide,
    ]
    private static let hideEmptyDescription = Array("hide empty description".utf8)
    private static let transitionArrow = Array("-->".utf8)
    private static let regionDivider = Array("--".utf8)
    private static let classMarker = Array(":::".utf8)
    private static let numberSign = UInt8(ascii: "#")
}
