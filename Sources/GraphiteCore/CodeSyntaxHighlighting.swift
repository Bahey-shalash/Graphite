import Foundation
import Synchronization

/// What a piece of code is, which decides the color it is drawn in.
public enum CodeTokenKind: String, CaseIterable, Sendable {
    case keyword
    case typeName
    /// A function or macro being called or declared, or an assembly label.
    case function
    case string
    case number
    /// A named value: `true`, `nullptr`, `None`, an all-capitals constant, a markup entity.
    case constant
    case comment
    /// A preprocessor or assembler directive: `#include`, `` `define ``, `.section`.
    case preprocessor
    /// An attribute, annotation or decorator: `@objc`, `#[derive(Debug)]`, `clk'event`.
    case attribute
    /// A key: a JSON or YAML key, a CSS property, a quoted SQL name.
    case property
    /// A variable written with a sigil, or a register: `$HOME`, `%rax`, `x0`.
    case variable
}

/// A run of code of one kind. Text between tokens is plain code.
public struct CodeToken: Equatable, Sendable {
    /// In UTF-16 units of the text the token was found in.
    public let range: NSRange
    public let kind: CodeTokenKind

    public init(range: NSRange, kind: CodeTokenKind) {
        self.range = range
        self.kind = kind
    }
}

/// The construct a line of code ends inside, which the next line continues: a block
/// comment, a string that spans lines, or a markup tag whose attributes go on.
public enum CodeLineState: Hashable, Sendable {
    case normal
    case blockComment(ruleIndex: Int, depth: Int)
    case string(ruleIndex: Int)
    case markupTag

    /// The state as one integer, to keep beside a line of text; see `init(storedValue:)`.
    public var storedValue: Int {
        switch self {
        case .normal: 0
        case .markupTag: 1
        case .string(let ruleIndex): 2 | (ruleIndex << 2)
        case .blockComment(let ruleIndex, let depth): 3 | (ruleIndex << 2) | (depth << 10)
        }
    }

    public init?(storedValue: Int) {
        guard storedValue >= 0 else { return nil }
        let ruleIndex = (storedValue >> 2) & 0xFF
        switch storedValue & 3 {
        case 0: self = .normal
        case 1: self = .markupTag
        case 2: self = .string(ruleIndex: ruleIndex)
        default: self = .blockComment(ruleIndex: ruleIndex, depth: storedValue >> 10)
        }
    }
}

/// Splits code into tokens, line by line, carrying a `CodeLineState` from one line to
/// the next, so an editor can tokenize only the lines it restyles once it knows the state
/// they start in. Pure Swift over UTF-16 units: no regular expressions, and in a pass
/// that only follows the state, no strings are built.
public struct CodeLineHighlighter: Sendable {
    public let language: CodeLanguage
    /// The construct the next line starts inside.
    public private(set) var state: CodeLineState

    public init(language: CodeLanguage, state: CodeLineState = .normal) {
        self.language = language
        self.state = state
    }

    /// The tokens of `units[lineRange]`, a line without its line break, with ranges in
    /// `units`. The state moves past the line.
    public mutating func tokens(inLine lineRange: Range<Int>, of units: [UInt16]) -> [CodeToken] {
        scan(lineRange, of: units, collectsTokens: true)
    }

    /// Moves the state past `units[lineRange]` without making tokens.
    public mutating func advance(pastLine lineRange: Range<Int>, of units: [UInt16]) {
        _ = scan(lineRange, of: units, collectsTokens: false)
    }

    private mutating func scan(_ lineRange: Range<Int>, of units: [UInt16], collectsTokens: Bool) -> [CodeToken] {
        let clampedRange = max(0, lineRange.lowerBound)..<min(units.count, max(lineRange.lowerBound, lineRange.upperBound))
        let language = language
        let startState = state
        let (tokens, endState) = units.withUnsafeBufferPointer { buffer in
            var scanner = CodeLineScanner(language: language, units: buffer, state: startState, collectsTokens: collectsTokens)
            scanner.scanLine(clampedRange.lowerBound, clampedRange.upperBound)
            return (scanner.tokens, scanner.state)
        }
        state = endState
        return tokens
    }
}

/// Highlights whole code blocks, as reading view shows them.
public enum CodeSyntaxHighlighter {
    /// The language a fenced code block's info text names (```` ```cpp ````, ```` ```C++ ````,
    /// ```` ```py title="x" ````), or nil for one Graphite does not highlight.
    public static func language(forFenceInfo info: String) -> CodeLanguage? {
        CodeLanguage.named(NotePreviewDocument.codeBlockLanguage(ofFenceInfo: info.trimmingCharacters(in: .whitespaces)))
    }

    /// The tokens of `code`, with ranges in its UTF-16 units. Kept for the code blocks
    /// shown most recently, so a block scrolled back into view is not tokenized again.
    public static func tokens(in code: String, language: CodeLanguage) -> [CodeToken] {
        let key = CachedTokensKey(languageName: language.name, code: code)
        if let cachedTokens = cachedTokens.withLock({ cache in cache.tokens(for: key) }) { return cachedTokens }
        let tokens = uncachedTokens(in: code, language: language)
        cachedTokens.withLock { cache in cache.store(tokens, for: key) }
        return tokens
    }

    /// The tokens of `code`, without the cache.
    public static func uncachedTokens(in code: String, language: CodeLanguage) -> [CodeToken] {
        let units = Array(code.utf16)
        var highlighter = CodeLineHighlighter(language: language)
        var tokens: [CodeToken] = []
        for lineRange in lineRanges(in: units) {
            tokens.append(contentsOf: highlighter.tokens(inLine: lineRange, of: units))
        }
        return tokens
    }

