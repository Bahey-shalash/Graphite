/// What a relation's operator says: the marks at its ends and its line (`<|--` is an inheritance mark at the source
/// on a solid line).
struct ClassDiagramRelationOperator: Equatable {
    let sourceEnd: ClassDiagramRelationEnd
    let targetEnd: ClassDiagramRelationEnd
    let line: ClassDiagramLineStyle
}

/// Reads a relation's operator: an optional mark, the line (`--` or `..`), an optional mark. A mark is `<|` or `|>`
/// (inheritance), `*` (composition), `o` (aggregation, when no identifier character follows it, so that `-- order`
/// names a class), `<` or `>` (arrow) or `()` (lollipop), on either side, as Mermaid's grammar allows.
enum ClassDiagramRelationSyntax {
    /// Reads an operator at the cursor and moves past it, or returns nil, without moving, when there is none.
    static func readOperator(_ cursor: inout MermaidTextCursor) -> ClassDiagramRelationOperator? {
        var lookahead = cursor
        let sourceEnd = readEnd(&lookahead)
        lookahead.skipSpaces()
        guard let line = readLine(&lookahead) else { return nil }
        lookahead.skipSpaces()
        let targetEnd = readEnd(&lookahead)
        cursor = lookahead
        return ClassDiagramRelationOperator(sourceEnd: sourceEnd, targetEnd: targetEnd, line: line)
    }

    /// Whether a mark or a line starts at the cursor: what follows a class's name in a relation.
    static func startsOperator(_ cursor: MermaidTextCursor) -> Bool {
        var lookahead = cursor
        return readEnd(&lookahead) != .none || readLine(&lookahead) != nil
    }

    private static func readLine(_ cursor: inout MermaidTextCursor) -> ClassDiagramLineStyle? {
        if cursor.hasPrefix(solidLine) {
            cursor.advance(by: solidLine.count)
            return .solid
        }
        if cursor.hasPrefix(dashedLine) {
            cursor.advance(by: dashedLine.count)
            return .dashed
        }
        return nil
    }

    private static func readEnd(_ cursor: inout MermaidTextCursor) -> ClassDiagramRelationEnd {
        for (written, end) in twoByteEnds where cursor.hasPrefix(written) {
            cursor.advance(by: written.count)
            return end
        }
        guard let byte = cursor.peek() else { return .none }
        switch byte {
        case MermaidByte.lessThan, MermaidByte.greaterThan:
            cursor.advance()
            return .arrow
        case asterisk:
            cursor.advance()
            return .composition
        case MermaidByte.letterO:
            if let next = cursor.peek(1), MermaidByte.isIdentifierByte(next) { return .none }
            cursor.advance()
            return .aggregation
        default:
            return .none
        }
    }

    private static let solidLine = Array("--".utf8)
    private static let dashedLine = Array("..".utf8)
    private static let asterisk = UInt8(ascii: "*")
    /// The marks written with two characters, tried before the one-character `<`.
    private static let twoByteEnds: [([UInt8], ClassDiagramRelationEnd)] = [
        (Array("<|".utf8), .inheritance), (Array("|>".utf8), .inheritance), (Array("()".utf8), .lollipop),
    ]
}
