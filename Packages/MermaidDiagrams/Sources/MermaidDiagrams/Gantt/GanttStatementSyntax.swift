import Foundation

/// A statement of a Gantt chart that starts with a keyword.
enum GanttKeyword {
    case dateFormat
    case axisFormat
    case inclusiveEndDates
    case topAxis
    case tickInterval
    case excludes
    case includes
    case todayMarker
    case weekday
    case weekendFromFriday
    case weekendFromSaturday
    case title
    case section
    /// A keyword that cannot start a statement (`gantt` again, `accDescription`, `href`, `call`): an error.
    case notAStatement
}

/// The tokens of Mermaid's Gantt grammar at the start of a statement: comments, keywords with their values, the
/// accessibility statements, and tasks.
enum GanttStatementSyntax {
    /// Where a keyword's value ends: how far the grammar's pattern for it reads.
    private enum ValueEnd {
        /// At `#`, `;` or the end of the line.
        case settingEnd
        /// At `;` or the end of the line.
        case semicolonOrLineEnd
        /// At the end of the line.
        case lineEnd
    }

    /// The keywords that take a value, each with where its value ends, in the order the grammar tries them.
    private static let keywordsWithValues: [(word: [UInt8], keyword: GanttKeyword, end: ValueEnd)] = [
        (Array("axisformat".utf8), .axisFormat, .settingEnd), (Array("accdescription".utf8), .notAStatement, .settingEnd),
        (Array("dateformat".utf8), .dateFormat, .settingEnd), (Array("includes".utf8), .includes, .settingEnd),
        (Array("tickinterval".utf8), .tickInterval, .settingEnd), (Array("todaymarker".utf8), .todayMarker, .semicolonOrLineEnd),
        (Array("title".utf8), .title, .lineEnd), (Array("excludes".utf8), .excludes, .settingEnd), (Array("section".utf8), .section, .lineEnd),
    ]
    /// The keywords that stand alone, ending where a word ends.
    private static let keywordsAlone: [(word: [UInt8], keyword: GanttKeyword)] = [
        (Array("gantt".utf8), .notAStatement), (Array("inclusiveenddates".utf8), .inclusiveEndDates), (Array("topaxis".utf8), .topAxis),
    ]
    private static let dayNames = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"].map { name in Array(name.utf8) }
    private static let numberSign = UInt8(ascii: "#")

    /// A space, a tab, a carriage return, a vertical tab or a form feed: whitespace other than a line break.
    static func isSpace(_ byte: UInt8) -> Bool {
        byte == MermaidByte.space || byte == MermaidByte.tab || byte == MermaidByte.carriageReturn || byte == 0x0B || byte == 0x0C
    }

    /// Whitespace as a regular expression's `\s` reads it among ASCII: a space or a line break.
    private static func isWhitespace(_ byte: UInt8) -> Bool {
        isSpace(byte) || byte == MermaidByte.newline
    }

