import Foundation

/// What a link between two nodes says: its stroke, its marks, how many ranks it spans and its text.
struct FlowchartLink: Equatable {
    var stroke: FlowchartEdgeStroke
    var sourceArrowhead: FlowchartArrowhead
    var targetArrowhead: FlowchartArrowhead
    var minimumRankSpan: Int
    var label: DiagramLabel?
    /// The identifier written before the link (`e1@-->`), or nil.
    var identifier: String?
}

/// Reads a link: `-->`, `---`, `-.->`, `==>`, `~~~` and their longer forms, a mark at either end (`<`, `>`, `o`, `x`),
/// the text in bars after it (`-->|text|`) or inside it (`-- text -->`, `-. text .->`, `== text ==>`), and an
/// identifier before it (`e1@-->`), which is read and left.
enum FlowchartLinkSyntax {
    /// Reads a link at the cursor, or returns nil and leaves the cursor where it was when none starts there.
    static func readLink(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> FlowchartLink? {
        var lookahead = cursor
        var identifier = lookahead.readIdentifier()
        if identifier == nil || lookahead.peek() != MermaidByte.atSign || lookahead.peek(1) == MermaidByte.openingBrace {
            lookahead = cursor
            identifier = nil
        } else {
            lookahead.advance()
        }
        guard var link = try readOperator(&lookahead) else { return nil }
        link.identifier = identifier
        cursor = lookahead
        cursor.skipSpaces()
        if cursor.peek() == MermaidByte.verticalBar {
            let openingLine = cursor.line
            cursor.advance()
            link.label = try readBarredLabel(&cursor, openingLine: openingLine)
        }
        return link
    }

    /// The operator itself, with any text written inside it.
    private static func readOperator(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> FlowchartLink? {
        let tildeCount = runLength(of: MermaidByte.tilde, in: cursor)
        if tildeCount >= 3 {
            cursor.advance(by: tildeCount)
            return FlowchartLink(stroke: .invisible, sourceArrowhead: .none, targetArrowhead: .none, minimumRankSpan: tildeCount - 2)
        }
        var lookahead = cursor
        let sourceArrowhead = readSourceArrowhead(&lookahead)
        let link: FlowchartLink?
        switch lookahead.peek() {
        case MermaidByte.equals: link = try readRun(of: MermaidByte.equals, stroke: .thick, sourceArrowhead: sourceArrowhead, &lookahead)
        case MermaidByte.hyphen where lookahead.peek(1) == MermaidByte.period:
            link = try readDotted(sourceArrowhead: sourceArrowhead, &lookahead)
        case MermaidByte.hyphen: link = try readRun(of: MermaidByte.hyphen, stroke: .solid, sourceArrowhead: sourceArrowhead, &lookahead)
        default: link = nil
        }
        if link != nil { cursor = lookahead }
        return link
    }

    /// `<`, `o` or `x` right before the line's first `-` or `=`.
    private static func readSourceArrowhead(_ cursor: inout MermaidTextCursor) -> FlowchartArrowhead {
        guard let mark = cursor.peek(), let next = cursor.peek(1), next == MermaidByte.hyphen || next == MermaidByte.equals,
              let arrowhead = arrowhead(forMark: mark, isSourceEnd: true) else { return .none }
        cursor.advance()
        return arrowhead
    }

    /// `-->`, `---`, `==>`, `===` and their longer forms; two signs followed by a space start text inside the link.
    private static func readRun(of sign: UInt8, stroke: FlowchartEdgeStroke, sourceArrowhead: FlowchartArrowhead,
                                _ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> FlowchartLink? {
        let count = runLength(of: sign, in: cursor)
        guard count >= 2 else { return nil }
        let openingLine = cursor.line
        cursor.advance(by: count)
        if let mark = cursor.peek(), let arrowhead = arrowhead(forMark: mark, isSourceEnd: false) {
            cursor.advance()
            return FlowchartLink(stroke: stroke, sourceArrowhead: sourceArrowhead, targetArrowhead: arrowhead, minimumRankSpan: count - 1)
        }
        if count >= 3 {
            return FlowchartLink(stroke: stroke, sourceArrowhead: sourceArrowhead, targetArrowhead: .none, minimumRankSpan: count - 2)
        }
        return try readTextInside(&cursor, closing: { lookahead in closingRun(of: sign, at: lookahead) }, stroke: stroke,
                                  sourceArrowhead: sourceArrowhead, openingLine: openingLine)
    }

    /// `-.->`, `-.-`, `-..->` and their text form `-. text .->`.
    private static func readDotted(sourceArrowhead: FlowchartArrowhead, _ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> FlowchartLink? {
        let openingLine = cursor.line
        cursor.advance()
        let periodCount = runLength(of: MermaidByte.period, in: cursor)
        cursor.advance(by: periodCount)
        guard cursor.peek() == MermaidByte.hyphen else {
            return try readTextInside(&cursor, closing: closingDotted(at:), stroke: .dotted, sourceArrowhead: sourceArrowhead,
                                      openingLine: openingLine)
        }
        cursor.advance()
        var targetArrowhead = FlowchartArrowhead.none
        if let mark = cursor.peek(), let arrowhead = arrowhead(forMark: mark, isSourceEnd: false) {
            targetArrowhead = arrowhead
            cursor.advance()
        }
        return FlowchartLink(stroke: .dotted, sourceArrowhead: sourceArrowhead, targetArrowhead: targetArrowhead, minimumRankSpan: periodCount)
    }

    /// Text inside a link, up to the first closing operator on the same line, which gives the target's mark and the span.
    private static func readTextInside(_ cursor: inout MermaidTextCursor,
                                       closing: (MermaidTextCursor) -> (length: Int, arrowhead: FlowchartArrowhead, span: Int)?,
                                       stroke: FlowchartEdgeStroke, sourceArrowhead: FlowchartArrowhead,
                                       openingLine: Int) throws(MermaidDiagramReadError) -> FlowchartLink {
        let textStart = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.newline {
            if let (length, targetArrowhead, span) = closing(cursor) {
                let written = FlowchartTextSyntax.unquoted(cursor.text(from: textStart, to: cursor.position).trimmingCharacters(in: .whitespaces))
                cursor.advance(by: length)
                return FlowchartLink(stroke: stroke, sourceArrowhead: sourceArrowhead, targetArrowhead: targetArrowhead, minimumRankSpan: span,
                                     label: DiagramLabelDecoder.label(from: written.text, form: written.form))
            }
            cursor.advance()
        }
        throw .invalidSyntax(line: openingLine, problem: .unclosedEdgeLabel)
    }

    /// The operator that closes text inside a solid or thick link: two or more signs and a mark, or three or more.
    private static func closingRun(of sign: UInt8, at cursor: MermaidTextCursor) -> (length: Int, arrowhead: FlowchartArrowhead, span: Int)? {
        let count = runLength(of: sign, in: cursor)
        guard count >= 2 else { return nil }
        if let mark = cursor.peek(count), let arrowhead = arrowhead(forMark: mark, isSourceEnd: false) {
            return (count + 1, arrowhead, count - 1)
        }
        return count >= 3 ? (count, .none, count - 2) : nil
    }

    /// The operator that closes text inside a dotted link: `.-` or `.->` (and `..->` for a longer one).
    private static func closingDotted(at cursor: MermaidTextCursor) -> (length: Int, arrowhead: FlowchartArrowhead, span: Int)? {
        let periodCount = runLength(of: MermaidByte.period, in: cursor)
        guard periodCount >= 1, cursor.peek(periodCount) == MermaidByte.hyphen else { return nil }
        if let mark = cursor.peek(periodCount + 1), let arrowhead = arrowhead(forMark: mark, isSourceEnd: false) {
            return (periodCount + 2, arrowhead, periodCount)
        }
        return (periodCount + 1, .none, periodCount)
    }

    /// Text between bars after a link: `|text|` or `|"text"|`.
    private static func readBarredLabel(_ cursor: inout MermaidTextCursor, openingLine: Int) throws(MermaidDiagramReadError) -> DiagramLabel {
        let textStart = cursor.position
        var isInsideQuotation = false
        while let byte = cursor.peek(), byte != MermaidByte.newline {
            if byte == MermaidByte.quotationMark { isInsideQuotation.toggle() }
            if byte == MermaidByte.verticalBar, !isInsideQuotation {
                let written = FlowchartTextSyntax.unquoted(cursor.text(from: textStart, to: cursor.position).trimmingCharacters(in: .whitespaces))
                cursor.advance()
                return DiagramLabelDecoder.label(from: written.text, form: written.form)
            }
            cursor.advance()
        }
        throw .invalidSyntax(line: openingLine, problem: .unclosedEdgeLabel)
    }

    private static func arrowhead(forMark mark: UInt8, isSourceEnd: Bool) -> FlowchartArrowhead? {
        switch mark {
        case MermaidByte.greaterThan: isSourceEnd ? nil : .arrow
        case MermaidByte.lessThan: isSourceEnd ? .arrow : nil
        case MermaidByte.letterO: .circle
        case MermaidByte.letterX: .cross
        default: nil
        }
    }

    private static func runLength(of sign: UInt8, in cursor: MermaidTextCursor) -> Int {
        var count = 0
        while cursor.peek(count) == sign { count += 1 }
        return count
    }
}
