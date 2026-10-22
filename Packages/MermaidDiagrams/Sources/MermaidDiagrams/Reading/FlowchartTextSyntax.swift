import Foundation

/// Reads the text written inside a node's brackets or an edge's bars: quoted (`"…"`, which may hold any bracket),
/// a Markdown string (`"`…`"`), or plain up to the first closing text.
enum FlowchartTextSyntax {
    /// Reads text up to the first of `closings` and moves past it. Returns the label and which closing ended it.
    /// - Parameter openingLine: The line of the opening bracket, which an unclosed text is reported on.
    static func readText(_ cursor: inout MermaidTextCursor, closedByAnyOf closings: [[UInt8]],
                         openingLine: Int) throws(MermaidDiagramReadError) -> (DiagramLabel, Int) {
        cursor.skipSpaces()
        let textStart = cursor.position
        if cursor.peek() == MermaidByte.quotationMark {
            cursor.advance()
            while let byte = cursor.peek(), byte != MermaidByte.quotationMark { cursor.advance() }
            guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedQuotation) }
            cursor.advance()
            let written = unquoted(cursor.text(from: textStart, to: cursor.position))
            cursor.skipSpaces()
            guard let closingIndex = closings.firstIndex(where: { closing in cursor.hasPrefix(closing) }) else {
                throw .invalidSyntax(line: cursor.line, problem: cursor.isAtEnd ? .unclosedShape(closingText: closingText(closings))
                                                                                : .unexpectedText(cursor.excerpt()))
            }
            cursor.advance(by: closings[closingIndex].count)
            return (DiagramLabelDecoder.label(from: written.text, form: written.form), closingIndex)
        }
        while !cursor.isAtEnd {
            if let closingIndex = closings.firstIndex(where: { closing in cursor.hasPrefix(closing) }) {
                let text = cursor.trimmedText(from: textStart, to: cursor.position)
                cursor.advance(by: closings[closingIndex].count)
                return (DiagramLabelDecoder.label(from: text, form: .plain), closingIndex)
            }
            cursor.advance()
        }
        throw .invalidSyntax(line: openingLine, problem: .unclosedShape(closingText: closingText(closings)))
    }

    /// Text between quotation marks loses them; a Markdown string (`"`…`"`) loses its backticks too.
    static func unquoted(_ written: String) -> (text: String, form: DiagramLabelDecoder.Form) {
        guard written.count >= 2, written.hasPrefix("\""), written.hasSuffix("\"") else { return (written, .plain) }
        let inside = written.dropFirst().dropLast()
        if inside.count >= 2, inside.hasPrefix("`"), inside.hasSuffix("`") {
            return (String(inside.dropFirst().dropLast()), .markdown)
        }
        return (String(inside), .plain)
    }

    private static func closingText(_ closings: [[UInt8]]) -> String {
        String(decoding: closings.first ?? [], as: UTF8.self)
    }
}
