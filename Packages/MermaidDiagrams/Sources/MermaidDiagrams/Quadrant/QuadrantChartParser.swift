import Foundation

/// Reads a quadrant chart's statements after its `quadrantChart` keyword from their tokens (`QuadrantChartLexer`), as
/// Mermaid's quadrant grammar does: `title …`, `x-axis low --> high` and `y-axis low --> high` (the high end may be
/// left out; an arrow with nothing after it is drawn after the low end's text), `quadrant-1` to `quadrant-4` and
/// their texts, points (`Name:::class: [x, y] radius: 10, color: #ff3300`), `classDef name styles`, accessibility
/// statements, each ending at a line break, a semicolon or the end of the text. A text is quoted, a Markdown string, or
/// words with the spaces and hyphens between them.
struct QuadrantChartParser {
    private let tokens: [QuadrantChartToken]
    private let bytes: [UInt8]
    private var index = 0
    private var builder: QuadrantChartBuilder

    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> QuadrantChart {
        var parser = QuadrantChartParser(tokens: try QuadrantChartLexer.tokens(after: cursor), bytes: cursor.bytes,
                                         builder: QuadrantChartBuilder(limits: limits))
        try parser.readStatements()
        return parser.builder.chart
    }

    private init(tokens: [QuadrantChartToken], bytes: [UInt8], builder: QuadrantChartBuilder) {
        self.tokens = tokens
        self.bytes = bytes
        self.builder = builder
    }

    private var current: QuadrantChartToken? {
        index < tokens.count ? tokens[index] : nil
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while index < tokens.count {
            while current?.kind == .space { index += 1 }
            guard let token = current else { return }
            try readStatement(startingWith: token)
            guard let end = current else { return }
            guard end.kind == .lineBreak || end.kind == .semicolon else { throw unexpected(end) }
            index += 1
        }
    }

    /// The statement `token` starts; a line break or a semicolon starts none.
    private mutating func readStatement(startingWith token: QuadrantChartToken) throws(MermaidDiagramReadError) {
        if token.kind == .classDefinition {
            try readClassDefinition()
        } else if token.kind == .xAxis || token.kind == .yAxis {
            try readAxis(isHorizontal: token.kind == .xAxis)
        } else if let quadrant = QuadrantChartTokenKind.quadrants.firstIndex(of: token.kind) {
            index += 1
            builder.setQuadrantLabel(at: quadrant, try requiredText(after: token))
        } else if case .text(let title) = token.content, token.kind == .title {
            index += 1
            builder.setTitle(title)
        } else if case .accessibility(let statement) = token.content {
            index += 1
            builder.apply(statement)
        } else if QuadrantChartTokenKind.textStarts.contains(token.kind) {
            try readPoint(startingWith: token)
        }
    }

    /// `x-axis` or `y-axis`, a text, then `-->` and the high end's text; `-->` with nothing after it puts an arrow after
    /// the low end's text, as in Mermaid.
    private mutating func readAxis(isHorizontal: Bool) throws(MermaidDiagramReadError) {
        let keyword = tokens[index]
        index += 1
        var low = try requiredText(after: keyword)
        var high: QuadrantChartText?
        if current?.kind == .axisArrow {
            index += 1
            high = readText()
            if high == nil { low.text += Self.arrowAfterText }
        }
        builder.setAxisLabels(low: low, high: high, isHorizontal: isHorizontal)
    }

    /// A point: its text, its class after `:::`, its coordinates, and the styles after them.
    private mutating func readPoint(startingWith token: QuadrantChartToken) throws(MermaidDiagramReadError) {
        guard let label = readText() else { return }
        var className: String?
        if let classToken = current, classToken.kind == .className, case .text(let name) = classToken.content {
            className = name
            index += 1
        }
        guard let pointToken = current, case .coordinates(let xCoordinate, let yCoordinate) = pointToken.content else {
            throw .invalidSyntax(line: current?.line ?? token.line, problem: .expectedPointCoordinates)
        }
        index += 1
        let styles = current.map { next in QuadrantChartTokenKind.stylePieces.contains(next.kind) } == true ? try readStyles() : []
        try builder.addPoint(QuadrantChartWrittenPoint(label: label, className: className, xCoordinate: xCoordinate, yCoordinate: yCoordinate,
                                                       styles: styles), line: token.line)
    }