    /// The lines of `units`, each without its line break: CommonMark's "\n", "\r\n" and "\r".
    public static func lineRanges(in units: [UInt16]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var lineStart = 0
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit == CodeUnits.lineFeed || unit == CodeUnits.carriageReturn {
                ranges.append(lineStart..<index)
                if unit == CodeUnits.carriageReturn, index + 1 < units.count, units[index + 1] == CodeUnits.lineFeed { index += 1 }
                lineStart = index + 1
            }
            index += 1
        }
        ranges.append(lineStart..<units.count)
        return ranges
    }

    private struct CachedTokensKey: Hashable, Sendable {
        let languageName: String
        let code: String
    }

    /// The most recently tokenized blocks, up to a total length, oldest dropped first.
    private struct TokenCache: Sendable {
        /// About 2 MB of code: many notes' worth of code blocks, or a few very long ones.
        static let maximumCachedUnits = 1_000_000
        private var tokensByKey: [CachedTokensKey: [CodeToken]] = [:]
        private var insertionOrder: [CachedTokensKey] = []
        private var cachedUnits = 0

        func tokens(for key: CachedTokensKey) -> [CodeToken]? { tokensByKey[key] }

        mutating func store(_ tokens: [CodeToken], for key: CachedTokensKey) {
            let length = key.code.utf16.count
            guard length <= Self.maximumCachedUnits, tokensByKey[key] == nil else { return }
            while cachedUnits + length > Self.maximumCachedUnits, !insertionOrder.isEmpty {
                let oldestKey = insertionOrder.removeFirst()
                tokensByKey[oldestKey] = nil
                cachedUnits -= oldestKey.code.utf16.count
            }
            tokensByKey[key] = tokens
            insertionOrder.append(key)
            cachedUnits += length
        }
    }

    private static let cachedTokens = Mutex(TokenCache())
}

/// UTF-16 units the scanner tests for.
enum CodeUnits {
    static let lineFeed = UInt16(UInt8(ascii: "\n"))
    static let carriageReturn = UInt16(UInt8(ascii: "\r"))
    static let space = UInt16(UInt8(ascii: " "))
    static let tab = UInt16(UInt8(ascii: "\t"))
    static let backslash = UInt16(UInt8(ascii: "\\"))
    static let underscore = UInt16(UInt8(ascii: "_"))
    static let dot = UInt16(UInt8(ascii: "."))
    static let colon = UInt16(UInt8(ascii: ":"))
    static let semicolon = UInt16(UInt8(ascii: ";"))
    static let comma = UInt16(UInt8(ascii: ","))
    static let hash = UInt16(UInt8(ascii: "#"))
    static let at = UInt16(UInt8(ascii: "@"))
    static let dollar = UInt16(UInt8(ascii: "$"))
    static let percent = UInt16(UInt8(ascii: "%"))
    static let backtick = UInt16(UInt8(ascii: "`"))
    static let tilde = UInt16(UInt8(ascii: "~"))
    static let singleQuote = UInt16(UInt8(ascii: "'"))
    static let doubleQuote = UInt16(UInt8(ascii: "\""))
    static let openingParenthesis = UInt16(UInt8(ascii: "("))
    static let closingParenthesis = UInt16(UInt8(ascii: ")"))
    static let openingBracket = UInt16(UInt8(ascii: "["))
    static let closingBracket = UInt16(UInt8(ascii: "]"))
    static let openingBrace = UInt16(UInt8(ascii: "{"))
    static let closingBrace = UInt16(UInt8(ascii: "}"))
    static let lessThan = UInt16(UInt8(ascii: "<"))
    static let greaterThan = UInt16(UInt8(ascii: ">"))
    static let equals = UInt16(UInt8(ascii: "="))
    static let exclamation = UInt16(UInt8(ascii: "!"))
    static let question = UInt16(UInt8(ascii: "?"))
    static let asterisk = UInt16(UInt8(ascii: "*"))
    static let ampersand = UInt16(UInt8(ascii: "&"))
    static let plus = UInt16(UInt8(ascii: "+"))
    static let minus = UInt16(UInt8(ascii: "-"))
    static let slash = UInt16(UInt8(ascii: "/"))

    static func isDigit(_ unit: UInt16) -> Bool { unit >= 48 && unit <= 57 }
    static func isHexadecimalDigit(_ unit: UInt16) -> Bool { isDigit(unit) || (unit >= 65 && unit <= 70) || (unit >= 97 && unit <= 102) }
    static func isASCIILetter(_ unit: UInt16) -> Bool { (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122) }
    static func isUppercaseASCIILetter(_ unit: UInt16) -> Bool { unit >= 65 && unit <= 90 }
    static func isLowercaseASCIILetter(_ unit: UInt16) -> Bool { unit >= 97 && unit <= 122 }
    static func isSpace(_ unit: UInt16) -> Bool { unit == space || unit == tab || unit == 0x0C || unit == 0xA0 }
}

/// One pass over one line. Ranges are offsets in `units`.
private struct CodeLineScanner {
    let language: CodeLanguage
    let units: UnsafeBufferPointer<UInt16>
    var state: CodeLineState
    let collectsTokens: Bool
    private(set) var tokens: [CodeToken] = []

    init(language: CodeLanguage, units: UnsafeBufferPointer<UInt16>, state: CodeLineState, collectsTokens: Bool) {
        self.language = language
        self.units = units
        self.state = state
        self.collectsTokens = collectsTokens
    }

    private var features: CodeLanguage.Features { language.features }

    // MARK: Line

    mutating func scanLine(_ lineStart: Int, _ lineEnd: Int) {
        switch language.syntax {
        case .markdown: scanMarkdownLine(lineStart, lineEnd)
        case .markup: scanMarkupLine(lineStart, lineEnd)
        case .general: scanGeneralLine(lineStart, lineEnd)
        }
    }

    private mutating func emit(_ start: Int, _ end: Int, _ kind: CodeTokenKind) {
        guard collectsTokens, end > start else { return }
        if let lastToken = tokens.last, lastToken.kind == kind, NSMaxRange(lastToken.range) == start {
            tokens[tokens.count - 1] = CodeToken(range: NSRange(location: lastToken.range.location, length: end - lastToken.range.location), kind: kind)
        } else {
            tokens.append(CodeToken(range: NSRange(location: start, length: end - start), kind: kind))
        }
    }

    /// Continues a block comment or string the line starts inside. Returns where the rest
    /// of the line starts.
    private mutating func continueOpenConstruct(_ lineStart: Int, _ lineEnd: Int) -> Int {
        switch state {
        case .normal, .markupTag:
            return lineStart
        case .blockComment(let ruleIndex, let depth):
            guard ruleIndex < language.blockComments.count else { state = .normal; return lineStart }
            let (end, remainingDepth) = scanBlockComment(language.blockComments[ruleIndex], from: lineStart, depth: depth, lineEnd: lineEnd)
            emit(lineStart, end, .comment)
            state = remainingDepth.map { depthLeft in .blockComment(ruleIndex: ruleIndex, depth: depthLeft) } ?? .normal
            return end
        case .string(let ruleIndex):
            guard ruleIndex < language.strings.count else { state = .normal; return lineStart }
            let rule = language.strings[ruleIndex]
            let (end, isClosed) = scanStringBody(rule, from: lineStart, lineEnd: lineEnd, usesEscapes: rule.usesBackslashEscapes)
            emit(lineStart, end, rule.kind)
            state = isClosed ? .normal : .string(ruleIndex: ruleIndex)
            return end
        }
    }

