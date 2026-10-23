/// Splits an XY chart's text after its keyword into the tokens of Mermaid's XY chart grammar, as Pele's lexer does:
/// a state machine whose states decide what a character starts. In an axis' statement and between a series'
/// brackets a number is one token and `-->` another; elsewhere digits and a minus sign are tokens of a word.
/// Keywords are read without regard to case, and `vertical` and `horizontal` even inside a longer word. A line
/// break directly after an axis or a series ends its statement; one after spaces is skipped with them. `%%` and a
/// character followed by `%%` start a comment that runs to the end of the line. A character no rule reads ends
/// the tokens with an `invalid` one.
struct XYChartLexer {
    private var cursor: MermaidTextCursor
    private var state = State.initial
    private var stack: [State] = []
    private var tokens: [XYChartToken] = []

    private enum State {
        case initial
        /// After `x-axis` or `y-axis`.
        case axis
        /// Inside an x axis' `[ … ]`.
        case axisCategories
        /// After `line` or `bar`.
        case series
        /// Inside a series' `[ … ]`.
        case seriesValues
        /// After a quotation mark.
        case string
        case accessibilityTitle
        case accessibilityDescription
        /// Inside `accDescr { … }`.
        case accessibilityDescriptionBlock
    }

    /// The tokens from the cursor to the end of the text, the last `end`, or `invalid` where a character no rule reads is.
    static func tokens(after cursor: MermaidTextCursor) -> [XYChartToken] {
        var lexer = XYChartLexer(cursor: cursor)
        lexer.readTokens()
        return lexer.tokens
    }

    private init(cursor: MermaidTextCursor) {
        self.cursor = cursor
    }

    private mutating func readTokens() {
        while let byte = cursor.peek() {
            switch state {
            case .string: readString(startingWith: byte)
            case .accessibilityTitle: readLineValue(.accessibilityTitleValue)
            case .accessibilityDescription: readLineValue(.accessibilityDescriptionValue)
            case .accessibilityDescriptionBlock: readDescriptionBlock(startingWith: byte)
            case .initial, .axis, .axisCategories, .series, .seriesValues:
                guard readStatementToken(startingWith: byte) else {
                    emit(.invalid, to: cursor.position)
                    return
                }
            }
        }
        emit(endOfTextKind, to: cursor.position)
        emit(.end, to: cursor.position)
    }

    /// The token the grammar gives for the empty rest of the text in the current state.
    private var endOfTextKind: XYChartTokenKind {
        switch state {
        case .string: .string
        case .accessibilityTitle: .accessibilityTitleValue
        case .accessibilityDescription: .accessibilityDescriptionValue
        case .accessibilityDescriptionBlock: .accessibilityDescriptionBlockValue
        case .initial, .axis, .axisCategories, .series, .seriesValues: .endOfFile
        }
    }

    /// Reads the token, comment or spaces that start at `byte` outside strings and accessibility text, or returns
    /// false for a character no rule reads.
    private mutating func readStatementToken(startingWith byte: UInt8) -> Bool {
        if skipComment(startingWith: byte) { return true }
        if byte == MermaidByte.newline || byte == MermaidByte.carriageReturn {
            readLineBreak(startingWith: byte)
            return true
        }
        if readKeyword(startingWith: byte) || readBracketArrowOrNumber(startingWith: byte) { return true }
        return readTextOrPunctuation(startingWith: byte)
    }

    /// `%%` to the end of its line, or a character followed by `%%` with them: Mermaid's second comment rule takes the
    /// character before the comment with it, a line break included, but not a closing brace.
    private mutating func skipComment(startingWith byte: UInt8) -> Bool {
        if byte == MermaidByte.percent, cursor.peek(1) == MermaidByte.percent {
            cursor.skipToEndOfLine()
            return true
        }
        let length = XYChartCharacter.commentPrefixLength(of: byte)
        guard byte != MermaidByte.closingBrace, length > 0, cursor.peek(length) == MermaidByte.percent,
              cursor.peek(length + 1) == MermaidByte.percent else { return false }
        cursor.advance(by: length)
        cursor.skipToEndOfLine()
        return true
    }

