/// Cuts a quadrant chart's statements into tokens as Mermaid's quadrant grammar does (Pele's port of its lexer):
/// `%%` comments anywhere, `title` and the rest of its line, accessibility statements, the keywords `x-axis`,
/// `y-axis`, `quadrant-1` to `quadrant-4` and the arrow `-->` with the spaces around them, `classDef`, text in
/// quotation marks or Markdown quotation marks, `:::` and a class's name, a point's `: [x, y]`
/// (`QuadrantChartPointSyntax`), and otherwise runs of letters, digits and characters beyond ASCII, and single
/// characters. Keywords are read without regard to case. A character no rule takes is an error, as in Mermaid.
struct QuadrantChartLexer {
    private var cursor: MermaidTextCursor
    private var tokens: [QuadrantChartToken] = []

    /// The tokens of the statements after the cursor, which is just past the `quadrantChart` keyword.
    static func tokens(after cursor: MermaidTextCursor) throws(MermaidDiagramReadError) -> [QuadrantChartToken] {
        var lexer = QuadrantChartLexer(cursor: cursor)
        while let byte = lexer.cursor.peek() { try lexer.readToken(startingWith: byte) }
        return lexer.tokens
    }

    private init(cursor: MermaidTextCursor) {
        self.cursor = cursor
    }

    private mutating func readToken(startingWith byte: UInt8) throws(MermaidDiagramReadError) {
        let start = cursor
        if skipComment(startingWith: byte) { return }
        if byte == MermaidByte.newline || byte == MermaidByte.carriageReturn {
            while let next = cursor.peek(), next == MermaidByte.newline || next == MermaidByte.carriageReturn { cursor.advance() }
            return append(.lineBreak, from: start)
        }
        if let title = readTitle() { return append(.title, content: .text(title), from: start) }
        if let statement = try MermaidAccessibilityStatement.read(&cursor) { return append(.accessibility, content: .accessibility(statement), from: start) }
        if let keyword = readKeywordWithSpaces() { return append(keyword, from: start) }
        if isAtWord(Self.classDefinitionKeyword) {
            cursor.advance(by: Self.classDefinitionKeyword.count)
            return append(.classDefinition, from: start)
        }
        if byte == MermaidByte.quotationMark { return try readString(from: start) }
        if cursor.hasPrefix(Self.classMarker) { return try readClassName(from: start) }
        if let coordinates = try QuadrantChartPointSyntax.readPoint(&cursor) { return append(.point, content: coordinates, from: start) }
        try readRunOrCharacter(startingWith: byte, from: start)
    }

    private mutating func append(_ kind: QuadrantChartTokenKind, content: QuadrantChartTokenContent = .none, from start: MermaidTextCursor) {
        tokens.append(QuadrantChartToken(kind: kind, content: content, start: start.position, end: cursor.position, line: start.line))
    }

    /// `%%` and the rest of its line, or a character other than `}` followed by `%%` and the rest of the line: Mermaid's
    /// second comment rule takes that character with it, a line break included.
    private mutating func skipComment(startingWith byte: UInt8) -> Bool {
        if byte == MermaidByte.percent, cursor.peek(1) == MermaidByte.percent {
            cursor.skipToEndOfLine()
            return true
        }
        guard byte != MermaidByte.closingBrace, cursor.peek(1) == MermaidByte.percent, cursor.peek(2) == MermaidByte.percent else { return false }
        cursor.advance(by: 3)
        cursor.skipToEndOfLine()
        return true
    }

    /// `title` with no letter, digit or underscore after it, then the rest of its line, which is the title as written.
    private mutating func readTitle() -> String? {
        guard isAtWord(Self.titleKeyword) else { return nil }
        cursor.advance(by: Self.titleKeyword.count)
        let start = cursor.position
        cursor.skipToEndOfLine()
        return cursor.text(from: start, to: cursor.position)
    }

    /// After any spaces: `x-axis`, `y-axis`, `quadrant-1` to `quadrant-4`, `quadrantChart`, or two or more hyphens and
    /// `>`, each taking the spaces after it too. Nil, with the cursor where it was, when none is there.
    private mutating func readKeywordWithSpaces() -> QuadrantChartTokenKind? {
        guard let byte = cursor.peek(), Self.canStartKeyword(byte) else { return nil }
        var lookahead = cursor
        while lookahead.peek() == MermaidByte.space { lookahead.advance() }
        guard let (kind, length) = Self.keyword(at: lookahead) else { return nil }
        lookahead.advance(by: length)
        while lookahead.peek() == MermaidByte.space { lookahead.advance() }
        cursor = lookahead
        return kind
    }

    /// Whether `byte` may start a keyword with the spaces before it: a space, `x`, `y`, `-` or `q` in either case.
    private static func canStartKeyword(_ byte: UInt8) -> Bool {
        switch MermaidByte.lowercased(byte) {
        case MermaidByte.space, UInt8(ascii: "x"), UInt8(ascii: "y"), MermaidByte.hyphen, UInt8(ascii: "q"): true
        default: false
        }
    }

