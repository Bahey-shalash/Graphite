import Foundation

/// Reads a timeline's statements after its `timeline` keyword, as Mermaid's timeline grammar does: an optional
/// direction (`LR` or `TD`) on the keyword's line, then `title …`, `section …`, accessibility text, time periods,
/// and events, each after a colon followed by a space: on a period's line (`2004 : Facebook : Google`) or on the
/// lines that follow it (`: Google`). A period runs to a colon, a `#` or the end of its line; an event to the end of
/// its line or to the next colon followed by a space. Comments (`%%`, and `#` where a statement would start) and
/// spaces between statements are skipped. Keywords are read without regard to case.
struct TimelineParser {
    private var cursor: MermaidTextCursor
    private var builder: TimelineDiagramBuilder

    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> TimelineDiagram {
        var parser = TimelineParser(cursor: cursor, builder: TimelineDiagramBuilder(limits: limits))
        parser.readDirection()
        try parser.readStatements()
        return parser.builder.diagram
    }

    /// `LR` or `TD` after at least one space on the keyword's line. Anything else there is read as the statements are.
    private mutating func readDirection() {
        var lookahead = cursor
        lookahead.skipSpaces()
        guard lookahead.position > cursor.position, !Self.isWordByte(lookahead.peek(2)) else { return }
        if lookahead.hasCaseInsensitivePrefix(Self.leftToRight) {
            builder.setDirection(.leftToRight)
        } else if lookahead.hasCaseInsensitivePrefix(Self.topToBottom) {
            builder.setDirection(.topToBottom)
        } else {
            return
        }
        lookahead.advance(by: 2)
        cursor = lookahead
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            skipSpacesAndComments()
            guard let byte = cursor.peek() else { return }
            if byte == MermaidByte.newline {
                cursor.advance()
            } else if isAtKeyword(Self.timelineKeyword) {
                throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
            } else if let title = readTitle() {
                builder.setTitle(title.trimmingCharacters(in: .whitespacesAndNewlines))
            } else if let statement = try MermaidAccessibilityStatement.read(&cursor) {
                builder.apply(statement)
            } else if let section = readSection() {
                try builder.addSection(Self.label(section))
            } else if byte != MermaidByte.colon {
                let period = readPeriod()
                try builder.addPeriod(Self.label(period))
            } else if let event = readEvent() {
                try builder.addEvent(Self.label(event.text), line: event.line)
            } else {
                throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
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

    /// `title` and a space, then the rest of the line, which must hold something.
    private mutating func readTitle() -> String? {
        guard isAtKeyword(Self.titleKeyword), let separator = cursor.peek(Self.titleKeyword.count), Self.isSpace(separator) || separator == MermaidByte.newline,
              let first = cursor.peek(Self.titleKeyword.count + 1), first != MermaidByte.newline else { return nil }
        cursor.advance(by: Self.titleKeyword.count + 1)
        return cursor.readRestOfLine()
    }

    /// `section` and a space, then text up to a colon or the end of the line, which must hold something.
    private mutating func readSection() -> String? {
        guard isAtKeyword(Self.sectionKeyword), let separator = cursor.peek(Self.sectionKeyword.count),
              Self.isSpace(separator) || separator == MermaidByte.newline else { return nil }
        var lookahead = cursor
        lookahead.advance(by: Self.sectionKeyword.count + 1)
        let start = lookahead.position
        while let byte = lookahead.peek(), byte != MermaidByte.colon, byte != MermaidByte.newline { lookahead.advance() }
        guard lookahead.position > start else { return nil }
        cursor = lookahead
        return cursor.text(from: start, to: cursor.position)
    }

    /// A period: from the cursor, which is at no colon, to a colon, a `#` or the end of the line.
    private mutating func readPeriod() -> String {
        let start = cursor.position
        cursor.advance()
        while let byte = cursor.peek(), byte != MermaidByte.colon, byte != Self.numberSign, byte != MermaidByte.newline { cursor.advance() }
        return cursor.text(from: start, to: cursor.position)
    }

    /// An event: a colon and a space, then text to the end of the line or to the next colon followed by a space, which
    /// must hold something. Nil, with the cursor left where it was, when there is none.
    private mutating func readEvent() -> (text: String, line: Int)? {
        guard let separator = cursor.peek(1), Self.isSpace(separator) || separator == MermaidByte.newline else { return nil }
        var lookahead = cursor
        let line = lookahead.line
        lookahead.advance(by: 2)
        let start = lookahead.position
        while let byte = lookahead.peek(), byte != MermaidByte.newline {
            if byte == MermaidByte.colon, let next = lookahead.peek(1), Self.isSpace(next) || next == MermaidByte.newline { break }
            lookahead.advance()
        }
        guard lookahead.position > start else { return nil }
        cursor = lookahead
        return (cursor.text(from: start, to: cursor.position), line)
    }

    /// Text as the timeline draws it: `<br>` breaks a line, entity codes are read, and other tags stay as written.
    private static func label(_ text: String) -> DiagramLabel {
        DiagramLabelDecoder.label(from: text.trimmingCharacters(in: .whitespacesAndNewlines), form: .literal)
    }

    /// Whether `keyword` (lowercase) is at the cursor, in any case, and no letter, digit or underscore follows it.
    private func isAtKeyword(_ keyword: [UInt8]) -> Bool {
        cursor.hasCaseInsensitivePrefix(keyword) && !Self.isWordByte(cursor.peek(keyword.count))
    }

    /// A space, a tab, a carriage return, a vertical tab or a form feed: what Mermaid's grammar skips between tokens.
    private static func isSpace(_ byte: UInt8) -> Bool {
        MermaidByte.isSpace(byte) || byte == MermaidByte.carriageReturn || byte == verticalTab || byte == formFeed
    }

    private static func isWordByte(_ byte: UInt8?) -> Bool {
        guard let byte else { return false }
        return MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
    }

    private static let timelineKeyword = Array("timeline".utf8)
    private static let titleKeyword = Array("title".utf8)
    private static let sectionKeyword = Array("section".utf8)
    private static let leftToRight = Array("lr".utf8)
    private static let topToBottom = Array("td".utf8)
    private static let numberSign = UInt8(ascii: "#")
    private static let verticalTab: UInt8 = 0x0B
    private static let formFeed: UInt8 = 0x0C
}
