import Foundation

/// Reads a user journey's statements after its `journey` keyword, as Mermaid's journey grammar does: `title …`,
/// `section …`, `accTitle` and `accDescr`, and tasks (`Make tea: 5: Me, Cat`), whose text runs to a colon and whose
/// score and actors run from there to the end of the line. A `#`, a `;` or a line break ends any text, and a colon also
/// ends a task's text or a section's; a `;` or a colon where a statement would start is an error. `title` and
/// `section` are keywords only when a space or a line break follows them, so either alone on its line takes the next
/// line as its text, as in Mermaid. Comments (`%%`, a `%` that opens no directive, and `#` where a statement would
/// start) and spaces between statements are skipped. Keywords are read without regard to case.
struct UserJourneyParser {
    private var cursor: MermaidTextCursor
    private var builder: UserJourneyDiagramBuilder

    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> UserJourneyDiagram {
        var parser = UserJourneyParser(cursor: cursor, builder: UserJourneyDiagramBuilder(limits: limits))
        try parser.readStatements()
        return parser.builder.diagram
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            skipSpacesAndComments()
            guard let byte = cursor.peek() else { return }
            if byte == MermaidByte.newline {
                cursor.advance()
            } else if isAtJourneyKeyword() || byte == MermaidByte.colon || byte == MermaidByte.semicolon {
                throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
            } else if let title = readKeywordText(Self.titleKeyword, endsAtColon: false) {
                builder.setTitle(title)
            } else if let statement = try MermaidAccessibilityStatement.read(&cursor) {
                builder.apply(statement)
            } else if let section = readKeywordText(Self.sectionKeyword, endsAtColon: true) {
                try builder.addSection(Self.label(section))
            } else {
                try readTask()
            }
        }
    }

    /// Skips spaces, tabs and carriage returns, `%%` comments, a `%` that opens no directive, and `#` comments, up
    /// to a line break, which ends a statement. A character just before `%%` goes with the comment, as in Mermaid's
    /// grammar, so a line break before a comment line goes with it.
    private mutating func skipSpacesAndComments() {
        while let byte = cursor.peek() {
            if byte == MermaidByte.percent, cursor.peek(1) != MermaidByte.openingBrace {
                cursor.skipToEndOfLine()
            } else if byte != MermaidByte.closingBrace, cursor.peek(1) == MermaidByte.percent, cursor.peek(2) == MermaidByte.percent {
                cursor.advance(by: 3)
                cursor.skipToEndOfLine()
            } else if byte == MermaidByte.newline {
                return
            } else if Self.isSpace(byte) {
                cursor.advance()
            } else if byte == Self.numberSign {
                cursor.skipToEndOfLine()
            } else {
                return
            }
        }
    }

    /// `journey` again, in any case, with no letter, digit or underscore after it: Mermaid's grammar reads it as its
    /// keyword, which no statement starts with.
    private func isAtJourneyKeyword() -> Bool {
        guard cursor.hasCaseInsensitivePrefix(Self.journeyKeyword) else { return false }
        guard let next = cursor.peek(Self.journeyKeyword.count) else { return true }
        return !(MermaidByte.isLetter(next) || MermaidByte.isDigit(next) || next == MermaidByte.underscore)
    }

    /// `keyword` (lowercase) in any case, a space or a line break, then text that ends as `skipText` ends it and holds
    /// something: that text without the spaces at its ends, or nil with the cursor left where it was.
    private mutating func readKeywordText(_ keyword: [UInt8], endsAtColon: Bool) -> String? {
        guard cursor.hasCaseInsensitivePrefix(keyword), let separator = cursor.peek(keyword.count),
              Self.isSpace(separator) || separator == MermaidByte.newline else { return nil }
        var lookahead = cursor
        lookahead.advance(by: keyword.count + 1)
        let start = lookahead.position
        Self.skipText(&lookahead, endsAtColon: endsAtColon)
        guard lookahead.position > start else { return nil }
        cursor = lookahead
        return cursor.trimmedText(from: start, to: cursor.position)
    }

    /// A task: its text from the cursor to a colon, then its data, the colon and what follows it to the end of its
    /// text, which must hold something.
    private mutating func readTask() throws(MermaidDiagramReadError) {
        let start = cursor.position
        cursor.advance()
        Self.skipText(&cursor, endsAtColon: true)
        let text = cursor.trimmedText(from: start, to: cursor.position)
        skipSpacesAndComments()
        guard cursor.peek() == MermaidByte.colon else { throw .invalidSyntax(line: cursor.line, problem: .expectedTaskScore) }
        let dataStart = cursor.position
        cursor.advance()
        Self.skipText(&cursor, endsAtColon: false)
        guard cursor.position > dataStart + 1 else { throw .invalidSyntax(line: cursor.line, problem: .expectedTaskScore) }
        try builder.addTask(Self.label(text), data: Substring(cursor.text(from: dataStart, to: cursor.position)))
    }

    /// Moves to the `#`, `;` or line break that ends a text, or to a colon too when `endsAtColon`.
    private static func skipText(_ cursor: inout MermaidTextCursor, endsAtColon: Bool) {
        while let byte = cursor.peek(), byte != numberSign, byte != MermaidByte.semicolon, byte != MermaidByte.newline,
              !(endsAtColon && byte == MermaidByte.colon) {
            cursor.advance()
        }
    }

    /// Text as the user journey draws it: `<br>` breaks a line, entity codes are read, and other tags stay as written.
    private static func label(_ text: String) -> DiagramLabel {
        DiagramLabelDecoder.label(from: text, form: .literal)
    }

    /// A space, a tab, a carriage return, a vertical tab or a form feed: what Mermaid's grammar skips between tokens.
    private static func isSpace(_ byte: UInt8) -> Bool {
        MermaidByte.isSpace(byte) || byte == MermaidByte.carriageReturn || byte == verticalTab || byte == formFeed
    }

    private static let journeyKeyword = Array("journey".utf8)
    private static let titleKeyword = Array("title".utf8)
    private static let sectionKeyword = Array("section".utf8)
    private static let numberSign = UInt8(ascii: "#")
    private static let verticalTab: UInt8 = 0x0B
    private static let formFeed: UInt8 = 0x0C
}