    private mutating func scanGeneralLine(_ lineStart: Int, _ lineEnd: Int) {
        var index = continueOpenConstruct(lineStart, lineEnd)
        guard index < lineEnd || state != .normal else { return }
        /// The last unit that is not a space before `index`, or 0.
        var previousUnit: UInt16 = index > lineStart ? units[index - 1] : 0
        var previousWasIdentifier = false
        var isFirstTokenOfLine = index == lineStart
        /// The kind a declaration keyword gives the next identifier: `def name`, `class Name`.
        var declaredKind: CodeTokenKind?
        if features.contains(.yamlKeys), isFirstTokenOfLine { index = scanYAMLKey(lineStart, lineEnd) }

        while index < lineEnd {
            let unit = units[index]
            if CodeUnits.isSpace(unit) { index += 1; continue }
            let tokenStart = index
            var isIdentifier = false
            defer {
                if index > tokenStart {
                    previousUnit = units[index - 1]
                    previousWasIdentifier = isIdentifier
                    isFirstTokenOfLine = false
                }
            }

            if features.contains(.assemblyLines), unit == CodeUnits.hash || unit == CodeUnits.dollar,
               index + 1 < lineEnd, CodeUnits.isDigit(units[index + 1]) || units[index + 1] == CodeUnits.minus {
                // An immediate: `#4` on ARM, `$4` in AT&T syntax.
                index = scanNumber(from: index + 1, lineEnd: lineEnd)
                emit(tokenStart, index, .number)
                continue
            }
            if let ruleIndex = blockCommentRuleIndex(at: index, lineEnd: lineEnd, isFirstTokenOfLine: isFirstTokenOfLine) {
                let rule = language.blockComments[ruleIndex]
                let (end, remainingDepth) = scanBlockComment(rule, from: index + rule.opening.count, depth: 1, lineEnd: lineEnd)
                emit(tokenStart, end, .comment)
                if let remainingDepth { state = .blockComment(ruleIndex: ruleIndex, depth: remainingDepth) }
                index = end
                continue
            }
            if startsLineComment(at: index, lineEnd: lineEnd, lineStart: lineStart) {
                emit(tokenStart, lineEnd, .comment)
                index = lineEnd
                continue
            }
            if features.contains(.transposeQuote), unit == CodeUnits.singleQuote,
               previousWasIdentifier || [CodeUnits.closingParenthesis, CodeUnits.closingBracket, CodeUnits.closingBrace, CodeUnits.dot, CodeUnits.singleQuote].contains(previousUnit),
               tokenStart > lineStart, !CodeUnits.isSpace(units[tokenStart - 1]) {
                // MATLAB's transpose, not a string.
                index += 1
                continue
            }
            if features.contains(.vhdlNumbers) || features.contains(.characterLiteralsOnly) || features.contains(.verilogNumbers), unit == CodeUnits.singleQuote {
                index = scanSingleQuote(at: index, lineEnd: lineEnd, previousUnit: previousUnit, previousWasIdentifier: previousWasIdentifier)
                continue
            }
            if let ruleIndex = stringRuleIndex(at: index, lineEnd: lineEnd) {
                index = scanString(ruleIndex: ruleIndex, tokenStart: tokenStart, openingStart: index, lineEnd: lineEnd)
                continue
            }
            let isSignedCSSNumber = features.contains(.cssRules) && unit == CodeUnits.minus && index + 1 < lineEnd && CodeUnits.isDigit(units[index + 1])
            if CodeUnits.isDigit(unit) || isSignedCSSNumber || (unit == CodeUnits.dot && index + 1 < lineEnd && CodeUnits.isDigit(units[index + 1]) && !previousWasIdentifier) {
                index = scanNumber(from: index, lineEnd: lineEnd)
                emit(tokenStart, index, .number)
                continue
            }
            if isIdentifierStart(unit) {
                isIdentifier = true
                index = scanIdentifierToken(tokenStart, lineStart: lineStart, lineEnd: lineEnd, previousUnit: previousUnit,
                                            isFirstTokenOfLine: isFirstTokenOfLine, declaredKind: &declaredKind)
                continue
            }
            // The `=` of MATLAB's `function y = scaled(x)` keeps the declaration waiting for its name.
            if unit != CodeUnits.equals { declaredKind = nil }
            index = scanSigil(at: index, lineStart: lineStart, lineEnd: lineEnd, isFirstTokenOfLine: isFirstTokenOfLine)
        }
    }

    // MARK: Identifiers

    private func isIdentifierStart(_ unit: UInt16) -> Bool {
        CodeUnits.isASCIILetter(unit) || unit == CodeUnits.underscore || unit >= 0x80 || language.identifierExtraUnits.contains(unit)
    }

    private func isIdentifierPart(_ unit: UInt16) -> Bool {
        isIdentifierStart(unit) || CodeUnits.isDigit(unit)
    }

    private func scanIdentifier(from start: Int, lineEnd: Int) -> Int {
        var index = start
        while index < lineEnd, isIdentifierPart(units[index]) { index += 1 }
        return index
    }

    private func word(_ start: Int, _ end: Int) -> String {
        let text = String(decoding: UnsafeBufferPointer(rebasing: units[start..<end]), as: UTF16.self)
        return language.ignoresCase ? text.lowercased() : text
    }

    /// The first unit after `index` that is not a space, or 0 at the end of the line.
    private func nextVisibleUnit(from index: Int, lineEnd: Int) -> (unit: UInt16, index: Int) {
        var position = index
        while position < lineEnd, CodeUnits.isSpace(units[position]) { position += 1 }
        return position < lineEnd ? (units[position], position) : (0, lineEnd)
    }