    private mutating func readLineBreak(startingWith byte: UInt8) {
        let isLineFeed = byte == MermaidByte.newline
        if state == .axis || state == .series, isLineFeed || cursor.peek(1) == MermaidByte.newline {
            emit(.newline, to: cursor.position + (isLineFeed ? 1 : 2))
            popState()
            return
        }
        var end = cursor.position + 1
        while end < cursor.bytes.count, cursor.bytes[end] == MermaidByte.newline || cursor.bytes[end] == MermaidByte.carriageReturn { end += 1 }
        emit(.newline, to: end)
    }

    private mutating func readKeyword(startingWith byte: UInt8) -> Bool {
        switch MermaidByte.lowercased(byte) {
        case UInt8(ascii: "t"): return readWordKeyword(Self.titleKeyword, as: .title)
        case UInt8(ascii: "a"): return readAccessibilityKeyword()
        case UInt8(ascii: "x"):
            return readWordKeyword(Self.betaChartKeyword, as: .chartKeyword) || readWordKeyword(Self.chartKeyword, as: .chartKeyword)
                || readWordKeyword(Self.xAxisKeyword, as: .xAxis, entering: .axis)
        case UInt8(ascii: "y"): return readWordKeyword(Self.yAxisKeyword, as: .yAxis, entering: .axis)
        case UInt8(ascii: "v"): return readOrientation(Self.verticalKeyword)
        case UInt8(ascii: "h"): return readOrientation(Self.horizontalKeyword)
        case UInt8(ascii: "l"): return readWordKeyword(Self.lineKeyword, as: .line, entering: .series)
        case UInt8(ascii: "b"): return readWordKeyword(Self.barKeyword, as: .bar, entering: .series)
        default: return false
        }
    }

    /// `keyword`, in any case, when no letter, digit or underscore follows it.
    private mutating func readWordKeyword(_ keyword: [UInt8], as kind: XYChartTokenKind, entering newState: State? = nil) -> Bool {
        guard cursor.hasCaseInsensitivePrefix(keyword), !XYChartCharacter.isWordByte(cursor.peek(keyword.count)) else { return false }
        emit(kind, to: cursor.position + keyword.count)
        if let newState { pushState(newState) }
        return true
    }

    /// `vertical` or `horizontal`, in any case, whatever follows it.
    private mutating func readOrientation(_ keyword: [UInt8]) -> Bool {
        guard cursor.hasCaseInsensitivePrefix(keyword) else { return false }
        emit(.orientation, to: cursor.position + keyword.count)
        return true
    }

    /// `accTitle` or `accDescr`, then spaces and line breaks, then a colon, or a brace after `accDescr`.
    private mutating func readAccessibilityKeyword() -> Bool {
        let isDescription = cursor.hasCaseInsensitivePrefix(Self.accessibilityDescriptionKeyword)
        guard isDescription || cursor.hasCaseInsensitivePrefix(Self.accessibilityTitleKeyword) else { return false }
        let afterSpaces = JavaScriptWhitespace.endOfRun(in: cursor.bytes, from: cursor.position + Self.accessibilityDescriptionKeyword.count)
        let next = afterSpaces < cursor.bytes.count ? cursor.bytes[afterSpaces] : nil
        if next == MermaidByte.colon {
            emit(isDescription ? .accessibilityDescription : .accessibilityTitle,
                 to: JavaScriptWhitespace.endOfRun(in: cursor.bytes, from: afterSpaces + 1))
            pushState(isDescription ? .accessibilityDescription : .accessibilityTitle)
            return true
        }
        guard isDescription, next == MermaidByte.openingBrace else { return false }
        cursor.advance(by: JavaScriptWhitespace.endOfRun(in: cursor.bytes, from: afterSpaces + 1) - cursor.position)
        pushState(.accessibilityDescriptionBlock)
        return true
    }

    private mutating func readBracketArrowOrNumber(startingWith byte: UInt8) -> Bool {
        if byte == MermaidByte.openingBracket {
            if state == .axis { pushState(.axisCategories) } else if state == .series { pushState(.seriesValues) }
            emit(.openingBracket, to: cursor.position + 1)
            return true
        }
        if byte == MermaidByte.closingBracket {
            if state == .seriesValues || state == .axisCategories { popState() }
            emit(.closingBracket, to: cursor.position + 1)
            return true
        }
        if state == .axis, cursor.hasPrefix(Self.arrow) {
            emit(.arrow, to: cursor.position + Self.arrow.count)
            return true
        }
        guard state == .axis || state == .seriesValues, let end = XYChartCharacter.endOfNumber(in: cursor.bytes, from: cursor.position) else {
            return false
        }
        emit(.number, to: end)
        return true
    }