    /// `classDef`, one space, the class's name, one space, and its styles.
    private mutating func readClassDefinition() throws(MermaidDiagramReadError) {
        let keyword = tokens[index]
        index += 1
        try expectSpace()
        var name = ""
        while let piece = current, QuadrantChartTokenKind.classNamePieces.contains(piece.kind) {
            name += text(of: piece)
            index += 1
        }
        guard !name.isEmpty else { throw current.map(unexpected) ?? .invalidSyntax(line: keyword.line, problem: .expectedName) }
        try expectSpace()
        try builder.addClass(name, styles: try readStyles(), line: keyword.line)
    }

    /// Styles separated by commas, each made of letters, digits, colons, spaces, `#` and hyphens, without the spaces at
    /// its ends.
    private mutating func readStyles() throws(MermaidDiagramReadError) -> [String] {
        var styles: [String] = []
        while true {
            var style = ""
            while let piece = current, QuadrantChartTokenKind.stylePieces.contains(piece.kind) {
                style += text(of: piece)
                index += 1
            }
            guard !style.isEmpty else { throw .invalidSyntax(line: current?.line ?? tokens[index - 1].line, problem: .expectedPointStyle) }
            styles.append(style.trimmingCharacters(in: .whitespaces))
            guard current?.kind == .comma else { return styles }
            index += 1
        }
    }

    /// A text: a quoted or Markdown string or a word, then words, spaces and hyphens. Nil when none starts here.
    private mutating func readText() -> QuadrantChartText? {
        guard let first = current, QuadrantChartTokenKind.textStarts.contains(first.kind) else { return nil }
        var text = text(of: first)
        index += 1
        while let piece = current, QuadrantChartTokenKind.textContinuations.contains(piece.kind) {
            text += self.text(of: piece)
            index += 1
        }
        return QuadrantChartText(text: text, isMarkdown: first.kind == .markdownString)
    }

    /// The text after `keyword`, which must have one.
    private mutating func requiredText(after keyword: QuadrantChartToken) throws(MermaidDiagramReadError) -> QuadrantChartText {
        guard let text = readText() else { throw .invalidSyntax(line: current?.line ?? keyword.line, problem: .expectedAxisOrQuadrantText) }
        return text
    }

    /// One space or tab, as `classDef` takes one before and after the class's name.
    private mutating func expectSpace() throws(MermaidDiagramReadError) {
        guard let space = current, space.kind == .space else {
            throw current.map(unexpected) ?? .invalidSyntax(line: tokens[index - 1].line, problem: .expectedName)
        }
        index += 1
    }

    /// The text a token stands for: a string's or a class's text, else its bytes as written.
    private func text(of token: QuadrantChartToken) -> String {
        if case .text(let text) = token.content { return text }
        return String(decoding: bytes[token.start..<token.end], as: UTF8.self)
    }

    /// The error of a token where it does not belong: its first characters, after the spaces a keyword takes.
    private func unexpected(_ token: QuadrantChartToken) -> MermaidDiagramReadError {
        var cursor = MermaidTextCursor(bytes: bytes)
        cursor.advance(by: token.start)
        cursor.skipSpaces()
        return .invalidSyntax(line: token.line, problem: .unexpectedText(cursor.excerpt()))
    }

    /// What Mermaid writes after an axis's low end when its arrow has no high end.
    static let arrowAfterText = " ⟶ "
}

/// A text of a quadrant chart as written, and whether it is a Markdown string.
struct QuadrantChartText {
    var text: String
    let isMarkdown: Bool
}

/// A point as its statement writes it, before its coordinates and styles are read.
struct QuadrantChartWrittenPoint {
    let label: QuadrantChartText
    let className: String?
    let xCoordinate: String
    let yCoordinate: String
    let styles: [String]
}
