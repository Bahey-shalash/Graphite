/// Reads a message's arrow, as Mermaid's sequence grammar spells them.
enum SequenceArrowSyntax {
    /// What an arrow at the cursor is.
    enum Operator: Equatable {
        /// `->`, `-->`, `->>`, `-->>`, `-x`, `--x`, `-)`, `--)`, `<<->>` or `<<-->>`.
        case arrow(SequenceArrow)
        /// One of Mermaid 12's half arrows (`-|\`, `-|/`, `-\\`, `-//`, their dotted forms and their reverses), which
        /// is read but not laid out.
        case halfArrow
    }

    /// Reads the arrow at the cursor and moves past it; nil when none starts there.
    static func readOperator(_ cursor: inout MermaidTextCursor) -> Operator? {
        guard let (found, length) = operatorAt(cursor) else { return nil }
        cursor.advance(by: length)
        return found
    }

    private static func operatorAt(_ cursor: MermaidTextCursor) -> (Operator, Int)? {
        if cursor.hasPrefix(twoWaySolid) { return (.arrow(SequenceArrow(stroke: .solid, head: .arrow, pointsBothWays: true)), twoWaySolid.count) }
        if cursor.hasPrefix(twoWayDotted) { return (.arrow(SequenceArrow(stroke: .dotted, head: .arrow, pointsBothWays: true)), twoWayDotted.count) }
        guard let first = cursor.peek() else { return nil }
        if first == SequenceTextSyntax.slash || first == SequenceTextSyntax.backslash { return reverseHalfArrow(cursor) }
        guard first == MermaidByte.hyphen else { return nil }
        let isDotted = cursor.peek(1) == MermaidByte.hyphen
        let headOffset = isDotted ? 2 : 1
        let stroke: SequenceLineStroke = isDotted ? .dotted : .solid
        guard let headByte = cursor.peek(headOffset) else { return nil }
        let following = cursor.peek(headOffset + 1)
        switch headByte {
        case MermaidByte.greaterThan:
            if following == MermaidByte.greaterThan { return (.arrow(SequenceArrow(stroke: stroke, head: .arrow)), headOffset + 2) }
            return (.arrow(SequenceArrow(stroke: stroke, head: .none)), headOffset + 1)
        case MermaidByte.letterX, UInt8(ascii: "X"): return (.arrow(SequenceArrow(stroke: stroke, head: .cross)), headOffset + 1)
        case SequenceTextSyntax.closingParenthesis: return (.arrow(SequenceArrow(stroke: stroke, head: .open)), headOffset + 1)
        case MermaidByte.verticalBar where following == SequenceTextSyntax.backslash || following == SequenceTextSyntax.slash:
            return (.halfArrow, headOffset + 2)
        case SequenceTextSyntax.backslash where following == SequenceTextSyntax.backslash, SequenceTextSyntax.slash where following == SequenceTextSyntax.slash:
            return (.halfArrow, headOffset + 2)
        default: return nil
        }
    }

    /// `/|-`, `\|-`, `//-`, `\\-` and their dotted forms ending `--`.
    private static func reverseHalfArrow(_ cursor: MermaidTextCursor) -> (Operator, Int)? {
        guard let first = cursor.peek(), let second = cursor.peek(1), second == MermaidByte.verticalBar || second == first,
              cursor.peek(2) == MermaidByte.hyphen else { return nil }
        return (.halfArrow, cursor.peek(3) == MermaidByte.hyphen ? 4 : 3)
    }

    private static let twoWaySolid = Array("<<->>".utf8)
    private static let twoWayDotted = Array("<<-->>".utf8)
}
