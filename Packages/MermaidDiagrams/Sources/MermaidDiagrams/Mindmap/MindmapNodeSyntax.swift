import Foundation

/// What one line of a mindmap says about a node: its identifier, its text and its shape.
struct MindmapNodeDefinition {
    let identifier: String
    let label: DiagramLabel
    let shape: MindmapNodeShape
}

/// Reads a mindmap node as Mermaid's mindmap grammar does: an identifier, delimiters around its text, or both
/// (`id[text]`). Text runs to the first closing delimiter and may cross lines; between quotation marks (`"…"`) or as
/// a Markdown string (`"`…`"`) it may hold delimiters. Any opening delimiter pairs with any closing one, and the pair
/// gives the shape. Every label is read as Markdown, as Pele reads a mindmap's.
enum MindmapNodeSyntax {
    /// Reads the node at the cursor, which is past the line's indentation.
    static func readNode(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> MindmapNodeDefinition {
        var identifier: String?
        if openingDelimiter(at: cursor) == nil {
            let start = cursor.position
            while let byte = cursor.peek(), !endsIdentifier(byte) { cursor.advance() }
            guard cursor.position > start else { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
            identifier = cursor.trimmedText(from: start, to: cursor.position)
        }
        guard let opening = openingDelimiter(at: cursor) else {
            let text = identifier ?? ""
            return MindmapNodeDefinition(identifier: text, label: DiagramLabelDecoder.label(from: text, form: .markdown), shape: .plain)
        }
        let openingLine = cursor.line
        cursor.advance(by: opening.utf8.count)
        let (written, form) = try readText(&cursor, opening: opening, openingLine: openingLine)
        let closing = try readClosingDelimiter(&cursor, opening: opening, openingLine: openingLine)
        let label = DiagramLabelDecoder.label(from: written, form: form)
        return MindmapNodeDefinition(identifier: identifier ?? written.trimmingCharacters(in: .whitespacesAndNewlines), label: label,
                                     shape: shape(opening: opening, closing: closing))
    }

    /// The shape Mermaid gives a pair of delimiters: the opening one decides, except that `(` closed by anything but
    /// `)` is a cloud.
    static func shape(opening: String, closing: String) -> MindmapNodeShape {
        switch opening {
        case "[": .rectangle
        case "(": closing == ")" ? .roundedRectangle : .cloud
        case "((": .circle
        case ")": .cloud
        case "))": .bang
        case "{{": .hexagon
        default: .plain
        }
    }

    /// The delimiter that opens a node's text at the cursor, longest first, or nil.
    private static func openingDelimiter(at cursor: MermaidTextCursor) -> String? {
        guard let byte = cursor.peek() else { return nil }
        let next = cursor.peek(1)
        switch byte {
        case MermaidByte.hyphen: return next == closingParenthesis ? "-)" : nil
        case openingParenthesis: return next == MermaidByte.hyphen ? "(-" : next == openingParenthesis ? "((" : "("
        case closingParenthesis: return next == closingParenthesis ? "))" : ")"
        case MermaidByte.openingBrace: return next == MermaidByte.openingBrace ? "{{" : nil
        case MermaidByte.openingBracket: return "["
        default: return nil
        }
    }

    /// An identifier runs to a parenthesis, an opening bracket, a brace or the end of the line, as Mermaid's does.
    private static func endsIdentifier(_ byte: UInt8) -> Bool {
        switch byte {
        case openingParenthesis, closingParenthesis, MermaidByte.openingBracket, MermaidByte.openingBrace, MermaidByte.closingBrace,
             MermaidByte.newline, MermaidByte.carriageReturn: true
        default: false
        }
    }

    /// The text inside the delimiters, and how it was written. The cursor is left on the closing delimiter.
    private static func readText(_ cursor: inout MermaidTextCursor, opening: String,
                                 openingLine: Int) throws(MermaidDiagramReadError) -> (String, DiagramLabelDecoder.Form) {
        if cursor.peek() == MermaidByte.quotationMark {
            let isMarkdown = cursor.peek(1) == MermaidByte.graveAccent
            cursor.advance(by: isMarkdown ? 2 : 1)
            let start = cursor.position
            while let byte = cursor.peek(), byte != MermaidByte.quotationMark, !(isMarkdown && byte == MermaidByte.graveAccent) { cursor.advance() }
            guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedQuotation) }
            let text = cursor.text(from: start, to: cursor.position)
            if isMarkdown {
                guard cursor.hasPrefix(markdownStringEnd) else { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
                cursor.advance(by: markdownStringEnd.count)
            } else {
                cursor.advance()
            }
            return (text, .markdown)
        }
        let start = cursor.position
        while let byte = cursor.peek(), !closesText(byte) { cursor.advance() }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedShape(closingText: expectedClosing(for: opening))) }
        guard cursor.position > start else { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
        return (cursor.text(from: start, to: cursor.position), .markdown)
    }

    /// Text that is not quoted ends at a parenthesis, a closing bracket or a closing brace.
    private static func closesText(_ byte: UInt8) -> Bool {
        byte == openingParenthesis || byte == closingParenthesis || byte == MermaidByte.closingBracket || byte == MermaidByte.closingBrace
    }

    /// Reads the delimiter that closes the text and returns it.
    private static func readClosingDelimiter(_ cursor: inout MermaidTextCursor, opening: String,
                                             openingLine: Int) throws(MermaidDiagramReadError) -> String {
        guard let byte = cursor.peek() else {
            throw .invalidSyntax(line: openingLine, problem: .unclosedShape(closingText: expectedClosing(for: opening)))
        }
        let next = cursor.peek(1)
        let closing: String?
        switch byte {
        case closingParenthesis: closing = next == closingParenthesis ? "))" : ")"
        case openingParenthesis: closing = next == openingParenthesis ? "((" : next == MermaidByte.hyphen ? "(-" : "("
        case MermaidByte.closingBracket: closing = "]"
        case MermaidByte.closingBrace: closing = next == MermaidByte.closingBrace ? "}}" : nil
        case MermaidByte.hyphen: closing = next == closingParenthesis ? "-)" : nil
        default: closing = nil
        }
        guard let closing else { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
        cursor.advance(by: closing.utf8.count)
        return closing
    }

    /// The delimiter that closes `opening` in the shape it starts, for an error that names what is missing.
    private static func expectedClosing(for opening: String) -> String {
        switch opening {
        case "[": "]"
        case "(": ")"
        case "((": "))"
        case ")": "("
        case "))": "(("
        case "{{": "}}"
        case "(-": "-)"
        default: "(-"
        }
    }

    private static let openingParenthesis = UInt8(ascii: "(")
    private static let closingParenthesis = UInt8(ascii: ")")
    private static let markdownStringEnd = Array("`\"".utf8)
}
