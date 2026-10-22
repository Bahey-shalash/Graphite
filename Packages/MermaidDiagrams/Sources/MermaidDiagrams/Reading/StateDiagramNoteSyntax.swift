/// A note statement that sits beside a state.
struct StateDiagramNoteDeclaration: Equatable {
    let state: StateDiagramStateReference
    let side: StateDiagramNoteSide
    let text: DiagramLabel
}

/// Reads what follows the keyword `note`: `left of Id : text` on one line, `left of Id` with lines up to a line that
/// starts with `end note`, or a floating note (`"text" as Id`), which Mermaid reads and does not draw.
enum StateDiagramNoteSyntax {
    /// Reads from the cursor, after `note` and its space, to the end of the note. Nil for a floating note.
    /// - Parameter keywordLine: The line of `note`, which a note without `end note` is reported on.
    static func readNote(_ cursor: inout MermaidTextCursor, keywordLine: Int) throws(MermaidDiagramReadError) -> StateDiagramNoteDeclaration? {
        cursor.skipSpaces()
        if try StateDiagramTextSyntax.readQuotedText(&cursor) != nil {
            try readFloatingNoteIdentifier(&cursor)
            return nil
        }
        guard let side = readSide(&cursor) else {
            throw .invalidSyntax(line: cursor.line, problem: cursor.isAtEnd ? .expectedState : .unexpectedText(cursor.excerpt()))
        }
        cursor.skipSpaces()
        guard let state = StateDiagramTextSyntax.readReference(&cursor) else { throw .invalidSyntax(line: cursor.line, problem: .expectedState) }
        cursor.skipSpaces()
        if let text = StateDiagramTextSyntax.readColonText(&cursor) {
            return StateDiagramNoteDeclaration(state: state, side: side, text: text)
        }
        let text = try readLinesUpToEndNote(&cursor, keywordLine: keywordLine)
        return StateDiagramNoteDeclaration(state: state, side: side, text: StateDiagramTextSyntax.label(from: text))
    }

    /// `left of` or `right of`, in any case, followed by a space.
    private static func readSide(_ cursor: inout MermaidTextCursor) -> StateDiagramNoteSide? {
        for (side, words) in sideWords where StateDiagramTextSyntax.isAtKeyword(cursor, words) {
            cursor.advance(by: words.count)
            return side
        }
        return nil
    }

    /// The text from the cursor to the next line whose first word is `end note`, trimmed; the cursor moves past
    /// `end note`. A line that holds `end note` after other words does not end the note.
    private static func readLinesUpToEndNote(_ cursor: inout MermaidTextCursor, keywordLine: Int) throws(MermaidDiagramReadError) -> String {
        let start = cursor.position
        while true {
            cursor.skipToEndOfLine()
            guard !cursor.isAtEnd else { throw .invalidSyntax(line: keywordLine, problem: .unclosedNote) }
            cursor.advance()
            let lineStart = cursor.position
            cursor.skipSpaces()
            if StateDiagramTextSyntax.isAtKeyword(cursor, endNoteWords) {
                let text = cursor.trimmedText(from: start, to: lineStart)
                cursor.advance(by: endNoteWords.count)
                return text
            }
        }
    }

    /// `as Id` after a floating note's text.
    private static func readFloatingNoteIdentifier(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) {
        cursor.skipSpaces()
        guard StateDiagramTextSyntax.isAtKeyword(cursor, asWord) else {
            throw .invalidSyntax(line: cursor.line, problem: cursor.isAtEnd ? .expectedState : .unexpectedText(cursor.excerpt()))
        }
        cursor.advance(by: asWord.count)
        cursor.skipSpaces()
        guard StateDiagramTextSyntax.readIdentifier(&cursor) != nil else { throw .invalidSyntax(line: cursor.line, problem: .expectedState) }
    }

    private static let sideWords: [(StateDiagramNoteSide, [UInt8])] = [(.left, Array("left of".utf8)), (.right, Array("right of".utf8))]
    private static let endNoteWords = Array("end note".utf8)
    private static let asWord = Array("as".utf8)
}
