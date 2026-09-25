import Foundation

/// A problem in a Bases expression. Parse errors carry the character offset where
/// reading stopped; evaluation errors describe the failing operation.
public enum BaseExpressionError: Error, Equatable, Sendable, LocalizedError {
    case syntax(String, position: Int)
    case evaluation(String)

    public var errorDescription: String? {
        switch self {
        case .syntax(let message, let position): "\(message) (at character \(position + 1))"
        case .evaluation(let message): message
        }
    }
}

public enum BaseUnaryOperator: String, Sendable, Hashable {
    case not = "!"
    case negate = "-"
    case plus = "+"
}

public enum BaseBinaryOperator: String, Sendable, Hashable {
    case or = "||"
    case and = "&&"
    case equal = "=="
    case notEqual = "!="
    case less = "<"
    case lessOrEqual = "<="
    case greater = ">"
    case greaterOrEqual = ">="
    case add = "+"
    case subtract = "-"
    case multiply = "*"
    case divide = "/"
    case remainder = "%"

    /// Higher binds tighter.
    var precedence: Int {
        switch self {
        case .or: 1
        case .and: 2
        case .equal, .notEqual: 3
        case .less, .lessOrEqual, .greater, .greaterOrEqual: 4
        case .add, .subtract: 5
        case .multiply, .divide, .remainder: 6
        }
    }
}

/// The syntax tree of a formula or filter.
public indirect enum BaseExpression: Hashable, Sendable {
    case literal(BaseValue)
    /// A bare name: a note property, `file`, `note`, `formula`, `this`, or a variable
    /// such as `value` inside `filter()`.
    case identifier(String)
    case member(BaseExpression, String)
    case subscripted(BaseExpression, BaseExpression)
    case functionCall(String, [BaseExpression])
    case methodCall(BaseExpression, String, [BaseExpression])
    case unary(BaseUnaryOperator, BaseExpression)
    case binary(BaseBinaryOperator, BaseExpression, BaseExpression)
    case listLiteral([BaseExpression])

    public static func parse(_ sourceText: String) throws -> BaseExpression {
        var parser = BaseExpressionParser(tokens: try BaseExpressionTokenizer.tokens(in: sourceText))
        return try parser.parseComplete()
    }
}

// MARK: Tokens

struct BaseToken: Equatable {
    enum Kind: Equatable {
        case number(Double)
        case string(String)
        case identifier(String)
        case regularExpression(pattern: String, flags: String)
        case symbol(String)
        case end
    }
    let kind: Kind
    let position: Int
}

enum BaseExpressionTokenizer {
    /// Longest symbols first so `==` is not read as `=` `=`.
    private static let symbols = ["===", "!==", "==", "!=", "<=", ">=", "&&", "||", "+", "-", "*", "/", "%", "<", ">", "!", "(", ")", "[", "]", ",", ".", "{", "}"]

