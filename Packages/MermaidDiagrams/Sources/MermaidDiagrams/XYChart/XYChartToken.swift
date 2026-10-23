/// A token of Mermaid's XY chart grammar (`xychart.jison`): its kind, where its text is in the diagram's bytes, and
/// the line it starts on.
struct XYChartToken {
    let kind: XYChartTokenKind
    let start: Int
    let end: Int
    let line: Int
}

/// The kinds of token Mermaid's XY chart lexer gives, by its grammar's names.
enum XYChartTokenKind: Hashable {
    /// The end of the tokens.
    case end
    /// A character the grammar has no rule for: the tokens stop there.
    case invalid
    case newline
    case title
    case accessibilityTitle
    case accessibilityTitleValue
    case accessibilityDescription
    case accessibilityDescriptionValue
    case accessibilityDescriptionBlockValue
    /// `xychart` or `xychart-beta` again.
    case chartKeyword
    /// `vertical` or `horizontal`.
    case orientation
    case xAxis
    case yAxis
    /// `-->` between the two ends of an axis' range.
    case arrow
    case line
    case bar
    /// A number with an optional sign and fraction, read only in an axis' statement and between a series' brackets.
    case number
    case openingBracket
    case closingBracket
    /// The text between quotation marks.
    case string
    /// A run of ASCII letters.
    case letters
    /// A run of digits where a number is not read.
    case digits
    case colon
    case plus
    case comma
    case equals
    case asterisk
    case numberSign
    case underscore
    case period
    case ampersand
    case minus
    case semicolon
    /// The grammar's end of the text, which may end a statement.
    case endOfFile

    /// Whether the token is part of a word of text that is not quoted: Mermaid joins such tokens without the spaces
    /// between them (`cat2 asdf` is `cat2asdf`).
    var isWordPart: Bool {
        Self.wordParts.contains(self)
    }

    /// Whether the token is text: quoted, or a word part.
    var isText: Bool {
        self == .string || isWordPart
    }

    /// Whether the token may end a statement.
    var endsStatement: Bool {
        self == .newline || self == .semicolon || self == .endOfFile
    }

    private static let wordParts: Set<XYChartTokenKind> = [.ampersand, .digits, .letters, .plus, .equals, .asterisk, .period, .numberSign, .minus,
                                                          .underscore]
}
