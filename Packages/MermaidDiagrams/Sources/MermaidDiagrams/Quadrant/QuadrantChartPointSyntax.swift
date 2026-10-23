/// A quadrant chart point's `: [x, y]`, as Mermaid's quadrant grammar reads it: a colon and an opening bracket, with
/// any spaces and line breaks before, between and after them, then two coordinates separated by a comma and the
/// closing bracket, and the spaces after it. A coordinate is `1`, or `0` alone or followed by any character and digits
/// (`0.75`; Mermaid's pattern takes `0x5` and `0,5` too, which are no number from 0 to 1).
enum QuadrantChartPointSyntax {
    /// The point's coordinates as written, moving the cursor past them, or nil, with the cursor where it was, when no
    /// point starts at the cursor. A point whose brackets do not hold two coordinates is an error.
    static func readPoint(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> QuadrantChartTokenContent? {
        guard let byte = cursor.peek(), byte == MermaidByte.colon || isWhitespace(byte) else { return nil }
        var lookahead = cursor
        skipWhitespace(&lookahead)
        guard lookahead.peek() == MermaidByte.colon else { return nil }
        lookahead.advance()
        skipWhitespace(&lookahead)
        guard lookahead.peek() == MermaidByte.openingBracket else { return nil }
        lookahead.advance()
        cursor = lookahead
        skipWhitespace(&cursor)
        let xCoordinate = try readCoordinate(&cursor)
        skipWhitespace(&cursor)
        try expect(MermaidByte.comma, &cursor)
        skipWhitespace(&cursor)
        let yCoordinate = try readCoordinate(&cursor)
        skipWhitespace(&cursor)
        try expect(MermaidByte.closingBracket, &cursor)
        while cursor.peek() == MermaidByte.space { cursor.advance() }
        return .coordinates(xCoordinate: xCoordinate, yCoordinate: yCoordinate)
    }

    /// `1`, or `0`, then any character but a line break and digits when they follow it.
    private static func readCoordinate(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> String {
        let start = cursor.position
        if cursor.peek() == one {
            cursor.advance()
        } else if cursor.peek() == zero {
            cursor.advance()
            if let next = cursor.peek(), next != MermaidByte.newline, next != MermaidByte.carriageReturn, let digit = cursor.peek(1),
               MermaidByte.isDigit(digit) {
                cursor.advance(by: 2)
                while let byte = cursor.peek(), MermaidByte.isDigit(byte) { cursor.advance() }
            }
        } else {
            throw .invalidSyntax(line: cursor.line, problem: .expectedPointCoordinates)
        }
        return cursor.text(from: start, to: cursor.position)
    }

    private static func expect(_ byte: UInt8, _ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) {
        guard cursor.peek() == byte else { throw .invalidSyntax(line: cursor.line, problem: .expectedPointCoordinates) }
        cursor.advance()
    }

    /// Spaces, tabs, line breaks, carriage returns, vertical tabs and form feeds: what Mermaid's `\s` takes here.
    private static func skipWhitespace(_ cursor: inout MermaidTextCursor) {
        while let byte = cursor.peek(), isWhitespace(byte) { cursor.advance() }
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        MermaidByte.isWhitespace(byte) || byte == verticalTab || byte == formFeed
    }

    private static let zero = UInt8(ascii: "0")
    private static let one = UInt8(ascii: "1")
    private static let verticalTab: UInt8 = 0x0B
    private static let formFeed: UInt8 = 0x0C
}
