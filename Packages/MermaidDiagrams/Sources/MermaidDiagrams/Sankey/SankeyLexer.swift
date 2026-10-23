/// Splits a Sankey diagram's prepared text into the tokens of Mermaid's Sankey grammar (`sankey.jison`, RFC 4180's
/// CSV), as Pele's lexer does: line breaks, commas, quotation marks, and text between them. Outside quotation marks,
/// text is the characters of RFC 4180's `TEXTDATA` extended to Unicode (no control character, quotation mark or
/// comma); between them, commas, line breaks and doubled quotation marks too. A character outside these ends the
/// tokens with an `invalid` one, as it would be matched as empty text forever.
struct SankeyLexer {
    struct Token {
        let kind: Kind
        let start: Int
        let end: Int
    }

    enum Kind: Equatable {
        case newline
        case comma
        case quotationMark
        /// Text outside quotation marks.
        case text
        /// Text between quotation marks, doubled quotation marks included.
        case quotedText
        /// The grammar's end of the text.
        case endOfFile
        case end
        /// A character no rule reads: the tokens stop there.
        case invalid
    }

    private let bytes: [UInt8]
    private var position = 0
    private var isQuoted = false
    private var tokens: [Token] = []

    /// The tokens of the prepared text, which starts after the diagram's keyword.
    static func tokens(of bytes: [UInt8]) -> [Token] {
        var lexer = SankeyLexer(bytes: bytes)
        lexer.readTokens()
        return lexer.tokens
    }

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    private mutating func readTokens() {
        while position < bytes.count {
            let isRead = isQuoted ? readQuoted() : readUnquoted()
            guard isRead else {
                emit(.invalid, to: position)
                return
            }
        }
        emit(isQuoted ? .quotedText : .endOfFile, to: position)
        emit(.end, to: position)
    }

    private mutating func readUnquoted() -> Bool {
        let byte = bytes[position]
        if byte == MermaidByte.newline {
            emit(.newline, to: position + 1)
        } else if byte == MermaidByte.comma {
            emit(.comma, to: position + 1)
        } else if byte == MermaidByte.quotationMark {
            isQuoted = true
            emit(.quotationMark, to: position + 1)
        } else {
            var end = position
            while case let length = SankeyCharacter.textDataLength(in: bytes, at: end), length > 0 { end += length }
            guard end > position else { return false }
            emit(.text, to: end)
        }
        return true
    }

    /// The closing quotation mark, or the text up to it: a doubled quotation mark is text.
    private mutating func readQuoted() -> Bool {
        if bytes[position] == MermaidByte.quotationMark, !isQuotationMark(at: position + 1) {
            isQuoted = false
            emit(.quotationMark, to: position + 1)
            return true
        }
        var end = position
        while end < bytes.count {
            let byte = bytes[end]
            if byte == MermaidByte.comma || byte == MermaidByte.newline || byte == MermaidByte.carriageReturn {
                end += 1
            } else if byte == MermaidByte.quotationMark, isQuotationMark(at: end + 1) {
                end += 2
            } else if case let length = SankeyCharacter.textDataLength(in: bytes, at: end), length > 0 {
                end += length
            } else {
                break
            }
        }
        guard end > position else { return false }
        emit(.quotedText, to: end)
        return true
    }

    private func isQuotationMark(at index: Int) -> Bool {
        index < bytes.count && bytes[index] == MermaidByte.quotationMark
    }

    private mutating func emit(_ kind: Kind, to end: Int) {
        tokens.append(Token(kind: kind, start: position, end: end))
        position = end
    }
}