    static func tokens(in sourceText: String) throws -> [BaseToken] {
        let characters = Array(sourceText)
        var tokens: [BaseToken] = []
        var position = 0

        /// A `/` starts a regular expression only where an operand is expected;
        /// elsewhere it divides.
        func expectsOperand() -> Bool {
            guard let previous = tokens.last else { return true }
            switch previous.kind {
            case .number, .string, .identifier, .regularExpression: return false
            case .symbol(let symbol): return ![")", "]", "}"].contains(symbol)
            case .end: return true
            }
        }

        while position < characters.count {
            let character = characters[position]
            if character.isWhitespace { position += 1; continue }
            let start = position
            if character.isNumber && character.isASCII || (character == "." && position + 1 < characters.count && characters[position + 1].isASCII && characters[position + 1].isNumber && expectsOperand()) {
                position = scanNumber(characters, from: position)
                let text = String(characters[start..<position])
                guard let number = Double(text) else { throw BaseExpressionError.syntax("Invalid number “\(text)”", position: start) }
                tokens.append(BaseToken(kind: .number(number), position: start))
                continue
            }
            if character == "\"" || character == "'" {
                let (text, endPosition) = try scanString(characters, from: position, quote: character)
                tokens.append(BaseToken(kind: .string(text), position: start))
                position = endPosition
                continue
            }
            if character == "/" && expectsOperand() {
                let (pattern, flags, endPosition) = try scanRegularExpression(characters, from: position)
                tokens.append(BaseToken(kind: .regularExpression(pattern: pattern, flags: flags), position: start))
                position = endPosition
                continue
            }
            if character.isLetter || character == "_" || character == "$" {
                while position < characters.count, characters[position].isLetter || characters[position].isNumber || characters[position] == "_" || characters[position] == "$" {
                    position += 1
                }
                tokens.append(BaseToken(kind: .identifier(String(characters[start..<position])), position: start))
                continue
            }
            let remainingText = String(characters[position..<min(characters.count, position + 3)])
            guard let symbol = symbols.first(where: { symbol in remainingText.hasPrefix(symbol) }) else {
                throw BaseExpressionError.syntax("Unexpected character “\(character)”", position: start)
            }
            // The strict operators read as `==` and `!=`. Those compare numbers and dates
            // with their text by value (`1 === "1"` is true); see `BaseEvaluator.isEqual`.
            let normalizedSymbol = symbol == "===" ? "==" : (symbol == "!==" ? "!=" : symbol)
            tokens.append(BaseToken(kind: .symbol(normalizedSymbol), position: start))
            position += symbol.count
        }
        tokens.append(BaseToken(kind: .end, position: characters.count))
        return tokens
    }

    private static func scanNumber(_ characters: [Character], from startPosition: Int) -> Int {
        var position = startPosition
        func isDigit(_ index: Int) -> Bool { index < characters.count && characters[index].isASCII && characters[index].isNumber }
        while isDigit(position) { position += 1 }
        if position < characters.count, characters[position] == ".", isDigit(position + 1) {
            position += 1
            while isDigit(position) { position += 1 }
        }
        if position < characters.count, characters[position] == "e" || characters[position] == "E" {
            var exponentPosition = position + 1
            if exponentPosition < characters.count, characters[exponentPosition] == "+" || characters[exponentPosition] == "-" { exponentPosition += 1 }
            if isDigit(exponentPosition) {
                position = exponentPosition
                while isDigit(position) { position += 1 }
            }
        }
        return position
    }

    private static func scanString(_ characters: [Character], from startPosition: Int, quote: Character) throws -> (String, Int) {
        var position = startPosition + 1
        var text = ""
        while position < characters.count {
            let character = characters[position]
            if character == quote { return (text, position + 1) }
            if character == "\\", position + 1 < characters.count {
                let escaped = characters[position + 1]
                position += 2
                // JavaScript's escapes. A malformed `\x` or `\u` is a syntax error, as in
                // JavaScript, instead of silently becoming different text.
                switch escaped {
                case "n": text.append("\n")
                case "t": text.append("\t")
                case "r": text.append("\r")
                case "b": text.append("\u{8}")
                case "f": text.append("\u{C}")
                case "v": text.append("\u{B}")
                case "0": text.append("\u{0}")
                case "x":
                    guard let scalarValue = hexValue(characters, from: position, digitCount: 2), let scalar = Unicode.Scalar(scalarValue) else {
                        throw BaseExpressionError.syntax("Invalid escape; \\x needs two hexadecimal digits", position: position - 2)
                    }
                    text.unicodeScalars.append(scalar)
                    position += 2
                case "u":
                    let (scalar, endPosition) = try scanUnicodeEscape(characters, from: position)
                    text.unicodeScalars.append(scalar)
                    position = endPosition
                default:
                    // A backslash before a line break continues the text on the next line.
                    if !escaped.isNewline { text.append(escaped) }
                }
                continue
            }
            text.append(character)
            position += 1
        }
        throw BaseExpressionError.syntax("Unterminated text; add the closing \(quote)", position: startPosition)
    }

    /// The value of exactly `digitCount` ASCII hexadecimal digits at `startPosition`.
    /// `UInt32(_:radix:)` alone would also accept a sign, so `\u+041` read as "A".
    private static func hexValue(_ characters: [Character], from startPosition: Int, digitCount: Int) -> UInt32? {
        guard startPosition + digitCount <= characters.count else { return nil }
        let digits = characters[startPosition..<startPosition + digitCount]
        guard digits.allSatisfy({ digit in digit.isASCII && digit.isHexDigit }) else { return nil }
        return UInt32(String(digits), radix: 16)
    }

