import Foundation

/// Reads a Sankey diagram's rows after its `sankey` or `sankey-beta` keyword, as Mermaid's grammar and Pele's parser do,
/// over the tokens of `SankeyLexer` on the text as Mermaid prepares it (`SankeyPreparedText`): a line break after the
/// keyword, then rows of three fields, `source,target,value`, each plain or between quotation marks (where a doubled
/// quotation mark is one), one row per line. A node's name is its field without the spaces at either end.
struct SankeyParser {
    private let text: SankeyPreparedText
    private let tokens: [SankeyLexer.Token]
    private var index = 0
    private var builder: SankeyDiagramBuilder

    private init(text: SankeyPreparedText, limits: MermaidDiagramLimits) {
        self.text = text
        tokens = SankeyLexer.tokens(of: text.bytes)
        builder = SankeyDiagramBuilder(limits: limits)
    }

    /// Reads the Sankey diagram whose keyword ends at the cursor.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> SankeyDiagram {
        var parser = SankeyParser(text: SankeyPreparedText(after: cursor), limits: limits)
        try parser.expect(.newline)
        try parser.readRows()
        return parser.builder.diagram
    }

    private var kind: SankeyLexer.Kind { tokens[index].kind }

    private mutating func readRows() throws(MermaidDiagramReadError) {
        while true {
            let source = try readName()
            try expect(.comma)
            let target = try readName()
            try expect(.comma)
            let value = try readField()
            try builder.addLink(from: source, to: target, value: JavaScriptNumberReading.parseFloat(value))
            guard kind == .newline else { break }
            index += 1
        }
        if kind == .endOfFile { index += 1 }
        guard kind == .end else { throw failure(.unexpectedText(excerpt(at: tokens[index]))) }
    }

    /// A field without the spaces at either end, a doubled quotation mark read as one; an error when a character
    /// Mermaid refuses in a name (a control character, an unpaired surrogate) is there once entity codes are decoded.
    private mutating func readName() throws(MermaidDiagramReadError) -> String {
        let start = tokens[index]
        let name = try readField().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"\"", with: "\"")
        guard !DiagramLabelDecoder.decodingEntities(name).unicodeScalars.contains(where: Self.isRefusedInName) else {
            throw .invalidSyntax(line: text.line(at: start.start), problem: .unexpectedText(excerpt(at: start)))
        }
        return name
    }

    /// Text, or text between quotation marks.
    private mutating func readField() throws(MermaidDiagramReadError) -> String {
        if kind == .text {
            index += 1
            return written(tokens[index - 1])
        }
        guard kind == .quotationMark else { throw failure(.expectedSankeyFields) }
        let opening = tokens[index]
        index += 1
        guard kind == .quotedText else { throw failure(.expectedSankeyFields) }
        let field = written(tokens[index])
        index += 1
        guard kind == .quotationMark else {
            throw kind == .invalid ? failure(.expectedSankeyFields) : .invalidSyntax(line: text.line(at: opening.start), problem: .unclosedQuotation)
        }
        index += 1
        return field
    }

    private mutating func expect(_ expected: SankeyLexer.Kind) throws(MermaidDiagramReadError) {
        guard kind == expected else { throw failure(.expectedSankeyFields) }
        index += 1
    }

    /// The error for the token at the index: `problem`, or the text there when it is a character no rule reads or text
    /// where a line break should be.
    private func failure(_ problem: MermaidSyntaxProblem) -> MermaidDiagramReadError {
        let token = tokens[index]
        let isUnexpected = token.kind == .invalid || (token.kind == .text && index == 0)
        return .invalidSyntax(line: text.line(at: token.start), problem: isUnexpected ? .unexpectedText(excerpt(at: token)) : problem)
    }

    private func written(_ token: SankeyLexer.Token) -> String {
        String(decoding: text.bytes[token.start..<token.end], as: UTF8.self)
    }

    private func excerpt(at token: SankeyLexer.Token) -> String {
        var cursor = MermaidTextCursor(bytes: text.bytes)
        cursor.advance(by: token.start)
        return cursor.excerpt()
    }

    /// The characters XML 1.0 refuses that Mermaid's check of a name finds: controls other than tab, line feed and
    /// carriage return, and U+FFFE and U+FFFF.
    private static func isRefusedInName(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return value < 0x09 || value == 0x0B || value == 0x0C || (0x0E...0x1F).contains(value) || value == 0xFFFE || value == 0xFFFF
    }
}