    /// The keyword or arrow at `lookahead` and its length in bytes, or nil.
    private static func keyword(at lookahead: MermaidTextCursor) -> (QuadrantChartTokenKind, Int)? {
        if lookahead.hasCaseInsensitivePrefix(xAxisKeyword) { return (.xAxis, xAxisKeyword.count) }
        if lookahead.hasCaseInsensitivePrefix(yAxisKeyword) { return (.yAxis, yAxisKeyword.count) }
        if lookahead.peek() == MermaidByte.hyphen {
            var hyphenCount = 0
            while lookahead.peek(hyphenCount) == MermaidByte.hyphen { hyphenCount += 1 }
            return hyphenCount >= 2 && lookahead.peek(hyphenCount) == MermaidByte.greaterThan ? (.axisArrow, hyphenCount + 1) : nil
        }
        guard lookahead.hasCaseInsensitivePrefix(quadrantKeyword) else { return nil }
        let quadrantLength = quadrantKeyword.count
        if lookahead.peek(quadrantLength) == MermaidByte.hyphen, let digit = lookahead.peek(quadrantLength + 1),
           (firstQuadrantDigit...lastQuadrantDigit).contains(digit) {
            return (QuadrantChartTokenKind.quadrants[Int(digit - firstQuadrantDigit)], quadrantLength + 2)
        }
        var afterQuadrant = lookahead
        afterQuadrant.advance(by: quadrantLength)
        return afterQuadrant.hasCaseInsensitivePrefix(chartKeyword) ? (.chartKeyword, quadrantLength + chartKeyword.count) : nil
    }

    /// Text in quotation marks, which may span lines, or a Markdown string between "` and `". Empty text makes no
    /// token, as in Mermaid's grammar; a quotation without its end is an error.
    private mutating func readString(from start: MermaidTextCursor) throws(MermaidDiagramReadError) {
        let isMarkdown = cursor.peek(1) == MermaidByte.graveAccent
        cursor.advance(by: isMarkdown ? 2 : 1)
        let textStart = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.quotationMark, !(isMarkdown && byte == MermaidByte.graveAccent) { cursor.advance() }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: start.line, problem: .unclosedQuotation) }
        let text = cursor.text(from: textStart, to: cursor.position)
        if isMarkdown {
            guard cursor.peek() == MermaidByte.graveAccent, cursor.peek(1) == MermaidByte.quotationMark else {
                throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
            }
            cursor.advance()
        }
        cursor.advance()
        guard !text.isEmpty else { return }
        append(isMarkdown ? .markdownString : .string, content: .text(text), from: start)
    }

    /// `:::` and a class's name: letters, digits and underscores, at least one.
    private mutating func readClassName(from start: MermaidTextCursor) throws(MermaidDiagramReadError) {
        cursor.advance(by: Self.classMarker.count)
        let nameStart = cursor.position
        while let byte = cursor.peek(), Self.isWordByte(byte) { cursor.advance() }
        guard cursor.position > nameStart else { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
        append(.className, content: .text(cursor.text(from: nameStart, to: cursor.position)), from: start)
    }

    /// A run of letters, of digits or of bytes beyond ASCII, or one character that makes a token alone.
    private mutating func readRunOrCharacter(startingWith byte: UInt8, from start: MermaidTextCursor) throws(MermaidDiagramReadError) {
        if MermaidByte.isLetter(byte) {
            skipRun(of: MermaidByte.isLetter)
            return append(.letters, from: start)
        }
        if byte >= Self.firstByteBeyondASCII {
            skipRun { next in next >= Self.firstByteBeyondASCII }
            return append(.otherCharacters, from: start)
        }
        if MermaidByte.isDigit(byte) {
            skipRun(of: MermaidByte.isDigit)
            return append(.digits, from: start)
        }
        guard let kind = Self.singleCharacters[byte] else { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
        cursor.advance()
        append(kind, from: start)
    }

    private mutating func skipRun(of isInRun: (UInt8) -> Bool) {
        while let byte = cursor.peek(), isInRun(byte) { cursor.advance() }
    }

    /// Whether `word` (lowercase) is at the cursor in any case, with no letter, digit or underscore after it.
    private func isAtWord(_ word: [UInt8]) -> Bool {
        guard cursor.hasCaseInsensitivePrefix(word) else { return false }
        return !(cursor.peek(word.count).map(Self.isWordByte) ?? false)
    }

    static func isWordByte(_ byte: UInt8) -> Bool {
        MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
    }

    /// The characters that make a token alone, and the token each makes.
    private static let singleCharacters: [UInt8: QuadrantChartTokenKind] = {
        var kinds: [UInt8: QuadrantChartTokenKind] = [
            MermaidByte.colon: .colon, MermaidByte.comma: .comma, MermaidByte.hyphen: .hyphen, numberSign: .numberSign,
            MermaidByte.semicolon: .semicolon, MermaidByte.ampersand: .ampersand, asterisk: .asterisk,
        ]
        for character in "+=_.!$%'`?\\/".utf8 { kinds[character] = .otherPunctuation }
        for space in [MermaidByte.space, MermaidByte.tab, verticalTab, formFeed] { kinds[space] = .space }
        return kinds
    }()

    private static let titleKeyword = Array("title".utf8)
    private static let classDefinitionKeyword = Array("classdef".utf8)
    private static let xAxisKeyword = Array("x-axis".utf8)
    private static let yAxisKeyword = Array("y-axis".utf8)
    private static let quadrantKeyword = Array("quadrant".utf8)
    private static let chartKeyword = Array("chart".utf8)
    private static let classMarker = Array(":::".utf8)
    private static let firstQuadrantDigit = UInt8(ascii: "1")
    private static let lastQuadrantDigit = UInt8(ascii: "4")
    private static let firstByteBeyondASCII: UInt8 = 0x80
    private static let numberSign = UInt8(ascii: "#")
    private static let asterisk = UInt8(ascii: "*")
    private static let verticalTab: UInt8 = 0x0B
    private static let formFeed: UInt8 = 0x0C
}