    /// Reads the part after `\u`: four hexadecimal digits, or one to six in braces
    /// (`\u{1F600}`). A UTF-16 surrogate pair written as two escapes (`\uD83D\uDE00`)
    /// becomes the one character it encodes. A lone surrogate cannot be stored in a Swift
    /// string, so it becomes U+FFFD, the replacement character JavaScript shows for it.
    private static func scanUnicodeEscape(_ characters: [Character], from startPosition: Int) throws -> (Unicode.Scalar, Int) {
        let invalidEscape = BaseExpressionError.syntax("Invalid escape; \\u needs four hexadecimal digits or {…}", position: startPosition - 2)
        if startPosition < characters.count, characters[startPosition] == "{" {
            guard let closingBraceIndex = characters[(startPosition + 1)...].prefix(7).firstIndex(of: "}") else { throw invalidEscape }
            let digitCount = closingBraceIndex - startPosition - 1
            guard (1...6).contains(digitCount), let scalarValue = hexValue(characters, from: startPosition + 1, digitCount: digitCount),
                  let scalar = Unicode.Scalar(scalarValue) else { throw invalidEscape }
            return (scalar, closingBraceIndex + 1)
        }
        guard let codeUnit = hexValue(characters, from: startPosition, digitCount: 4) else { throw invalidEscape }
        let endPosition = startPosition + 4
        if let scalar = Unicode.Scalar(codeUnit) { return (scalar, endPosition) }
        let highSurrogates: ClosedRange<UInt32> = 0xD800...0xDBFF, lowSurrogates: ClosedRange<UInt32> = 0xDC00...0xDFFF
        if highSurrogates.contains(codeUnit), endPosition + 1 < characters.count, characters[endPosition] == "\\", characters[endPosition + 1] == "u",
           let lowCodeUnit = hexValue(characters, from: endPosition + 2, digitCount: 4), lowSurrogates.contains(lowCodeUnit),
           let scalar = Unicode.Scalar(0x10000 + ((codeUnit - 0xD800) << 10) + (lowCodeUnit - 0xDC00)) {
            return (scalar, endPosition + 6)
        }
        return ("\u{FFFD}", endPosition)
    }

    private static func scanRegularExpression(_ characters: [Character], from startPosition: Int) throws -> (String, String, Int) {
        var position = startPosition + 1
        var pattern = ""
        var isInCharacterClass = false
        while position < characters.count {
            let character = characters[position]
            if character == "\\", position + 1 < characters.count {
                pattern.append(character)
                pattern.append(characters[position + 1])
                position += 2
                continue
            }
            if character == "[" { isInCharacterClass = true }
            if character == "]" { isInCharacterClass = false }
            if character == "/" && !isInCharacterClass {
                position += 1
                var flags = ""
                while position < characters.count, "gimsuy".contains(characters[position]) {
                    flags.append(characters[position])
                    position += 1
                }
                return (pattern, flags, position)
            }
            if character == "\n" { break }
            pattern.append(character)
            position += 1
        }
        throw BaseExpressionError.syntax("Unterminated regular expression", position: startPosition)
    }
}

// MARK: Parser

/// Precedence-climbing parser over the token list.
struct BaseExpressionParser {
    private let tokens: [BaseToken]
    private var tokenIndex = 0
    /// Guards against stack exhaustion from pathological input in a file. Bases work runs
    /// on secondary threads with 512 KB stacks, and the limits leave room for unoptimized
    /// builds, whose frames are several times larger than release ones.
    ///
    /// `nestingDepth` bounds the parser's own recursion (parentheses, arguments, unary
    /// operators); a debug build uses about 4 KB of stack per level.
    private var nestingDepth = 0
    static let maximumNestingDepth = 64

    /// The tree is bounded separately, because evaluation, `dependsOnCurrentRow`, hashing
    /// and freeing the indirect enum recurse once per level of the finished tree, and a
    /// flat chain such as `1+1+…+1` or `a.b().b()…` is parsed by a loop yet nests one level
    /// per term. See `stackCost(of:)`.
    static let maximumStackCost = 100