    private mutating func scanIdentifierToken(_ start: Int, lineStart: Int, lineEnd: Int, previousUnit: UInt16, isFirstTokenOfLine: Bool,
                                              declaredKind: inout CodeTokenKind?) -> Int {
        let end = scanIdentifier(from: start, lineEnd: lineEnd)
        // A string prefix: `r"…"`, `f'…'`, `b"…"`, `u8"…"`.
        if end < lineEnd, !language.stringPrefixes.isEmpty, let ruleIndex = stringRuleIndex(at: end, lineEnd: lineEnd),
           language.stringPrefixes.contains(String(decoding: UnsafeBufferPointer(rebasing: units[start..<end]), as: UTF16.self).lowercased()) {
            declaredKind = nil
            return scanString(ruleIndex: ruleIndex, tokenStart: start, openingStart: end, lineEnd: lineEnd)
        }
        // A VHDL bit string: `x"FF"`, `b"0101"`, `ux"0F"`.
        if features.contains(.vhdlNumbers), end < lineEnd, units[end] == CodeUnits.doubleQuote, end - start <= 2 {
            let prefix = word(start, end)
            if ["b", "o", "x", "d", "ub", "uo", "ux", "sb", "so", "sx"].contains(prefix) {
                let (stringEnd, _) = scanStringBody(CodeLanguage.StringRule(opening: "\"", closing: "\"", doubledClosingEscapes: true),
                                                    from: end + 1, lineEnd: lineEnd, usesEscapes: false)
                emit(start, stringEnd, .number)
                declaredKind = nil
                return stringEnd
            }
        }
        guard collectsTokens else { return end }
        let next = nextVisibleUnit(from: end, lineEnd: lineEnd)
        let text = word(start, end)
        let isMember = previousUnit == CodeUnits.dot && start > lineStart && units[start - 1] == CodeUnits.dot
        let pendingKind = declaredKind
        declaredKind = nil

        if features.contains(.assemblyLines), isFirstTokenOfLine {
            emit(start, end, next.unit == CodeUnits.colon ? .function : .keyword)
            return end
        }
        if features.contains(.cssRules) {
            // `--background-primary: …` declares a custom property; `var(--background-primary)` reads one.
            if text.hasPrefix("--") {
                emit(start, end, next.unit == CodeUnits.colon ? .property : .variable)
                return end
            }
            // `color: red;` but not the selector `a:hover {`.
            if next.unit == CodeUnits.colon, !(end..<lineEnd).contains(where: { position in units[position] == CodeUnits.openingBrace }) {
                emit(start, end, .property)
                return end
            }
        }
        if !isMember {
            if language.keywords.contains(text) {
                if language.functionDeclarationKeywords.contains(text) { declaredKind = .function }
                if language.typeDeclarationKeywords.contains(text) { declaredKind = .typeName }
                emit(start, end, .keyword)
                return end
            }
            if language.constants.contains(text) { emit(start, end, .constant); return end }
            if language.typeNames.contains(text) { emit(start, end, .typeName); return end }
            if language.variableNames.contains(text) { emit(start, end, .variable); return end }
        }
        if let pendingKind {
            // MATLAB's `function y = scaled(x)` names its result before the function.
            if pendingKind == .function, next.unit == CodeUnits.equals, next.index + 1 >= lineEnd || units[next.index + 1] != CodeUnits.equals {
                declaredKind = pendingKind
                return end
            }
            emit(start, end, pendingKind)
            return end
        }
        if features.contains(.macroBang), next.unit == CodeUnits.exclamation, next.index == end,
           end + 1 >= lineEnd || units[end + 1] != CodeUnits.equals {
            emit(start, end + 1, .function)
            return end + 1
        }
        if features.contains(.marksFunctionCalls), next.unit == CodeUnits.openingParenthesis {
            // `Point(1, 2)` and `new Map()` make a value of a type; `MAX(a, b)` is a macro.
            let isTypeName = features.contains(.capitalizedIdentifiersAreTypes) && CodeUnits.isUppercaseASCIILetter(units[start]) && !isAllCapitals(start, end)
            emit(start, end, isTypeName ? .typeName : .function)
            return end
        }
        if !isMember, language.builtinFunctions.contains(text) {
            emit(start, end, .function)
            return end
        }
        if features.contains(.yamlValues) { return end }
        let firstUnit = units[start]
        if features.contains(.uppercaseIdentifiersAreConstants), end - start > 1, isAllCapitals(start, end) {
            emit(start, end, .constant)
            return end
        }
        if features.contains(.capitalizedIdentifiersAreTypes), CodeUnits.isUppercaseASCIILetter(firstUnit) {
            emit(start, end, .typeName)
            return end
        }
        if features.contains(.underscoreTypeSuffix), end - start > 2, units[end - 2] == CodeUnits.underscore, units[end - 1] == UInt16(UInt8(ascii: "t")) {
            emit(start, end, .typeName)
        }
        return end
    }

    /// Whether the identifier has letters and all of them are capitals: `MAX_SIZE`, `EOF`.
    private func isAllCapitals(_ start: Int, _ end: Int) -> Bool {
        var hasLetter = false
        for index in start..<end {
            let unit = units[index]
            if CodeUnits.isLowercaseASCIILetter(unit) || unit >= 0x80 { return false }
            if CodeUnits.isUppercaseASCIILetter(unit) { hasLetter = true }
        }
        return hasLetter
    }

    // MARK: Comments

    private func matches(_ pattern: [UInt16], at index: Int, lineEnd: Int) -> Bool {
        guard !pattern.isEmpty, index + pattern.count <= lineEnd else { return false }
        for offset in 0..<pattern.count where units[index + offset] != pattern[offset] { return false }
        return true
    }

    private func blockCommentRuleIndex(at index: Int, lineEnd: Int, isFirstTokenOfLine: Bool) -> Int? {
        for (ruleIndex, rule) in language.blockComments.enumerated() where matches(rule.opening, at: index, lineEnd: lineEnd) {
            if rule.opensOnlyAloneOnLine {
                guard isFirstTokenOfLine, nextVisibleUnit(from: index + rule.opening.count, lineEnd: lineEnd).unit == 0 else { continue }
            }
            return ruleIndex
        }
        return nil
    }

    /// Scans to the end of a block comment, counting nested openings where the language
    /// nests them. Returns where the scan stopped and the depth still open, nil when closed.
    private func scanBlockComment(_ rule: CodeLanguage.BlockCommentRule, from start: Int, depth: Int, lineEnd: Int) -> (end: Int, remainingDepth: Int?) {
        var index = start
        var depth = depth
        if rule.opensOnlyAloneOnLine {
            // `%{ … %}` and `=begin … =end` close only on a line of their own.
            let first = nextVisibleUnit(from: start, lineEnd: lineEnd)
            if matches(rule.closing, at: first.index, lineEnd: lineEnd) { return (lineEnd, nil) }
            return (lineEnd, depth)
        }
        while index < lineEnd {
            if matches(rule.closing, at: index, lineEnd: lineEnd) {
                index += rule.closing.count
                depth -= 1
                if depth == 0 { return (index, nil) }
            } else if rule.nests, matches(rule.opening, at: index, lineEnd: lineEnd) {
                index += rule.opening.count
                depth += 1
            } else {
                index += 1
            }
        }
        return (lineEnd, depth)
    }