    /// Skips a comment to the end of its line and returns true: `%%` or a lone `%`, or any character but `}` followed
    /// by `%`. `%%{` is a directive, which the grammar cannot read here.
    static func skipComment(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> Bool {
        guard let byte = cursor.peek() else { return false }
        if byte == MermaidByte.percent, cursor.peek(1) == MermaidByte.percent, cursor.peek(2) == MermaidByte.openingBrace {
            throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
        }
        guard byte == MermaidByte.percent || (byte != MermaidByte.closingBrace && cursor.peek(1) == MermaidByte.percent) else { return false }
        cursor.skipToEndOfLine()
        return true
    }

    /// A keyword statement at the cursor, with its value without the spaces at either end, or nil with the cursor
    /// where it was. A keyword that takes a value needs a space and at least one character of value.
    static func readKeywordStatement(_ cursor: inout MermaidTextCursor) -> (GanttKeyword, String)? {
        for (word, keyword) in keywordsAlone where cursor.hasCaseInsensitivePrefix(word) {
            guard !isWordByte(cursor.peek(word.count)) else { continue }
            cursor.advance(by: word.count)
            return (keyword, "")
        }
        if let weekStatement = readWeekStatement(&cursor) { return weekStatement }
        for (word, keyword, end) in keywordsWithValues where cursor.hasCaseInsensitivePrefix(word) {
            guard let separator = cursor.peek(word.count), isWhitespace(separator) else { continue }
            var lookahead = cursor
            lookahead.advance(by: word.count + 1)
            let valueStart = lookahead.position
            while let byte = lookahead.peek(), !ends(byte, end) { lookahead.advance() }
            guard lookahead.position > valueStart else { continue }
            cursor = lookahead
            return (keyword, trimmed(cursor.text(from: valueStart, to: cursor.position)))
        }
        if cursor.hasCaseInsensitivePrefix(Array("href".utf8)) || cursor.hasCaseInsensitivePrefix(Array("call".utf8)),
           let separator = cursor.peek(4), isWhitespace(separator) {
            return (.notAStatement, "")
        }
        return nil
    }

    /// `weekday monday` … `weekday sunday`, `weekend friday` or `weekend saturday`.
    private static func readWeekStatement(_ cursor: inout MermaidTextCursor) -> (GanttKeyword, String)? {
        let isWeekday = cursor.hasCaseInsensitivePrefix(Array("weekday".utf8))
        guard isWeekday || cursor.hasCaseInsensitivePrefix(Array("weekend".utf8)) else { return nil }
        var lookahead = cursor
        lookahead.advance(by: "weekday".count)
        guard let separator = lookahead.peek(), isWhitespace(separator) else { return nil }
        while let byte = lookahead.peek(), isWhitespace(byte) { lookahead.advance() }
        let names = isWeekday ? dayNames : [dayNames[4], dayNames[5]]
        guard let name = names.first(where: { name in lookahead.hasCaseInsensitivePrefix(name) && !isWordByte(lookahead.peek(name.count)) }) else {
            return nil
        }
        lookahead.advance(by: name.count)
        cursor = lookahead
        if isWeekday { return (.weekday, String(decoding: name, as: UTF8.self)) }
        return (name == dayNames[4] ? .weekendFromFriday : .weekendFromSaturday, "")
    }

    /// `keyword: text` (`accTitle`, `accDescr`), its text to the end of the line without the spaces at either end, or
    /// nil with the cursor where it was.
    static func readAccessibilityLine(_ cursor: inout MermaidTextCursor, keyword: [UInt8]) -> String? {
        guard cursor.hasCaseInsensitivePrefix(keyword) else { return nil }
        var lookahead = cursor
        lookahead.advance(by: keyword.count)
        lookahead.skipWhitespace()
        guard lookahead.peek() == MermaidByte.colon else { return nil }
        lookahead.advance()
        let start = lookahead.position
        lookahead.skipToEndOfLine()
        cursor = lookahead
        return trimmed(cursor.text(from: start, to: cursor.position))
    }

    /// `accDescr { lines }`, its text trimmed and the spaces and blank lines after each line break left out, or nil
    /// with the cursor where it was.
    static func readAccessibilityBlock(_ cursor: inout MermaidTextCursor, keyword: [UInt8]) throws(MermaidDiagramReadError) -> String? {
        guard cursor.hasCaseInsensitivePrefix(keyword) else { return nil }
        var lookahead = cursor
        lookahead.advance(by: keyword.count)
        lookahead.skipWhitespace()
        guard lookahead.peek() == MermaidByte.openingBrace else { return nil }
        let openingLine = lookahead.line
        lookahead.advance()
        let start = lookahead.position
        while let byte = lookahead.peek(), byte != MermaidByte.closingBrace { lookahead.advance() }
        guard !lookahead.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedAccessibilityDescription) }
        let text = trimmed(lookahead.text(from: start, to: lookahead.position))
        lookahead.advance()
        cursor = lookahead
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let following = lines.dropFirst().map { line in String(line.drop { character in character.isWhitespace }) }.filter { line in !line.isEmpty }
        return ([String(lines.first ?? "")] + following).joined(separator: "\n")
    }

    /// Whether `click` and a space are at the cursor.
    static func isAtClick(_ cursor: MermaidTextCursor) -> Bool {
        guard cursor.hasCaseInsensitivePrefix(Array("click".utf8)), let separator = cursor.peek(5) else { return false }
        return isWhitespace(separator)
    }

    /// Whether a date (`2014-01-01`) or a colon starts the statement, which the grammar cannot read there.
    static func isAtDateOrColon(_ cursor: MermaidTextCursor) -> Bool {
        if cursor.peek() == MermaidByte.colon { return true }
        let digitOffsets = [0, 1, 2, 3, 5, 6, 8, 9]
        guard digitOffsets.allSatisfy({ offset in cursor.peek(offset).map(MermaidByte.isDigit) ?? false }),
              cursor.peek(4) == MermaidByte.hyphen, cursor.peek(7) == MermaidByte.hyphen else { return false }
        return !isWordByte(cursor.peek(10))
    }

    /// A task: its text up to the colon, without the spaces at either end, and its data after the colon up to `#`,
    /// `;` or the end of the line.
    static func readTask(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> (name: String, data: String) {
        let line = cursor.line
        let nameStart = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.colon, byte != MermaidByte.newline { cursor.advance() }
        guard cursor.peek() == MermaidByte.colon else { throw .invalidSyntax(line: line, problem: .expectedTaskData) }
        let name = trimmed(cursor.text(from: nameStart, to: cursor.position))
        cursor.advance()
        let dataStart = cursor.position
        while let byte = cursor.peek(), !ends(byte, .settingEnd) { cursor.advance() }
        guard cursor.position > dataStart else { throw .invalidSyntax(line: line, problem: .expectedTaskData) }
        return (name, cursor.text(from: dataStart, to: cursor.position))
    }

    /// The words of `value`, lowercased and split at spaces and commas, added to `words` where they are not yet.
    static func merging(_ value: String, into words: [String]) -> [String] {
        var merged = words
        for word in value.lowercased().split(whereSeparator: { character in character.isWhitespace || character == "," })
        where !merged.contains(String(word)) {
            merged.append(String(word))
        }
        return merged
    }

    private static func ends(_ byte: UInt8, _ end: ValueEnd) -> Bool {
        switch end {
        case .settingEnd: byte == MermaidByte.newline || byte == MermaidByte.semicolon || byte == numberSign
        case .semicolonOrLineEnd: byte == MermaidByte.newline || byte == MermaidByte.semicolon
        case .lineEnd: byte == MermaidByte.newline
        }
    }

    /// Whether a byte continues a word, as a regular expression's `\w` reads it.
    private static func isWordByte(_ byte: UInt8?) -> Bool {
        guard let byte else { return false }
        return MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