    /// A parsed subtree with its stack cost, so each new node can check the cost of the
    /// tree it forms without walking it.
    private struct ParsedExpression {
        let expression: BaseExpression
        let stackCost: Int
    }

    /// The evaluation stack one tree level takes, in units of a binary operator level
    /// (about 2 KB in a debug build, measured on a 512 KB thread). A function call such as
    /// `if()` takes about four units and a method call up to about three. A tree's cost is
    /// its height with each level weighted this way.
    private static func stackCost(of expression: BaseExpression) -> Int {
        switch expression {
        case .functionCall: 4
        case .methodCall: 3
        default: 1
        }
    }

    init(tokens: [BaseToken]) { self.tokens = tokens }

    private var current: BaseToken { tokens[tokenIndex] }

    private mutating func advance() { if tokenIndex < tokens.count - 1 { tokenIndex += 1 } }

    private func isSymbol(_ symbol: String) -> Bool { current.kind == .symbol(symbol) }

    private mutating func expect(_ symbol: String) throws {
        guard isSymbol(symbol) else { throw BaseExpressionError.syntax("Expected “\(symbol)”", position: current.position) }
        advance()
    }

    private var nestedTooDeeply: BaseExpressionError {
        BaseExpressionError.syntax("The expression is nested too deeply", position: current.position)
    }

    /// Wraps `expression`, whose direct children are `children`, checking the stack cost.
    private func node(_ expression: BaseExpression, children: [ParsedExpression]) throws -> ParsedExpression {
        let stackCost = Self.stackCost(of: expression) + (children.map(\.stackCost).max() ?? 0)
        guard stackCost < Self.maximumStackCost else { throw nestedTooDeeply }
        return ParsedExpression(expression: expression, stackCost: stackCost)
    }

    private func leaf(_ expression: BaseExpression) -> ParsedExpression {
        ParsedExpression(expression: expression, stackCost: 1)
    }

    mutating func parseComplete() throws -> BaseExpression {
        if current.kind == .end { throw BaseExpressionError.syntax("The expression is empty", position: 0) }
        let parsed = try parseExpression(minimumPrecedence: 1)
        guard current.kind == .end else { throw BaseExpressionError.syntax("Unexpected “\(describe(current))”", position: current.position) }
        return parsed.expression
    }

    private func describe(_ token: BaseToken) -> String {
        switch token.kind {
        case .number(let number): BaseValue.formatted(number)
        case .string(let text): "\"\(text)\""
        case .identifier(let name): name
        case .regularExpression(let pattern, let flags): "/\(pattern)/\(flags)"
        case .symbol(let symbol): symbol
        case .end: "end of expression"
        }
    }

    private mutating func parseExpression(minimumPrecedence: Int) throws -> ParsedExpression {
        nestingDepth += 1
        defer { nestingDepth -= 1 }
        guard nestingDepth < Self.maximumNestingDepth else { throw nestedTooDeeply }
        var left = try parseUnary()
        while case .symbol(let symbol) = current.kind, let binaryOperator = BaseBinaryOperator(rawValue: symbol), binaryOperator.precedence >= minimumPrecedence {
            advance()
            let right = try parseExpression(minimumPrecedence: binaryOperator.precedence + 1)
            left = try node(.binary(binaryOperator, left.expression, right.expression), children: [left, right])
        }
        return left
    }

    private mutating func parseUnary() throws -> ParsedExpression {
        if case .symbol(let symbol) = current.kind, let unaryOperator = BaseUnaryOperator(rawValue: symbol) {
            advance()
            nestingDepth += 1
            defer { nestingDepth -= 1 }
            guard nestingDepth < Self.maximumNestingDepth else { throw nestedTooDeeply }
            let operand = try parseUnary()
            if unaryOperator == .negate, case .literal(.number(let number)) = operand.expression { return leaf(.literal(.number(-number))) }
            return try node(.unary(unaryOperator, operand.expression), children: [operand])
        }
        return try parsePostfix(parsePrimary())
    }