    private func startsLineComment(at index: Int, lineEnd: Int, lineStart: Int) -> Bool {
        for prefix in language.lineCommentPrefixes where matches(prefix, at: index, lineEnd: lineEnd) {
            // In a shell or YAML, `#` starts a comment only as a word of its own: `a#b` is one word.
            if prefix == [CodeUnits.hash], features.contains(.hashCommentsAfterSpace), index > lineStart, !CodeUnits.isSpace(units[index - 1]) { continue }
            return true
        }
        return false
    }

    // MARK: Strings

    private func stringRuleIndex(at index: Int, lineEnd: Int) -> Int? {
        for (ruleIndex, rule) in language.strings.enumerated() where matches(rule.opening, at: index, lineEnd: lineEnd) { return ruleIndex }
        return nil
    }

    /// Scans a string from its prefix or opening delimiter. Returns where the scan stopped.
    private mutating func scanString(ruleIndex: Int, tokenStart: Int, openingStart: Int, lineEnd: Int) -> Int {
        let rule = language.strings[ruleIndex]
        let isRaw = tokenStart < openingStart && units[tokenStart..<openingStart].contains { unit in unit == UInt16(UInt8(ascii: "r")) || unit == UInt16(UInt8(ascii: "R")) }
        let (end, isClosed) = scanStringBody(rule, from: openingStart + rule.opening.count, lineEnd: lineEnd, usesEscapes: rule.usesBackslashEscapes && !isRaw)
        var kind = rule.kind
        if features.contains(.keysBeforeColon), nextVisibleUnit(from: end, lineEnd: lineEnd).unit == CodeUnits.colon { kind = .property }
        emit(tokenStart, end, kind)
        if !isClosed, rule.spansLines { state = .string(ruleIndex: ruleIndex) }
        return end
    }

    /// Scans a string's text and closing delimiter. A string that does not span lines and
    /// is not closed ends with the line.
    private func scanStringBody(_ rule: CodeLanguage.StringRule, from start: Int, lineEnd: Int, usesEscapes: Bool) -> (end: Int, isClosed: Bool) {
        var index = start
        while index < lineEnd {
            let unit = units[index]
            if usesEscapes, unit == CodeUnits.backslash {
                index += 2
                continue
            }
            if matches(rule.closing, at: index, lineEnd: lineEnd) {
                if rule.doubledClosingEscapes, matches(rule.closing, at: index + rule.closing.count, lineEnd: lineEnd) {
                    index += 2 * rule.closing.count
                    continue
                }
                return (index + rule.closing.count, true)
            }
            index += 1
        }
        return (lineEnd, false)
    }

    /// A single quote in a language where it is not always a string: a character literal
    /// (`'1'`), a VHDL attribute (`clk'event`), a Verilog sized number (`8'hFF`, `'0`) or a
    /// Rust lifetime (`'a`).
    private mutating func scanSingleQuote(at index: Int, lineEnd: Int, previousUnit: UInt16, previousWasIdentifier: Bool) -> Int {
        if features.contains(.verilogNumbers) {
            let baseIndex = index + 1 < lineEnd && (units[index + 1] == UInt16(UInt8(ascii: "s")) || units[index + 1] == UInt16(UInt8(ascii: "S"))) ? index + 2 : index + 1
            if baseIndex < lineEnd, "bBoOdDhH".utf16.contains(units[baseIndex]) || "01xXzZ".utf16.contains(units[baseIndex]) {
                var end = baseIndex + 1
                while end < lineEnd, CodeUnits.isHexadecimalDigit(units[end]) || "_xXzZ?".utf16.contains(units[end]) { end += 1 }
                emit(index, end, .number)
                return end
            }
            return index + 1
        }
        if features.contains(.vhdlNumbers), previousWasIdentifier || previousUnit == CodeUnits.closingParenthesis,
           index + 1 < lineEnd, isIdentifierStart(units[index + 1]) {
            let end = scanIdentifier(from: index + 1, lineEnd: lineEnd)
            // `'1'` right after a name is still a character (`x'1'` is rare); `clk'event` is an attribute.
            if !(end - index == 2 && end < lineEnd && units[end] == CodeUnits.singleQuote) {
                emit(index, end, .attribute)
                return end
            }
        }
        if index + 2 < lineEnd, units[index + 1] != CodeUnits.backslash, units[index + 2] == CodeUnits.singleQuote {
            emit(index, index + 3, .string)
            return index + 3
        }
        if index + 1 < lineEnd, units[index + 1] == CodeUnits.backslash {
            var end = index + 2
            while end < lineEnd, end - index < 12, units[end] != CodeUnits.singleQuote { end += 1 }
            if end < lineEnd {
                emit(index, end + 1, .string)
                return end + 1
            }
        }
        if features.contains(.macroBang), index + 1 < lineEnd, isIdentifierStart(units[index + 1]) {
            // A Rust lifetime or loop label.
            let end = scanIdentifier(from: index + 1, lineEnd: lineEnd)
            emit(index, end, .attribute)
            return end
        }
        return index + 1
    }

    // MARK: Numbers

