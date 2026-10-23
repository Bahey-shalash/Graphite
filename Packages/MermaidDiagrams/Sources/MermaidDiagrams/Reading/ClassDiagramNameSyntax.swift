/// A class's name as a class diagram writes it, and the generic type after it.
struct ClassDiagramName: Equatable {
    let identifier: String
    /// The text between the tildes after the name (`T` in `Square~T~`), or nil.
    let genericType: String?
}

/// Reads class names: identifier characters (letters, digits, `_`, any character beyond ASCII), with a `-` or a `.`
/// kept where another identifier character follows it (`Ca-r`, `Company.Engine`, while `A--B` and `A..B` stop before
/// the line); or any text but a backtick between backticks (`` `Animal Class!` ``). A generic type between tildes may
/// follow either (`Square~Shape~`).
enum ClassDiagramNameSyntax {
    /// Reads a name at the cursor and moves past it, or returns nil, without moving, when no name starts there.
    static func read(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> ClassDiagramName? {
        let identifier: String
        if cursor.peek() == MermaidByte.graveAccent {
            identifier = try readBacktickedName(&cursor)
        } else if let plain = readPlainName(&cursor) {
            identifier = plain
        } else {
            return nil
        }
        return ClassDiagramName(identifier: identifier, genericType: try readGenericType(&cursor))
    }

    private static func readPlainName(_ cursor: inout MermaidTextCursor) -> String? {
        let start = cursor.position
        while let byte = cursor.peek() {
            if MermaidByte.isIdentifierByte(byte) {
                cursor.advance()
            } else if byte == MermaidByte.hyphen || byte == MermaidByte.period, cursor.position > start, let next = cursor.peek(1),
                      MermaidByte.isIdentifierByte(next) {
                cursor.advance()
            } else {
                break
            }
        }
        return cursor.position > start ? cursor.text(from: start, to: cursor.position) : nil
    }

    /// `` `any text` `` on one line.
    private static func readBacktickedName(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> String {
        let line = cursor.line
        cursor.advance()
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.graveAccent, byte != MermaidByte.newline { cursor.advance() }
        guard cursor.peek() == MermaidByte.graveAccent else { throw .invalidSyntax(line: line, problem: .unclosedQuotation) }
        let name = cursor.text(from: start, to: cursor.position)
        cursor.advance()
        return name
    }

    /// `~T~` right after a name, on one line; nil when there is none or it is empty.
    private static func readGenericType(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> String? {
        guard cursor.peek() == MermaidByte.tilde else { return nil }
        let line = cursor.line
        cursor.advance()
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.tilde, byte != MermaidByte.newline { cursor.advance() }
        guard cursor.peek() == MermaidByte.tilde else { throw .invalidSyntax(line: line, problem: .unclosedGenericType) }
        let genericType = cursor.text(from: start, to: cursor.position)
        cursor.advance()
        return genericType.isEmpty ? nil : genericType
    }
}