    private mutating func parsePostfix(_ base: ParsedExpression) throws -> ParsedExpression {
        var parsed = base
        while true {
            if isSymbol(".") {
                advance()
                guard case .identifier(let name) = current.kind else {
                    throw BaseExpressionError.syntax("Expected a name after “.”", position: current.position)
                }
                advance()
                if isSymbol("(") {
                    let arguments = try parseArguments()
                    parsed = try node(.methodCall(parsed.expression, name, arguments.map(\.expression)), children: [parsed] + arguments)
                } else {
                    parsed = try node(.member(parsed.expression, name), children: [parsed])
                }
            } else if isSymbol("[") {
                advance()
                let subscriptExpression = try parseExpression(minimumPrecedence: 1)
                try expect("]")
                parsed = try node(.subscripted(parsed.expression, subscriptExpression.expression), children: [parsed, subscriptExpression])
            } else {
                return parsed
            }
        }
    }

    private mutating func parseArguments() throws -> [ParsedExpression] {
        try expect("(")
        var arguments: [ParsedExpression] = []
        if isSymbol(")") { advance(); return arguments }
        while true {
            arguments.append(try parseExpression(minimumPrecedence: 1))
            if isSymbol(",") { advance(); continue }
            try expect(")")
            return arguments
        }
    }

    private mutating func parsePrimary() throws -> ParsedExpression {
        let token = current
        switch token.kind {
        case .number(let number):
            advance()
            return leaf(.literal(.number(number)))
        case .string(let text):
            advance()
            return leaf(.literal(.string(text)))
        case .regularExpression(let pattern, let flags):
            advance()
            return leaf(.literal(.regularExpression(BaseRegularExpression(pattern: pattern, flags: flags))))
        case .identifier(let name):
            advance()
            switch name {
            case "true": return leaf(.literal(.boolean(true)))
            case "false": return leaf(.literal(.boolean(false)))
            case "null", "undefined": return leaf(.literal(.null))
            default: break
            }
            if isSymbol("(") {
                let arguments = try parseArguments()
                return try node(.functionCall(name, arguments.map(\.expression)), children: arguments)
            }
            return leaf(.identifier(name))
        case .symbol("("):
            advance()
            let parsed = try parseExpression(minimumPrecedence: 1)
            try expect(")")
            return parsed
        case .symbol("["):
            advance()
            var elements: [ParsedExpression] = []
            if isSymbol("]") { advance(); return leaf(.listLiteral([])) }
            while true {
                elements.append(try parseExpression(minimumPrecedence: 1))
                if isSymbol(",") {
                    advance()
                    if isSymbol("]") { advance(); return try node(.listLiteral(elements.map(\.expression)), children: elements) }
                    continue
                }
                try expect("]")
                return try node(.listLiteral(elements.map(\.expression)), children: elements)
            }
        case .symbol("{"):
            // Only the empty object literal is meaningful (`{}.isEmpty()` in Obsidian's docs).
            advance()
            try expect("}")
            return leaf(.literal(.object(BaseObject(entries: []))))
        case .end:
            throw BaseExpressionError.syntax("The expression ends too early", position: token.position)
        case .symbol(let symbol):
            throw BaseExpressionError.syntax("Unexpected “\(symbol)”", position: token.position)
        }
    }
}

// MARK: Inspection

extension BaseExpression {
    /// Whether evaluating this expression can read the row's own file or properties.
    /// Expressions that only use literals and `this` can be evaluated once per query.
    public var dependsOnCurrentRow: Bool {
        switch self {
        case .literal: return false
        case .identifier(let name): return name != "this"
        case .member(let base, _): return base.dependsOnCurrentRow
        case .subscripted(let base, let subscriptExpression): return base.dependsOnCurrentRow || subscriptExpression.dependsOnCurrentRow
        case .functionCall(_, let arguments): return arguments.contains { argument in argument.dependsOnCurrentRow }
        case .methodCall(let receiver, _, let arguments): return receiver.dependsOnCurrentRow || arguments.contains { argument in argument.dependsOnCurrentRow }
        case .unary(_, let operand): return operand.dependsOnCurrentRow
        case .binary(_, let leftExpression, let rightExpression): return leftExpression.dependsOnCurrentRow || rightExpression.dependsOnCurrentRow
        case .listLiteral(let elements): return elements.contains { element in element.dependsOnCurrentRow }
        }
    }
}