    private func scanNumber(from start: Int, lineEnd: Int) -> Int {
        var index = start
        if index < lineEnd, units[index] == CodeUnits.minus { index += 1 }
        if index + 1 < lineEnd, units[index] == UInt16(UInt8(ascii: "0")), "xXbBoO".utf16.contains(units[index + 1]) {
            index += 2
            while index < lineEnd, CodeUnits.isHexadecimalDigit(units[index]) || units[index] == CodeUnits.underscore || units[index] == CodeUnits.singleQuote && features.contains(.digitSeparatorQuotes) { index += 1 }
        } else {
            while index < lineEnd, CodeUnits.isDigit(units[index]) || units[index] == CodeUnits.underscore
                    || (units[index] == CodeUnits.singleQuote && features.contains(.digitSeparatorQuotes) && index + 1 < lineEnd && CodeUnits.isDigit(units[index + 1])) { index += 1 }
            if features.contains(.verilogNumbers), index < lineEnd, units[index] == CodeUnits.singleQuote {
                // `8'hFF`: the size, then the base and digits.
                var end = index + 1
                if end < lineEnd, units[end] == UInt16(UInt8(ascii: "s")) || units[end] == UInt16(UInt8(ascii: "S")) { end += 1 }
                if end < lineEnd, "bBoOdDhH".utf16.contains(units[end]) {
                    end += 1
                    while end < lineEnd, CodeUnits.isHexadecimalDigit(units[end]) || "_xXzZ?".utf16.contains(units[end]) { end += 1 }
                    return end
                }
            }
            if features.contains(.vhdlNumbers), index < lineEnd, units[index] == CodeUnits.hash {
                // `16#FF#`: a base, then digits between number signs.
                var end = index + 1
                while end < lineEnd, CodeUnits.isHexadecimalDigit(units[end]) || units[end] == CodeUnits.underscore || units[end] == CodeUnits.dot { end += 1 }
                if end < lineEnd, units[end] == CodeUnits.hash { return end + 1 }
            }
            if index + 1 < lineEnd, units[index] == CodeUnits.dot, CodeUnits.isDigit(units[index + 1]) {
                index += 1
                while index < lineEnd, CodeUnits.isDigit(units[index]) || units[index] == CodeUnits.underscore { index += 1 }
            }
            if index < lineEnd, units[index] == UInt16(UInt8(ascii: "e")) || units[index] == UInt16(UInt8(ascii: "E")) {
                var exponentIndex = index + 1
                if exponentIndex < lineEnd, units[exponentIndex] == CodeUnits.plus || units[exponentIndex] == CodeUnits.minus { exponentIndex += 1 }
                if exponentIndex < lineEnd, CodeUnits.isDigit(units[exponentIndex]) {
                    index = exponentIndex
                    while index < lineEnd, CodeUnits.isDigit(units[index]) { index += 1 }
                }
            }
        }
        // Suffixes and units: `10u`, `1.5f`, `42i64`, `12pt`, `10ns`.
        while index < lineEnd, CodeUnits.isASCIILetter(units[index]) || CodeUnits.isDigit(units[index]) { index += 1 }
        return index
    }

    // MARK: Sigils

    /// Directives, attributes and variables that start with a symbol. Returns where the
    /// scan stopped, past the symbol when it starts nothing.
    private mutating func scanSigil(at index: Int, lineStart: Int, lineEnd: Int, isFirstTokenOfLine: Bool) -> Int {
        let unit = units[index]
        let nextUnit = index + 1 < lineEnd ? units[index + 1] : 0
        if features.contains(.sigilStringPrefixes), unit == CodeUnits.at || unit == CodeUnits.dollar {
            var openingStart = index + 1
            while openingStart < lineEnd, units[openingStart] == CodeUnits.at || units[openingStart] == CodeUnits.dollar { openingStart += 1 }
            if let ruleIndex = stringRuleIndex(at: openingStart, lineEnd: lineEnd) {
                return scanString(ruleIndex: ruleIndex, tokenStart: index, openingStart: openingStart, lineEnd: lineEnd)
            }
        }
        switch unit {
        case CodeUnits.hash:
            if features.contains(.lineStartHashDirectives), isFirstTokenOfLine {
                var end = index + 1
                while end < lineEnd, CodeUnits.isSpace(units[end]) { end += 1 }
                let directiveStart = end
                end = scanIdentifier(from: end, lineEnd: lineEnd)
                emit(index, end, .preprocessor)
                let directive = word(directiveStart, end)
                let next = nextVisibleUnit(from: end, lineEnd: lineEnd)
                if ["include", "import", "include_next"].contains(directive), next.unit == CodeUnits.lessThan {
                    var closing = next.index + 1
                    while closing < lineEnd, units[closing] != CodeUnits.greaterThan { closing += 1 }
                    let stringEnd = min(closing + 1, lineEnd)
                    emit(next.index, stringEnd, .string)
                    return stringEnd
                }
                return end
            }
            if features.contains(.bracketAttributes), nextUnit == CodeUnits.openingBracket || (nextUnit == CodeUnits.exclamation && index + 2 < lineEnd && units[index + 2] == CodeUnits.openingBracket) {
                var end = index + 1
                var depth = 0
                while end < lineEnd {
                    if units[end] == CodeUnits.openingBracket { depth += 1 }
                    if units[end] == CodeUnits.closingBracket {
                        depth -= 1
                        if depth == 0 { end += 1; break }
                    }
                    end += 1
                }
                emit(index, end, .attribute)
                return end
            }
            if features.contains(.hashDirectives), isIdentifierStart(nextUnit) {
                let end = scanIdentifier(from: index + 1, lineEnd: lineEnd)
                emit(index, end, .preprocessor)
                return end
            }
            if features.contains(.cssRules), CodeUnits.isHexadecimalDigit(nextUnit) {
                // A hex color, `#1e1e2e`; an id selector (`#main`) has letters past `f`.
                let end = scanIdentifier(from: index + 1, lineEnd: lineEnd)
                if (index + 1..<end).allSatisfy({ position in CodeUnits.isHexadecimalDigit(units[position]) }) {
                    emit(index, end, .number)
                    return end
                }
            }
        case CodeUnits.at:
            if features.contains(.atVariables), isIdentifierStart(nextUnit) || nextUnit == CodeUnits.at {
                let end = scanIdentifier(from: nextUnit == CodeUnits.at ? index + 2 : index + 1, lineEnd: lineEnd)
                emit(index, end, .variable)
                return end
            }
            if features.contains(.atAttributes), isIdentifierStart(nextUnit) {
                var end = scanIdentifier(from: index + 1, lineEnd: lineEnd)
                // `@app.route`, `@Foo.Bar`: a dotted name.
                while end + 1 < lineEnd, units[end] == CodeUnits.dot, isIdentifierStart(units[end + 1]) { end = scanIdentifier(from: end + 1, lineEnd: lineEnd) }
                emit(index, end, features.contains(.cssRules) ? .keyword : .attribute)
                return end
            }
        case CodeUnits.dollar:
            if features.contains(.dollarFunctions), isIdentifierStart(nextUnit) {
                let end = scanIdentifier(from: index + 1, lineEnd: lineEnd)
                emit(index, end, .function)
                return end
            }
            if features.contains(.dollarVariables) {
                if nextUnit == CodeUnits.openingBrace {
                    var end = index + 2
                    while end < lineEnd, units[end] != CodeUnits.closingBrace { end += 1 }
                    end = min(end + 1, lineEnd)
                    emit(index, end, .variable)
                    return end
                }
                if isIdentifierStart(nextUnit) {
                    let end = scanIdentifier(from: index + 1, lineEnd: lineEnd)
                    emit(index, end, .variable)
                    return end
                }
                if CodeUnits.isDigit(nextUnit) || "@*#?$!-".utf16.contains(nextUnit) {
                    emit(index, index + 2, .variable)
                    return index + 2
                }
            }
            if features.contains(.assemblyLines), isIdentifierStart(nextUnit) {
                // A MIPS register: `$t0`, `$sp`.
                let end = scanIdentifier(from: index + 1, lineEnd: lineEnd)
                emit(index, end, .variable)
                return end
            }
        case CodeUnits.backtick:
            if features.contains(.backtickDirectives), isIdentifierStart(nextUnit) {
                let end = scanIdentifier(from: index + 1, lineEnd: lineEnd)
                emit(index, end, .preprocessor)
                return end
            }
        case CodeUnits.backslash:
            if features.contains(.backslashCommands) {
                guard CodeUnits.isASCIILetter(nextUnit) else { return min(index + 2, lineEnd) }
                var end = index + 1
                while end < lineEnd, CodeUnits.isASCIILetter(units[end]) { end += 1 }
                if end < lineEnd, units[end] == CodeUnits.asterisk { end += 1 }
                emit(index, end, .keyword)
                let command = word(index + 1, end)
                if command == "begin" || command == "end", end < lineEnd, units[end] == CodeUnits.openingBrace {
                    var closing = end + 1
                    while closing < lineEnd, units[closing] != CodeUnits.closingBrace { closing += 1 }
                    emit(end + 1, closing, .typeName)
                    return min(closing + 1, lineEnd)
                }
                return end
            }
            return min(index + 2, lineEnd)
        case CodeUnits.percent:
            if features.contains(.assemblyLines), isIdentifierStart(nextUnit) {
                let end = scanIdentifier(from: index + 1, lineEnd: lineEnd)
                emit(index, end, .variable)
                return end
            }
        case CodeUnits.dot:
            if features.contains(.assemblyLines), isIdentifierStart(nextUnit) {
                let end = scanIdentifier(from: index + 1, lineEnd: lineEnd)
                let isLabel = end < lineEnd && units[end] == CodeUnits.colon
                emit(index, end, isLabel ? .function : .preprocessor)
                return end
            }
            if features.contains(.cssRules), isFirstTokenOfLine || units[index - 1] == CodeUnits.space, isIdentifierStart(nextUnit) {
                let end = scanCSSName(from: index + 1, lineEnd: lineEnd)
                emit(index, end, .typeName)
                return end
            }
        case CodeUnits.minus:
            if features.contains(.yamlValues), isFirstTokenOfLine, matches(Array("---".utf16), at: index, lineEnd: lineEnd) {
                emit(index, index + 3, .preprocessor)
                return index + 3
            }
        case CodeUnits.ampersand, CodeUnits.asterisk:
            if features.contains(.yamlValues), isIdentifierStart(nextUnit) {
                // A YAML anchor or alias.
                let end = scanIdentifier(from: index + 1, lineEnd: lineEnd)
                emit(index, end, .variable)
                return end
            }
        case CodeUnits.exclamation:
            if features.contains(.yamlValues), isIdentifierStart(nextUnit) || nextUnit == CodeUnits.exclamation {
                // A YAML tag, `!!str`.
                var end = index + 1
                while end < lineEnd, !CodeUnits.isSpace(units[end]) { end += 1 }
                emit(index, end, .typeName)
                return end
            }
        default:
            break
        }
        return index + 1
    }