    private mutating func readTextOrPunctuation(startingWith byte: UInt8) -> Bool {
        if byte == MermaidByte.quotationMark {
            cursor.advance()
            pushState(.string)
        } else if MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) {
            let isLetter = MermaidByte.isLetter(byte)
            var end = cursor.position + 1
            while end < cursor.bytes.count, isLetter ? MermaidByte.isLetter(cursor.bytes[end]) : MermaidByte.isDigit(cursor.bytes[end]) { end += 1 }
            emit(isLetter ? .letters : .digits, to: end)
        } else if JavaScriptWhitespace.length(in: cursor.bytes, at: cursor.position) > 0 {
            cursor.advance(by: JavaScriptWhitespace.endOfRun(in: cursor.bytes, from: cursor.position) - cursor.position)
        } else if let kind = Self.punctuation[byte] {
            emit(kind, to: cursor.position + 1)
        } else {
            return false
        }
        return true
    }

    /// The text up to the closing quotation mark or the end, or the closing mark itself.
    private mutating func readString(startingWith byte: UInt8) {
        if byte == MermaidByte.quotationMark {
            cursor.advance()
            popState()
            return
        }
        emit(.string, to: cursor.bytes[cursor.position...].firstIndex(of: MermaidByte.quotationMark) ?? cursor.bytes.count)
    }

    /// The rest of the line after `accTitle:` or `accDescr:`.
    private mutating func readLineValue(_ kind: XYChartTokenKind) {
        emit(kind, to: cursor.bytes[cursor.position...].firstIndex(of: MermaidByte.newline) ?? cursor.bytes.count)
        popState()
    }

    /// The text up to the closing brace or the end, or the closing brace itself.
    private mutating func readDescriptionBlock(startingWith byte: UInt8) {
        if byte == MermaidByte.closingBrace {
            cursor.advance()
            popState()
            return
        }
        emit(.accessibilityDescriptionBlockValue, to: cursor.bytes[cursor.position...].firstIndex(of: MermaidByte.closingBrace) ?? cursor.bytes.count)
    }

    private mutating func emit(_ kind: XYChartTokenKind, to end: Int) {
        tokens.append(XYChartToken(kind: kind, start: cursor.position, end: end, line: cursor.line))
        cursor.advance(by: end - cursor.position)
    }

    private mutating func pushState(_ newState: State) {
        stack.append(state)
        state = newState
    }

    private mutating func popState() {
        if let previous = stack.popLast() { state = previous }
    }

    private static let titleKeyword = Array("title".utf8)
    private static let accessibilityTitleKeyword = Array("acctitle".utf8)
    private static let accessibilityDescriptionKeyword = Array("accdescr".utf8)
    private static let betaChartKeyword = Array("xychart-beta".utf8)
    private static let chartKeyword = Array("xychart".utf8)
    private static let xAxisKeyword = Array("x-axis".utf8)
    private static let yAxisKeyword = Array("y-axis".utf8)
    private static let verticalKeyword = Array("vertical".utf8)
    private static let horizontalKeyword = Array("horizontal".utf8)
    private static let lineKeyword = Array("line".utf8)
    private static let barKeyword = Array("bar".utf8)
    private static let arrow = Array("-->".utf8)
    private static let punctuation: [UInt8: XYChartTokenKind] = [
        UInt8(ascii: ":"): .colon, UInt8(ascii: "+"): .plus, UInt8(ascii: ","): .comma, UInt8(ascii: "="): .equals, UInt8(ascii: "*"): .asterisk,
        UInt8(ascii: "#"): .numberSign, UInt8(ascii: "_"): .underscore, UInt8(ascii: "."): .period, UInt8(ascii: "&"): .ampersand,
        UInt8(ascii: "-"): .minus, UInt8(ascii: ";"): .semicolon,
    ]
}
