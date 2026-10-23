/// A piece of a quadrant chart's text, as Mermaid's quadrant grammar cuts it: what it is, what it holds, where it starts
/// and ends in the diagram's UTF-8 bytes, and the line it starts on.
struct QuadrantChartToken: Equatable {
    let kind: QuadrantChartTokenKind
    let content: QuadrantChartTokenContent
    let start: Int
    let end: Int
    let line: Int
}

/// What a token holds besides its bytes.
enum QuadrantChartTokenContent: Equatable {
    case none
    /// A title's text, a quoted or Markdown string's text, or a class's name.
    case text(String)
    case accessibility(MermaidAccessibilityStatement)
    /// A point's coordinates, as written.
    case coordinates(xCoordinate: String, yCoordinate: String)
}

/// What a piece of a quadrant chart's text is. Keywords, the axis arrow and a point's start take the spaces around
/// them; other text is cut into runs of letters, of digits and of characters beyond ASCII, and single characters.
enum QuadrantChartTokenKind: Hashable {
    /// One or more line breaks or carriage returns.
    case lineBreak
    /// `title` and the rest of its line, which is the title.
    case title
    /// `accTitle: …`, `accDescr: …` or `accDescr { … }`.
    case accessibility
    case xAxis
    case yAxis
    /// `-->`: two or more hyphens and `>`, between an axis's two texts.
    case axisArrow
    case quadrant1
    case quadrant2
    case quadrant3
    case quadrant4
    /// `quadrantChart` again, which no statement takes.
    case chartKeyword
    case classDefinition
    /// Text in quotation marks.
    case string
    /// A Markdown string, between "` and `".
    case markdownString
    /// `:::` and a class's name.
    case className
    /// `: [x, y]`.
    case point
    case letters
    /// Characters beyond ASCII.
    case otherCharacters
    case digits
    case colon
    case comma
    case hyphen
    case numberSign
    /// A space, a tab, a vertical tab or a form feed.
    case space
    case semicolon
    case ampersand
    case asterisk
    /// `+`, `=`, `_`, `.`, `!`, `$`, `%`, `'`, `` ` ``, `?`, `\` or `/`.
    case otherPunctuation

    /// Mermaid's `WORD` tokens: what a text may start with besides a string, and holds after it.
    static let wordPieces: Set<QuadrantChartTokenKind> = [.otherPunctuation, .ampersand, .asterisk, .digits, .letters, .comma, .numberSign,
                                                           .otherCharacters]
    /// What a text may start with.
    static let textStarts = wordPieces.union([.string, .markdownString])
    /// What a text holds after its first piece.
    static let textContinuations = wordPieces.union([.space, .hyphen])
    /// What a class's name after `classDef` is made of.
    static let classNamePieces: Set<QuadrantChartTokenKind> = [.letters, .digits, .hyphen, .comma, .colon, .ampersand, .numberSign, .asterisk,
                                                                .otherCharacters]
    /// What a style (`stroke-width: 10px`) is made of.
    static let stylePieces: Set<QuadrantChartTokenKind> = [.letters, .digits, .colon, .space, .numberSign, .hyphen]
    /// The quadrant keywords, quadrant 1 first.
    static let quadrants: [QuadrantChartTokenKind] = [.quadrant1, .quadrant2, .quadrant3, .quadrant4]
}