    /// A CSS name: letters, digits, `-` and `_`.
    private func scanCSSName(from start: Int, lineEnd: Int) -> Int {
        var index = start
        while index < lineEnd, isIdentifierPart(units[index]) || units[index] == CodeUnits.minus { index += 1 }
        return index
    }

    // MARK: YAML

    /// A YAML line's key: `name:` after indentation and list dashes. Returns where the rest
    /// of the line starts.
    private mutating func scanYAMLKey(_ lineStart: Int, _ lineEnd: Int) -> Int {
        var index = lineStart
        while index < lineEnd, CodeUnits.isSpace(units[index]) { index += 1 }
        while index + 1 < lineEnd, units[index] == CodeUnits.minus, CodeUnits.isSpace(units[index + 1]) {
            index += 2
            while index < lineEnd, CodeUnits.isSpace(units[index]) { index += 1 }
        }
        let keyStart = index
        guard keyStart < lineEnd, ![CodeUnits.hash, CodeUnits.doubleQuote, CodeUnits.singleQuote, CodeUnits.openingBrace, CodeUnits.openingBracket,
                                    CodeUnits.ampersand, CodeUnits.asterisk, CodeUnits.exclamation, CodeUnits.minus, CodeUnits.question, CodeUnits.greaterThan].contains(units[keyStart]) else { return index }
        var position = keyStart
        while position < lineEnd {
            let unit = units[position]
            if unit == CodeUnits.colon, position + 1 == lineEnd || CodeUnits.isSpace(units[position + 1]) {
                var keyEnd = position
                while keyEnd > keyStart, CodeUnits.isSpace(units[keyEnd - 1]) { keyEnd -= 1 }
                emit(keyStart, keyEnd, .property)
                return position + 1
            }
            if unit == CodeUnits.hash, position > keyStart, CodeUnits.isSpace(units[position - 1]) { break }
            position += 1
        }
        return keyStart
    }

    // MARK: Markdown

    private mutating func scanMarkdownLine(_ lineStart: Int, _ lineEnd: Int) {
        var index = lineStart
        var indentation = 0
        while index < lineEnd, CodeUnits.isSpace(units[index]) { index += 1; indentation += 1 }
        let isFence = matches(Array("```".utf16), at: index, lineEnd: lineEnd) || matches(Array("~~~".utf16), at: index, lineEnd: lineEnd)
        if case .string = state {
            emit(lineStart, lineEnd, .string)
            if isFence { state = .normal }
            return
        }
        if isFence {
            emit(index, lineEnd, .string)
            state = .string(ruleIndex: 0)
            return
        }
        guard index < lineEnd else { return }
        let unit = units[index]
        if indentation < 4, unit == CodeUnits.hash {
            var end = index
            while end < lineEnd, units[end] == CodeUnits.hash { end += 1 }
            if end - index <= 6, end == lineEnd || CodeUnits.isSpace(units[end]) {
                emit(index, lineEnd, .keyword)
                return
            }
        }
        if unit == CodeUnits.greaterThan {
            emit(index, lineEnd, .comment)
            return
        }
        if indentation < 4, unit == CodeUnits.minus || unit == CodeUnits.asterisk || unit == CodeUnits.underscore,
           (index..<lineEnd).allSatisfy({ position in units[position] == unit || CodeUnits.isSpace(units[position]) }),
           (index..<lineEnd).filter({ position in units[position] == unit }).count >= 3 {
            emit(index, lineEnd, .preprocessor)
            return
        }
        // A list marker, and a task's checkbox after it.
        var markerEnd = index
        if unit == CodeUnits.minus || unit == CodeUnits.asterisk || unit == CodeUnits.plus {
            markerEnd = index + 1
        } else if CodeUnits.isDigit(unit) {
            var end = index
            while end < lineEnd, CodeUnits.isDigit(units[end]) { end += 1 }
            if end < lineEnd, units[end] == CodeUnits.dot || units[end] == CodeUnits.closingParenthesis { markerEnd = end + 1 }
        }
        if markerEnd > index, markerEnd == lineEnd || CodeUnits.isSpace(units[markerEnd]) {
            emit(index, markerEnd, .keyword)
            index = markerEnd
            let next = nextVisibleUnit(from: index, lineEnd: lineEnd)
            if next.unit == CodeUnits.openingBracket, next.index + 2 < lineEnd, units[next.index + 2] == CodeUnits.closingBracket {
                emit(next.index, next.index + 3, .keyword)
                index = next.index + 3
            }
        }
        scanMarkdownInline(from: index, lineEnd: lineEnd)
    }

