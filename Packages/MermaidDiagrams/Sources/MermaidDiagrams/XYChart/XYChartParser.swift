/// Reads an XY chart's statements after its `xychart` or `xychart-beta` keyword, as Mermaid's grammar and Pele's
/// parser do, over the tokens of `XYChartLexer`: an orientation after the keyword, then `title`, `x-axis` (a title,
/// then categories in brackets or a range `start --> end`), `y-axis` (a title, then a range), `line` and `bar` (a
/// title, then numbers in brackets, each with an optional quoted label), `accTitle` and `accDescr`. Statements may
/// follow one another on a line; line breaks and semicolons between them are skipped. Text that is not quoted is the
/// run of word tokens joined without their spaces, as Mermaid joins them.
struct XYChartParser {
    private let tokens: [XYChartToken]
    private let bytes: [UInt8]
    private var index = 0
    private var builder: XYChartBuilder

    private init(tokens: [XYChartToken], bytes: [UInt8], limits: MermaidDiagramLimits) {
        self.tokens = tokens
        self.bytes = bytes
        builder = XYChartBuilder(limits: limits)
    }

    /// Reads the XY chart whose keyword ends at the cursor.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> XYChart {
        var parser = XYChartParser(tokens: XYChartLexer.tokens(after: cursor), bytes: cursor.bytes, limits: limits)
        parser.readKeywordLines()
        try parser.readStatements()
        return parser.builder.chart
    }

    private var kind: XYChartTokenKind { tokens[index].kind }

    /// The orientation after the keyword, and the keyword again with its own orientation, before any statement.
    private mutating func readKeywordLines() {
        readOrientation()
        while true {
            if kind.endsStatement {
                index += 1
            } else if kind == .chartKeyword {
                index += 1
                readOrientation()
            } else {
                return
            }
        }
    }

    private mutating func readOrientation() {
        guard kind == .orientation else { return }
        builder.setOrientation(text(of: tokens[index]))
        index += 1
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while kind != .end {
            let statement = tokens[index]
            index += 1
            switch statement.kind {
            case .title: builder.setTitle(try readText(orElse: .expectedChartText))
            case .xAxis: try readXAxis()
            case .yAxis: try readYAxis()
            case .line: try readSeries(.line)
            case .bar: try readSeries(.bar)
            case .accessibilityTitle: builder.setAccessibilityTitle(readValue())
            case .accessibilityDescription: builder.setAccessibilityDescription(readValue())
            case .accessibilityDescriptionBlockValue: builder.setAccessibilityDescription(text(of: statement))
            case .end, .invalid, .newline, .accessibilityTitleValue, .accessibilityDescriptionValue, .chartKeyword, .orientation, .arrow, .number,
                 .openingBracket, .closingBracket, .string, .letters, .digits, .colon, .plus, .comma, .equals, .asterisk, .numberSign, .underscore,
                 .period, .ampersand, .minus, .semicolon, .endOfFile:
                index -= 1
                throw failure(.unexpectedText(excerpt(at: statement)))
            }
            while kind.endsStatement { index += 1 }
        }
    }

    /// `x-axis`, then an optional title, then categories in brackets or a range; with neither, the title alone.
    private mutating func readXAxis() throws(MermaidDiagramReadError) {
        let title = kind.isText ? try readText(orElse: .expectedChartText) : nil
        if kind == .openingBracket {
            var categories: [String] = []
            repeat {
                index += 1
                categories.append(try readText(orElse: .expectedCategories))
            } while kind == .comma
            try expect(.closingBracket, orElse: .expectedCategories)
            try builder.setXAxisCategories(categories)
        } else if kind == .number || title == nil {
            let range = try readRange()
            builder.setXAxisRange(start: range.start, end: range.end)
        }
        builder.setXAxisTitle(title ?? "")
    }

    /// `y-axis`, then an optional title, then a range; a range is needed without a title.
    private mutating func readYAxis() throws(MermaidDiagramReadError) {
        let title = kind.isText ? try readText(orElse: .expectedChartText) : nil
        if kind == .number || title == nil {
            let range = try readRange()
            builder.setYAxisRange(start: range.start, end: range.end)
        }
        builder.setYAxisTitle(title ?? "")
    }

    /// `start --> end`.
    private mutating func readRange() throws(MermaidDiagramReadError) -> (start: Double, end: Double) {
        let start = try readNumber(orElse: .expectedAxisRange)
        try expect(.arrow, orElse: .expectedAxisRange)
        return (start, try readNumber(orElse: .expectedAxisRange))
    }

    /// `line` or `bar`, an optional title, then `[` numbers, each with an optional quoted label, separated by commas `]`.
    private mutating func readSeries(_ seriesKind: XYChartSeriesKind) throws(MermaidDiagramReadError) {
        let title = kind == .openingBracket ? "" : try readText(orElse: .expectedSeriesValues)
        try expect(.openingBracket, orElse: .expectedSeriesValues)
        var points: [(value: Double, label: String)] = []
        while true {
            let value = try readNumber(orElse: .expectedSeriesValues)
            var label = ""
            if kind == .string {
                label = text(of: tokens[index])
                index += 1
            }
            points.append((value, label))
            guard kind == .comma else { break }
            index += 1
        }
        try expect(.closingBracket, orElse: .expectedSeriesValues)
        try builder.addSeries(seriesKind, title: title, points: points)
    }

    /// Quoted text, or word tokens joined without the spaces between them.
    private mutating func readText(orElse problem: MermaidSyntaxProblem) throws(MermaidDiagramReadError) -> String {
        guard kind.isText else { throw failure(problem) }
        let first = tokens[index]
        index += 1
        var written = text(of: first)
        guard first.kind != .string else { return written }
        while kind.isWordPart {
            written += text(of: tokens[index])
            index += 1
        }
        return written
    }

    /// A number as JavaScript's `Number` reads its text: a sign, digits and a fraction; digits past what a double
    /// holds give infinity.
    private mutating func readNumber(orElse problem: MermaidSyntaxProblem) throws(MermaidDiagramReadError) -> Double {
        guard kind == .number, let number = Double(text(of: tokens[index])) else { throw failure(problem) }
        index += 1
        return number
    }

    /// The value the lexer gives after `accTitle:` or `accDescr:`.
    private mutating func readValue() -> String {
        let value = text(of: tokens[index])
        index += 1
        return value
    }

    private mutating func expect(_ expected: XYChartTokenKind, orElse problem: MermaidSyntaxProblem) throws(MermaidDiagramReadError) {
        guard kind == expected else { throw failure(problem) }
        index += 1
    }

    /// The error for the token at the index: `problem`, or the text there when it is a character no rule reads.
    private func failure(_ problem: MermaidSyntaxProblem) -> MermaidDiagramReadError {
        let token = tokens[index]
        return .invalidSyntax(line: token.line, problem: token.kind == .invalid ? .unexpectedText(excerpt(at: token)) : problem)
    }

    private func text(of token: XYChartToken) -> String {
        String(decoding: bytes[token.start..<token.end], as: UTF8.self)
    }

    private func excerpt(at token: XYChartToken) -> String {
        var cursor = MermaidTextCursor(bytes: bytes)
        cursor.advance(by: token.start)
        return cursor.excerpt()
    }
}