    private mutating func scanMarkdownInline(from start: Int, lineEnd: Int) {
        var index = start
        while index < lineEnd {
            let unit = units[index]
            if unit == CodeUnits.backslash {
                index += 2
            } else if unit == CodeUnits.backtick {
                var runEnd = index
                while runEnd < lineEnd, units[runEnd] == CodeUnits.backtick { runEnd += 1 }
                let run = Array(units[index..<runEnd])
                var closing = runEnd
                while closing < lineEnd, !matches(run, at: closing, lineEnd: lineEnd) { closing += 1 }
                guard closing < lineEnd else { index = runEnd; continue }
                emit(index, closing + run.count, .string)
                index = closing + run.count
            } else if unit == CodeUnits.openingBracket {
                let isWikilink = index + 1 < lineEnd && units[index + 1] == CodeUnits.openingBracket
                var closing = index + 1
                while closing < lineEnd, units[closing] != CodeUnits.closingBracket { closing += 1 }
                guard closing < lineEnd else { index += 1; continue }
                if isWikilink {
                    let end = min(closing + 2, lineEnd)
                    emit(index > start && units[index - 1] == CodeUnits.exclamation ? index - 1 : index, end, .property)
                    index = end
                } else if closing + 1 < lineEnd, units[closing + 1] == CodeUnits.openingParenthesis {
                    var urlEnd = closing + 2
                    while urlEnd < lineEnd, units[urlEnd] != CodeUnits.closingParenthesis { urlEnd += 1 }
                    emit(index, closing + 1, .property)
                    emit(closing + 1, min(urlEnd + 1, lineEnd), .string)
                    index = min(urlEnd + 1, lineEnd)
                } else {
                    index = closing + 1
                }
            } else if matches(Array("<!--".utf16), at: index, lineEnd: lineEnd) {
                var closing = index + 4
                while closing < lineEnd, !matches(Array("-->".utf16), at: closing, lineEnd: lineEnd) { closing += 1 }
                let end = min(closing + 3, lineEnd)
                emit(index, end, .comment)
                index = end
            } else {
                index += 1
            }
        }
    }

    // MARK: Markup

    private mutating func scanMarkupLine(_ lineStart: Int, _ lineEnd: Int) {
        var index = continueOpenConstruct(lineStart, lineEnd)
        while index < lineEnd {
            if state == .markupTag {
                index = scanMarkupAttributes(from: index, lineEnd: lineEnd)
                continue
            }
            let unit = units[index]
            if let ruleIndex = blockCommentRuleIndex(at: index, lineEnd: lineEnd, isFirstTokenOfLine: false) {
                let rule = language.blockComments[ruleIndex]
                let (end, remainingDepth) = scanBlockComment(rule, from: index + rule.opening.count, depth: 1, lineEnd: lineEnd)
                emit(index, end, .comment)
                if let remainingDepth { state = .blockComment(ruleIndex: ruleIndex, depth: remainingDepth) }
                index = end
            } else if unit == CodeUnits.lessThan, index + 1 < lineEnd, units[index + 1] == CodeUnits.question || units[index + 1] == CodeUnits.exclamation {
                // `<?xml …?>` and `<!DOCTYPE …>`.
                var closing = index + 2
                while closing < lineEnd, units[closing] != CodeUnits.greaterThan { closing += 1 }
                let end = min(closing + 1, lineEnd)
                emit(index, end, .preprocessor)
                index = end
            } else if unit == CodeUnits.lessThan, index + 1 < lineEnd, isIdentifierStart(units[index + 1]) || units[index + 1] == CodeUnits.slash {
                let nameStart = units[index + 1] == CodeUnits.slash ? index + 2 : index + 1
                var nameEnd = nameStart
                while nameEnd < lineEnd, isIdentifierPart(units[nameEnd]) || units[nameEnd] == CodeUnits.colon || units[nameEnd] == CodeUnits.minus || units[nameEnd] == CodeUnits.dot { nameEnd += 1 }
                emit(nameStart, nameEnd, .keyword)
                state = .markupTag
                index = nameEnd
            } else if unit == CodeUnits.ampersand {
                var end = index + 1
                while end < lineEnd, end - index < 12, isIdentifierPart(units[end]) || units[end] == CodeUnits.hash { end += 1 }
                if end < lineEnd, units[end] == CodeUnits.semicolon { emit(index, end + 1, .constant) }
                index = max(end, index + 1)
            } else {
                index += 1
            }
        }
    }

    /// A tag's attributes, until its `>`.
    private mutating func scanMarkupAttributes(from start: Int, lineEnd: Int) -> Int {
        var index = start
        while index < lineEnd {
            let unit = units[index]
            if unit == CodeUnits.greaterThan {
                state = .normal
                return index + 1
            }
            if unit == CodeUnits.doubleQuote || unit == CodeUnits.singleQuote {
                var closing = index + 1
                while closing < lineEnd, units[closing] != unit { closing += 1 }
                let end = min(closing + 1, lineEnd)
                emit(index, end, .string)
                index = end
            } else if isIdentifierStart(unit) {
                var end = index
                while end < lineEnd, isIdentifierPart(units[end]) || units[end] == CodeUnits.colon || units[end] == CodeUnits.minus { end += 1 }
                emit(index, end, .attribute)
                index = end
            } else {
                index += 1
            }
        }
        return lineEnd
    }
}
