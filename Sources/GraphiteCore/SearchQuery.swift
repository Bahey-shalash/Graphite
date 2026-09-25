import Foundation

/// A search written in Obsidian's search syntax: words, `"phrases"`, `/regular
/// expressions/`, `OR`, `-` to exclude, parentheses, operators such as `path:` and
/// `tag:`, and `[property:value]`.
public indirect enum SearchExpression: Equatable, Sendable {
    /// Every expression matches.
    case all([SearchExpression])
    /// At least one expression matches.
    case any([SearchExpression])
    case not(SearchExpression)
    /// A word, phrase, or regular expression in a note's name, path, or content.
    case term(SearchTerm)
    /// An operator such as `path:` or `line:` applied to what follows it.
    case scoped(SearchScope, SearchExpression)
    /// `[name]` finds notes with the property; `[name:value]` also matches its value.
    case property(name: String, value: SearchExpression?)
}

public struct SearchTerm: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Matches words starting with it, ignoring case and the accents of Latin letters.
        /// Chinese, Japanese, and Korean letters match anywhere inside a word.
        case word
        /// Matches the words in this order.
        case phrase
        case regularExpression
    }

    public let text: String
    public let kind: Kind

    public init(text: String, kind: Kind) {
        self.text = text; self.kind = kind
    }
}

/// Obsidian's search operators.
public enum SearchScope: String, CaseIterable, Sendable {
    case file, path, content, tag, line, block, section, task
    case taskTodo = "task-todo"
    case taskDone = "task-done"
    case matchCase = "match-case"
    case ignoreCase = "ignore-case"
}

// MARK: - Parsing

public enum SearchQueryParser {
    /// Groups, operators, and property values nested deeper than this are read flat. People
    /// write a few levels; the limit keeps a pasted run of `(` or `line:` from recursing, in
    /// the parser and in everything that walks the expression, deep enough to exhaust the
    /// small stacks that search runs on.
    static let maximumNestingDepth = 32

    /// The expression for `query`, or nil when it asks for nothing.
    public static func parse(_ query: String) -> SearchExpression? {
        parse(query, nestingDepth: 0)
    }

    private static func parse(_ query: String, nestingDepth: Int) -> SearchExpression? {
        var parser = TokenParser(tokens: tokens(in: query), nestingDepth: nestingDepth)
        return parser.parseQuery()
    }

    enum Token: Equatable {
        case term(SearchTerm)
        case openGroup
        case closeGroup
        case or
        case negation
        case scope(SearchScope)
        case property(name: String, valueText: String?)
    }

    static func tokens(in query: String) -> [Token] {
        // The iPad keyboard turns typed quotes into curly ones.
        let characters = Array(query.replacingOccurrences(of: "[\u{201C}\u{201D}\u{201E}\u{201F}\u{2033}]", with: "\"", options: .regularExpression))
        var tokens: [Token] = []
        var index = 0
        func isBreak(_ character: Character) -> Bool { character.isWhitespace || character == "(" || character == ")" }
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace { index += 1; continue }
            if character == "(" { tokens.append(.openGroup); index += 1; continue }
            if character == ")" { tokens.append(.closeGroup); index += 1; continue }
            if character == "-", index + 1 < characters.count, !isBreak(characters[index + 1]) || characters[index + 1] == "(" {
                tokens.append(.negation); index += 1; continue
            }
            if character == "\"" {
                let (text, nextIndex) = readDelimited(characters, from: index + 1, closing: "\"")
                tokens.append(.term(SearchTerm(text: text, kind: .phrase)))
                index = nextIndex
                continue
            }
            if character == "/", let closing = regularExpressionClosingIndex(in: characters, from: index + 1), closing > index + 1 {
                let pattern = String(characters[(index + 1)..<closing])
                tokens.append(.term(SearchTerm(text: pattern, kind: .regularExpression)))
                index = closing + 1
                continue
            }
            if character == "[", let closing = closingBracketIndex(in: characters, from: index + 1) {
                let content = String(characters[(index + 1)..<closing])
                index = closing + 1
                if let separator = propertySeparatorIndex(in: content) {
                    let name = String(content[..<separator]).trimmingCharacters(in: .whitespaces)
                    let valueText = String(content[content.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                    tokens.append(.property(name: unquoted(name), valueText: valueText))
                } else {
                    tokens.append(.property(name: unquoted(content.trimmingCharacters(in: .whitespaces)), valueText: nil))
                }
                continue
            }
            var word = ""
            var wordIndex = index
            var foundScope: SearchScope?
            while wordIndex < characters.count, !isBreak(characters[wordIndex]) {
                if characters[wordIndex] == ":", let scope = SearchScope(rawValue: word.lowercased()) {
                    foundScope = scope
                    wordIndex += 1
                    break
                }
                word.append(characters[wordIndex])
                wordIndex += 1
            }
            index = wordIndex
            if let foundScope {
                tokens.append(.scope(foundScope))
            } else if word == "OR" {
                tokens.append(.or)
            } else {
                tokens.append(.term(SearchTerm(text: word, kind: .word)))
            }
        }
        return tokens
    }

    /// Text up to an unescaped `closing` character; `\"` inside a phrase is a quote.
    private static func readDelimited(_ characters: [Character], from start: Int, closing: Character) -> (String, Int) {
        var text = ""
        var index = start
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count, characters[index + 1] == closing || characters[index + 1] == "\\" {
                text.append(characters[index + 1]); index += 2; continue
            }
            if character == closing { return (text, index + 1) }
            text.append(character); index += 1
        }
        return (text, index)
    }

    /// The `/` ending a regular expression. An escaped `\/` does not end it, and neither does
    /// a `/` inside a character class such as `[/]`, which JavaScript patterns, as Obsidian
    /// reads them, allow. An unclosed class falls back to the first unescaped `/`, so the
    /// pattern is reported as invalid instead of becoming words.
    private static func regularExpressionClosingIndex(in characters: [Character], from start: Int) -> Int? {
        var firstUnescapedSlash: Int?
        var characterClassDepth = 0
        var index = start
        while index < characters.count {
            switch characters[index] {
            case "\\":
                index += 2
                continue
            case "[":
                characterClassDepth += 1
            case "]":
                characterClassDepth = max(0, characterClassDepth - 1)
            case "/":
                if characterClassDepth == 0 { return index }
                if firstUnescapedSlash == nil { firstUnescapedSlash = index }
            default:
                break
            }
            index += 1
        }
        return firstUnescapedSlash
    }

    /// The `]` closing a property, skipping brackets inside quotes and nested brackets.
    private static func closingBracketIndex(in characters: [Character], from start: Int) -> Int? {
        var depth = 0
        var isInQuotes = false
        var index = start
        while index < characters.count {
            let character = characters[index]
            if character == "\\" { index += 2; continue }
            if character == "\"" { isInQuotes.toggle() }
            if !isInQuotes {
                if character == "[" { depth += 1 }
                if character == "]" {
                    if depth == 0 { return index }
                    depth -= 1
                }
            }
            index += 1
        }
        return nil
    }

    private static func propertySeparatorIndex(in content: String) -> String.Index? {
        var isInQuotes = false
        for index in content.indices {
            if content[index] == "\"" { isInQuotes.toggle() }
            if content[index] == ":" && !isInQuotes { return index }
        }
        return nil
    }

    private static func unquoted(_ text: String) -> String {
        text.count >= 2 && text.hasPrefix("\"") && text.hasSuffix("\"") ? String(text.dropFirst().dropLast()) : text
    }

    private struct TokenParser {
        let tokens: [Token]
        var position = 0
        /// Groups, operators, and property values around the current token.
        var nestingDepth: Int

        init(tokens: [Token], nestingDepth: Int) {
            self.tokens = tokens
            self.nestingDepth = nestingDepth
        }

        private var current: Token? { position < tokens.count ? tokens[position] : nil }
        private var canNestDeeper: Bool { nestingDepth < SearchQueryParser.maximumNestingDepth }

        mutating func parseQuery() -> SearchExpression? {
            var parts: [SearchExpression] = []
            while position < tokens.count {
                if let expression = parseAlternatives() { parts.append(expression) }
                // A closing parenthesis without an opening one is ignored.
                if current == .closeGroup || current == .or { position += 1 }
            }
            return combined(parts, as: SearchExpression.all)
        }

        private mutating func parseAlternatives() -> SearchExpression? {
            var alternatives: [SearchExpression] = []
            if let first = parseSequence() { alternatives.append(first) }
            while current == .or {
                position += 1
                if let next = parseSequence() { alternatives.append(next) }
            }
            return combined(alternatives, as: SearchExpression.any)
        }

        private mutating func parseSequence() -> SearchExpression? {
            var items: [SearchExpression] = []
            while let token = current, token != .or, token != .closeGroup {
                if let item = parseUnary() { items.append(item) }
            }
            return combined(items, as: SearchExpression.all)
        }

        /// A run of `-` is read at once, without recursing: two exclusions cancel. A `-` with
        /// nothing after it to exclude, as before `OR` or `)`, asks for nothing. Too deep for
        /// another group or operator, its `(` or operator is ignored, and what follows is read
        /// in place, still excluded by any `-` before it.
        private mutating func parseUnary() -> SearchExpression? {
            var negationCount = 0
            reading: while let token = current {
                switch token {
                case .negation:
                    negationCount += 1
                case .openGroup where !canNestDeeper, .scope where !canNestDeeper:
                    break
                default:
                    break reading
                }
                position += 1
            }
            guard let operand = parsePrimary() else { return nil }
            return negationCount.isMultiple(of: 2) ? operand : .not(operand)
        }

        private mutating func parsePrimary() -> SearchExpression? {
            // `OR` and `)` belong to the enclosing sequence even after an operator or `-`
            // that has nothing to apply to, so they are left for it.
            guard let token = current, token != .or, token != .closeGroup else { return nil }
            position += 1
            switch token {
            case .openGroup:
                nestingDepth += 1
                defer { nestingDepth -= 1 }
                let inner = parseAlternatives()
                if current == .closeGroup { position += 1 }
                return inner
            case .scope(let scope):
                nestingDepth += 1
                defer { nestingDepth -= 1 }
                guard let operand = parseUnary() else { return nil }
                return .scoped(scope, operand)
            case .term(let term):
                guard !term.text.isEmpty else { return nil }
                // `#tag` finds the tag, as tapping a tag in a note does.
                if term.kind == .word, term.text.hasPrefix("#"), TagSyntax.isValidTag(String(term.text.dropFirst())) {
                    return .scoped(.tag, .term(term))
                }
                return .term(term)
            case .property(let name, let valueText):
                guard !name.isEmpty else { return nil }
                guard let valueText, !valueText.isEmpty else { return .property(name: name, value: nil) }
                // Too deep: the value is looked for as written instead of being parsed again.
                guard canNestDeeper else { return .property(name: name, value: .term(SearchTerm(text: valueText, kind: .phrase))) }
                return .property(name: name, value: SearchQueryParser.parse(valueText, nestingDepth: nestingDepth + 1))
            case .negation, .closeGroup, .or:
                return nil
            }
        }

        private func combined(_ expressions: [SearchExpression], as combine: ([SearchExpression]) -> SearchExpression) -> SearchExpression? {
            switch expressions.count {
            case 0: nil
            case 1: expressions[0]
            default: combine(expressions)
            }
        }
    }
}

extension SearchExpression {
    /// Plain words and phrases joined by AND: the searches where files whose name
    /// contains every word are listed first.
    public var plainTerms: [SearchTerm]? {
        switch self {
        case .term(let term) where term.kind != .regularExpression: return [term]
        case .all(let items):
            var terms: [SearchTerm] = []
            for item in items {
                guard case .term(let term) = item, term.kind != .regularExpression else { return nil }
                terms.append(term)
            }
            return terms
        default: return nil
        }
    }

    /// Whether some part of the expression excludes (`-`) something.
    public var containsNegation: Bool {
        switch self {
        case .not: true
        case .all(let items), .any(let items): items.contains { item in item.containsNegation }
        case .scoped(_, let operand): operand.containsNegation
        case .property(_, let value): value?.containsNegation ?? false
        case .term: false
        }
    }

    /// The `/regular expressions/` in the search that cannot be compiled. Such a pattern
    /// matches nothing (and excluding it matches everything), so a search holding one
    /// should say so rather than show its results.
    public var invalidRegularExpressionPatterns: [String] {
        switch self {
        case .all(let items), .any(let items): items.flatMap(\.invalidRegularExpressionPatterns)
        case .not(let item), .scoped(_, let item): item.invalidRegularExpressionPatterns
        case .property(_, let value): value?.invalidRegularExpressionPatterns ?? []
        case .term(let term):
            term.kind == .regularExpression && (try? NSRegularExpression(pattern: term.text)) == nil ? [term.text] : []
        }
    }
}

// MARK: - Matching

/// What search can see of one file.
public struct SearchableFile: Sendable {
    public let path: VaultPath
    /// The note's text, frontmatter included; nil for files that are not notes.
    public let content: String?
    public let tags: [String]
    public let properties: [BaseFrontmatterEntry]

    public init(path: VaultPath, content: String?, tags: [String], properties: [BaseFrontmatterEntry]) {
        self.path = path; self.content = content; self.tags = tags; self.properties = properties
    }
}

/// Words of text as the full-text index sees them, so matching them here gives the same
/// answers as the index. SQLite's `unicode61` tokenizer, with `remove_diacritics 2`, reads
/// a word as a run of letters, numbers, and private-use characters, which a combining
/// accent it removes may continue. It folds case with Unicode's simple case folding and
/// removes accents from Latin letters only. This follows it character by character.
/// Foundation's folding is broader (`й` to `и`, `ά` to `α`, `ß` to `ss`, `ﬁ` to `fi`), and
/// a word folded that way is not a word the index holds, so it could never be found.
///
/// Two kinds of term go beyond the index's words; the index finds their candidates by
/// `literalFragments(of:)` and leaves the decision to `SearchMatcher`. Chinese and Japanese
/// are written without spaces and Korean joins particles to words, so a run of their letters
/// is one long word: a query word containing them matches anywhere inside a word, as in
/// Obsidian. A term with no words but symbols, such as an emoji, is found as written.
public struct SearchTextTokens {
    public struct Token {
        public let folded: String
        /// Where the word is in the original text (UTF-16).
        public let range: NSRange
    }

    public let tokens: [Token]
    /// The text the words were read from, to place a match that starts inside a word.
    private let text: String
    private let foldsCase: Bool

    public init(_ text: String, foldsCase: Bool = true) {
        var tokens: [Token] = []
        // The current word, folded, as UTF-8; the buffer is reused from word to word.
        var foldedBytes: [UInt8] = []
        foldedBytes.reserveCapacity(64)
        var isInWord = false
        var tokenStart = 0
        var offset = 0
        func finishToken() {
            guard isInWord else { return }
            tokens.append(Token(folded: String(decoding: foldedBytes, as: UTF8.self), range: NSRange(location: tokenStart, length: offset - tokenStart)))
            foldedBytes.removeAll(keepingCapacity: true)
            isInWord = false
        }
        for scalar in text.unicodeScalars {
            if scalar.isASCII {
                // Most text is ASCII, where only letters and digits make words and folding
                // only lowercases, so it skips the Unicode property lookups below.
                let byte = UInt8(truncatingIfNeeded: scalar.value)
                if Self.isASCIIWordByte(byte) {
                    if !isInWord { isInWord = true; tokenStart = offset }
                    foldedBytes.append(foldsCase ? Self.asciiLowercased(byte) : byte)
                } else {
                    finishToken()
                }
                offset += 1
                continue
            }
            if Self.isWordScalar(scalar) || (isInWord && Self.isRemovableAccent(scalar)) {
                if !isInWord { isInWord = true; tokenStart = offset }
                if let folded = Self.folded(scalar, foldsCase: foldsCase) { foldedBytes.append(contentsOf: folded.utf8) }
            } else {
                finishToken()
            }
            offset += scalar.utf16.count
        }
        finishToken()
        self.tokens = tokens
        self.text = text
        self.foldsCase = foldsCase
    }

    // MARK: Reading words as unicode61 does

    private static func isASCIIWordByte(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    private static func asciiLowercased(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + (UInt8(ascii: "a") - UInt8(ascii: "A")) : byte
    }

    /// unicode61 starts and continues words with letters, numbers, and private-use
    /// characters. Other combining marks, as in Devanagari, and emoji variation selectors
    /// separate words there, so they do here.
    static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        // unicode61's tables are Unicode 6.1's, and it reads every character assigned since
        // as part of a word, whatever it is now.
        guard isInUnicode61Tables(scalar) else { return true }
        switch scalar.value {
        // Characters whose category Unicode changed after 6.1: two Mongolian letters that
        // became marks, and New Tai Lue and Vedic signs that became letters.
        case 0x1885, 0x1886: return true
        case 0x19B0...0x19C0, 0x19C8, 0x19C9, 0x1CF2, 0x1CF3: return false
        default: break
        }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber, .privateUse:
            return true
        default:
            return false
        }
    }

    /// Whether `scalar` was assigned by Unicode 6.1, the version of unicode61's tables.
    private static func isInUnicode61Tables(_ scalar: Unicode.Scalar) -> Bool {
        guard let age = scalar.properties.age else { return false }
        return age.major < 6 || (age.major == 6 && age.minor <= 1)
    }

    /// The combining accents that Latin letters decompose into. unicode61 lets them continue
    /// a word and drops them from it, so `e` followed by U+0301 reads as `e`.
    static func isRemovableAccent(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x300...0x304, 0x306...0x30C, 0x30F, 0x311, 0x31B, 0x323...0x328, 0x32D, 0x32E, 0x330, 0x331:
            return true
        default:
            return false
        }
    }

    /// A non-ASCII word character as unicode61 stores it, or nil when it is dropped.
    private static func folded(_ scalar: Unicode.Scalar, foldsCase: Bool) -> Unicode.Scalar? {
        let caseFolded = foldsCase ? simpleCaseFolded(scalar) : scalar
        if isRemovableAccent(caseFolded) { return nil }
        let baseLetter = caseFolded.value < UInt32(latinBaseLetters.count) ? latinBaseLetters[Int(caseFolded.value)] : 0
        guard baseLetter != 0 else { return caseFolded }
        return Unicode.Scalar(foldsCase ? asciiLowercased(baseLetter) : baseLetter)
    }

    /// Simple case folding as unicode61's table has it: a letter's lowercase form, with a
    /// few exceptions, as of Unicode 6.1. Case mappings added since (Cherokee's, or those of
    /// letters assigned later) do not apply there, so they do not apply here.
    private static func simpleCaseFolded(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        let value = scalar.value
        // Above the Basic Multilingual Plane, unicode61 folds only Deseret capitals.
        if value >= 0x1_0000 {
            return (0x10400..<0x10428).contains(value) ? Unicode.Scalar(value + 0x28) ?? scalar : scalar
        }
        switch value {
        // Letters that are already lowercase but fold to another letter.
        case 0xB5: return "\u{3BC}"
        case 0x17F: return "s"
        case 0x3C2: return "\u{3C3}"
        case 0x3D0: return "\u{3B2}"
        case 0x3D1: return "\u{3B8}"
        case 0x3D5: return "\u{3C6}"
        case 0x3D6: return "\u{3C0}"
        case 0x3F0: return "\u{3BA}"
        case 0x3F1: return "\u{3C1}"
        case 0x3F5: return "\u{3B5}"
        case 0x1E9B: return "\u{1E61}"
        case 0x1FBE: return "\u{3B9}"
        default: break
        }
        guard scalar.properties.changesWhenLowercased, isInUnicode61Tables(scalar) else { return scalar }
        let lowercase = scalar.properties.lowercaseMapping.unicodeScalars
        // Only U+0130 (İ) lowercases to two characters; case folding leaves it, and its
        // accent is then removed like any Latin letter's.
        guard lowercase.count == 1, let lowercaseScalar = lowercase.first, isInUnicode61Tables(lowercaseScalar) else { return scalar }
        return lowercaseScalar
    }

    /// For each character below U+1F00, the ASCII letter it is with accents, or 0. These
    /// are the characters unicode61 removes accents from: those whose canonical
    /// decomposition is an ASCII letter followed by combining marks, all of them in the
    /// Latin-1 Supplement, Latin Extended-A and B, and Latin Extended Additional blocks.
    /// Its table misses U+01E0 and U+01E1 (`ǡ`), which decompose through a letter that
    /// comes after them in Unicode's list, so this does too.
    private static let latinBaseLetters: [UInt8] = (0..<UInt32(0x1F00)).map { value in
        guard (0xC0..<0x250).contains(value) || (0x1E00..<0x1F00).contains(value), value != 0x1E0, value != 0x1E1,
              let scalar = Unicode.Scalar(value) else { return 0 }
        let decomposition = String(Character(scalar)).decomposedStringWithCanonicalMapping.unicodeScalars
        guard decomposition.count > 1, let first = decomposition.first, first.isASCII else { return 0 }
        let byte = UInt8(truncatingIfNeeded: first.value)
        return isASCIIWordByte(byte) && !(UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) ? byte : 0
    }

    // MARK: Chinese, Japanese, and Korean

    /// Letters of Chinese, Japanese, and Korean: Han ideographs, kana, bopomofo, and hangul.
    static func isChineseJapaneseOrKoreanScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF,                        // Hangul jamo
             0x2E80...0x2FDF,                        // Han radicals
             0x3005...0x3007, 0x3021...0x3029,       // ideographic iteration and number marks
             0x3031...0x3035, 0x303B...0x303C,       // kana repetition marks
             0x3040...0x30FF,                        // hiragana and katakana
             0x3100...0x312F, 0x31A0...0x31BF,       // bopomofo
             0x3130...0x318F,                        // hangul compatibility jamo
             0x31F0...0x31FF,                        // katakana phonetic extensions
             0x3400...0x4DBF, 0x4E00...0x9FFF,       // Han ideographs
             0xA960...0xA97F, 0xAC00...0xD7FF,       // hangul syllables and jamo
             0xF900...0xFAFF,                        // Han compatibility ideographs
             0xFF66...0xFFDC,                        // halfwidth katakana and hangul
             0x1B000...0x1B16F,                      // kana supplement and extensions
             0x20000...0x323AF:                      // Han ideograph extensions
            return true
        default:
            return false
        }
    }

    /// Whether a query word holding `scalar` is found anywhere inside a word rather than
    /// only at its start: letters of Chinese, Japanese and Korean, and of Thai, Lao, Myanmar
    /// and Khmer, scripts written without spaces between words (or, in Korean, with
    /// particles joined to them), where the index reads a whole run as one word. The index
    /// finds candidates for such words by the runs `literalFragments(of:)` returns.
    public static func isMatchedInsideWords(_ scalar: Unicode.Scalar) -> Bool {
        if isChineseJapaneseOrKoreanScalar(scalar) || scalar.properties.isIdeographic { return true }
        switch scalar.value {
        case 0x0E00...0x0EFF, // Thai and Lao
             0x1000...0x109F, // Myanmar
             0x1780...0x17FF: // Khmer
            return true
        default:
            return false
        }
    }

    private static func containsLettersMatchedInsideWords(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isMatchedInsideWords)
    }

    // MARK: Matching

    /// Ranges in the original text where `queryTokens` appear in order; the last query
    /// word may be the start of a longer word when `lastIsPrefix` is set. A query word with
    /// letters `isMatchedInsideWords` accepts may be anywhere inside a word, and its range
    /// covers just that part.
    public func matches(of queryTokens: [String], lastIsPrefix: Bool) -> [NSRange] {
        guard !queryTokens.isEmpty, tokens.count >= queryTokens.count else { return [] }
        let isAnywhereInWord = queryTokens.map(Self.containsLettersMatchedInsideWords)
        var ranges: [NSRange] = []
        for startIndex in 0...(tokens.count - queryTokens.count) {
            var foldedRanges: [Range<Int>] = []
            for (queryIndex, queryToken) in queryTokens.enumerated() {
                let isLast = queryIndex == queryTokens.count - 1
                guard let foldedRange = Self.foldedRange(of: queryToken, in: tokens[startIndex + queryIndex].folded,
                                                         isAnywhere: isAnywhereInWord[queryIndex], isPrefix: isLast && lastIsPrefix) else { break }
                foldedRanges.append(foldedRange)
            }
            guard foldedRanges.count == queryTokens.count, let firstFoldedRange = foldedRanges.first, let lastFoldedRange = foldedRanges.last else { continue }
            let first = tokens[startIndex], last = tokens[startIndex + queryTokens.count - 1]
            let start = isAnywhereInWord[0] ? originalOffset(ofFoldedByte: firstFoldedRange.lowerBound, in: first) : first.range.location
            let end = isAnywhereInWord[queryTokens.count - 1] ? originalOffset(ofFoldedByte: lastFoldedRange.upperBound, in: last) : NSMaxRange(last.range)
            ranges.append(NSRange(location: start, length: end - start))
        }
        return ranges
    }

    public func contains(_ queryTokens: [String], lastIsPrefix: Bool) -> Bool {
        guard !queryTokens.isEmpty, tokens.count >= queryTokens.count else { return false }
        let isAnywhereInWord = queryTokens.map(Self.containsLettersMatchedInsideWords)
        for startIndex in 0...(tokens.count - queryTokens.count) {
            var isMatch = true
            for (queryIndex, queryToken) in queryTokens.enumerated() {
                let isLast = queryIndex == queryTokens.count - 1
                if Self.foldedRange(of: queryToken, in: tokens[startIndex + queryIndex].folded, isAnywhere: isAnywhereInWord[queryIndex], isPrefix: isLast && lastIsPrefix) == nil {
                    isMatch = false
                    break
                }
            }
            if isMatch { return true }
        }
        return false
    }

    /// Where `queryToken` is in the folded word `token`, in UTF-8 bytes, or nil. Words are
    /// compared by their bytes, as SQLite compares them, not by Swift's canonical equivalence.
    private static func foldedRange(of queryToken: String, in token: String, isAnywhere: Bool, isPrefix: Bool) -> Range<Int>? {
        let tokenBytes = token.utf8, queryBytes = queryToken.utf8
        if isAnywhere {
            guard let range = token.range(of: queryToken, options: .literal) else { return nil }
            let start = tokenBytes.distance(from: tokenBytes.startIndex, to: range.lowerBound)
            return start..<(start + queryBytes.count)
        }
        let isMatch = isPrefix ? tokenBytes.starts(with: queryBytes) : tokenBytes.elementsEqual(queryBytes)
        return isMatch ? 0..<queryBytes.count : nil
    }

    /// The UTF-16 offset in the original text of the character that begins at `foldedByte`
    /// of `token`'s folded form (or of its end, when `foldedByte` is the folded length).
    private func originalOffset(ofFoldedByte foldedByte: Int, in token: Token) -> Int {
        var offset = token.range.location
        var foldedByteCount = 0
        let start = String.Index(utf16Offset: token.range.location, in: text)
        for scalar in text.unicodeScalars[start...] {
            guard foldedByteCount < foldedByte, offset < NSMaxRange(token.range) else { break }
            foldedByteCount += scalar.isASCII ? 1 : Self.folded(scalar, foldsCase: foldsCase)?.utf8.count ?? 0
            offset += scalar.utf16.count
        }
        return offset
    }

    /// The folded words of a search term.
    public static func queryTokens(of text: String, foldsCase: Bool = true) -> [String] {
        SearchTextTokens(text, foldsCase: foldsCase).tokens.map(\.folded)
    }

    // MARK: Terms the index cannot find by its words

    /// What a term with no words, such as an emoji, a currency sign or an arrow, looks for
    /// as written: its text without the variation selectors that pick emoji or text style,
    /// so `❤️` also finds a plain `❤`. Nil when the term has words, or holds no symbol
    /// (punctuation alone, such as a lone "-", or whitespace), which asks for nothing.
    public static func literalSymbols(of text: String) -> String? {
        guard !text.unicodeScalars.contains(where: { scalar in scalar.isASCII ? isASCIIWordByte(UInt8(truncatingIfNeeded: scalar.value)) : isWordScalar(scalar) }),
              text.unicodeScalars.contains(where: isSymbol) else { return nil }
        var symbols = String.UnicodeScalarView()
        symbols.append(contentsOf: text.unicodeScalars.filter { scalar in !(0xFE00...0xFE0F).contains(scalar.value) })
        let trimmedSymbols = String(symbols).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSymbols.isEmpty ? nil : trimmedSymbols
    }

    /// A math, currency, modifier or other symbol, such as `+`, `€`, `^` or an emoji.
    private static func isSymbol(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol: true
        default: false
        }
    }

    /// Text that every note matching the word or phrase `text` contains exactly as written,
    /// for terms the full-text index cannot find by its words: each run of letters
    /// `isMatchedInsideWords` accepts, and the symbols of a term that has no words. The index
    /// selects candidates containing all of them and `SearchMatcher` decides. Empty when
    /// the index's words find the term exactly.
    public static func literalFragments(of text: String) -> [String] {
        if let symbols = literalSymbols(of: text) { return [symbols] }
        var fragments: [String] = []
        var currentFragment = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if isMatchedInsideWords(scalar) {
                currentFragment.append(scalar)
            } else if !currentFragment.isEmpty {
                fragments.append(String(currentFragment))
                currentFragment = String.UnicodeScalarView()
            }
        }
        if !currentFragment.isEmpty { fragments.append(String(currentFragment)) }
        return fragments
    }

    /// Ranges of `symbols` in `text`, as `literalSymbols(of:)` looks for them.
    public static func literalRanges(of symbols: String, in text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: text.length)
        while searchRange.length > 0 {
            let found = text.range(of: symbols, options: .literal, range: searchRange)
            guard found.location != NSNotFound, found.length > 0 else { break }
            ranges.append(found)
            searchRange = NSRange(location: NSMaxRange(found), length: text.length - NSMaxRange(found))
        }
        return ranges
    }
}

/// Decides whether a file matches a search expression. The index narrows the files
/// first; this checks the parts it cannot decide, such as `line:` and `[property:value]`.
public struct SearchMatcher {
    public let expression: SearchExpression
    private var regularExpressions: [String: NSRegularExpression] = [:]
    /// Folded words of each term, read once rather than for every candidate and line.
    private var queryTokensByTerm: [String: [String]] = [:]
    /// Whether a regular expression ran past `TimeLimitedRegularExpression`'s limit on a
    /// file checked so far. Its answer for that file is not reliable.
    public private(set) var hasExceededRegularExpressionTimeLimit = false

    public init(expression: SearchExpression) {
        self.expression = expression
    }

    public mutating func matches(_ file: SearchableFile) -> Bool {
        var context = FileContext(file: file)
        return evaluate(expression, in: .note, isCaseSensitive: false, context: &context)
    }

    /// Where a search looks inside one file.
    enum Target {
        /// A note's name, path, and content: where plain words look.
        case note
        case fileName
        case filePath
        case content
        /// The tags of the file, or of the part of it being searched.
        case tags([String])
        /// One line, block, section, or task of the content.
        case contentPart(String)
        /// A property's value.
        case propertyValue(String)
    }

    struct FileContext {
        let file: SearchableFile
        var contentTokens: [Bool: SearchTextTokens] = [:]
        var contentPartsByScope: [SearchScope: [String]] = [:]
        init(file: SearchableFile) { self.file = file }
    }

    private mutating func evaluate(_ expression: SearchExpression, in target: Target, isCaseSensitive: Bool, context: inout FileContext) -> Bool {
        switch expression {
        case .all(let items):
            for item in items where !evaluate(item, in: target, isCaseSensitive: isCaseSensitive, context: &context) { return false }
            return true
        case .any(let items):
            for item in items where evaluate(item, in: target, isCaseSensitive: isCaseSensitive, context: &context) { return true }
            return false
        case .not(let item):
            return !evaluate(item, in: target, isCaseSensitive: isCaseSensitive, context: &context)
        case .term(let term):
            return matches(term, in: target, isCaseSensitive: isCaseSensitive, context: &context)
        case .scoped(let scope, let operand):
            return evaluate(scope, operand, in: target, isCaseSensitive: isCaseSensitive, context: &context)
        case .property(let name, let value):
            let entries = context.file.properties.filter { entry in entry.key.caseInsensitiveCompare(name) == .orderedSame }
            guard !entries.isEmpty else { return false }
            guard let value else { return true }
            return entries.contains { entry in propertyValue(entry.node, matches: value, isCaseSensitive: isCaseSensitive, context: &context) }
        }
    }

    private mutating func evaluate(_ scope: SearchScope, _ operand: SearchExpression, in target: Target, isCaseSensitive: Bool, context: inout FileContext) -> Bool {
        switch scope {
        case .file: return evaluate(operand, in: .fileName, isCaseSensitive: isCaseSensitive, context: &context)
        case .path: return evaluate(operand, in: .filePath, isCaseSensitive: isCaseSensitive, context: &context)
        case .content: return evaluate(operand, in: .content, isCaseSensitive: isCaseSensitive, context: &context)
        case .tag:
            // Inside `line:`, `block:`, `section:` or `task:`, a tag must be written in that
            // part (`task-todo:#work`), not merely somewhere in the file.
            if case .contentPart(let part) = target {
                return evaluate(operand, in: .tags(Self.tags(writtenIn: part)), isCaseSensitive: isCaseSensitive, context: &context)
            }
            return evaluate(operand, in: .tags(context.file.tags), isCaseSensitive: isCaseSensitive, context: &context)
        case .matchCase: return evaluate(operand, in: target, isCaseSensitive: true, context: &context)
        case .ignoreCase: return evaluate(operand, in: target, isCaseSensitive: false, context: &context)
        case .line, .block, .section, .task, .taskTodo, .taskDone:
            // Inside a line, block, section, or task, an operator reads that part, not the
            // whole file (`section:(task-todo:#work)` wants an open task in the section). Read
            // from the whole file, nested operators would multiply: each level would visit
            // every line once for every line of the level around it.
            if case .contentPart(let enclosingPart) = target {
                for part in SearchContentParts.parts(of: enclosingPart, scope: scope)
                where evaluate(operand, in: .contentPart(part), isCaseSensitive: isCaseSensitive, context: &context) {
                    return true
                }
                return false
            }
            guard let content = context.file.content else { return false }
            if context.contentPartsByScope[scope] == nil { context.contentPartsByScope[scope] = SearchContentParts.parts(of: content, scope: scope) }
            for part in context.contentPartsByScope[scope] ?? [] {
                if evaluate(operand, in: .contentPart(part), isCaseSensitive: isCaseSensitive, context: &context) { return true }
            }
            return false
        }
    }

    private mutating func propertyValue(_ node: BaseFrontmatterNode, matches value: SearchExpression, isCaseSensitive: Bool, context: inout FileContext) -> Bool {
        switch node {
        case .sequence(let items):
            if items.isEmpty, case .term(let term) = value, term.text.lowercased() == "null" { return true }
            return items.contains { item in propertyValue(item, matches: value, isCaseSensitive: isCaseSensitive, context: &context) }
        case .mapping(let entries):
            return entries.contains { entry in propertyValue(entry.node, matches: value, isCaseSensitive: isCaseSensitive, context: &context) }
        case .scalar(let text, let isPlain):
            if case .term(let term) = value, term.kind == .word {
                let isNull = isPlain && ["", "~", "null", "Null", "NULL"].contains(text)
                if term.text.lowercased() == "null" { return isNull }
                if let comparison = NumericComparison(term.text), let number = Double(text.trimmingCharacters(in: .whitespaces)) {
                    return comparison.accepts(number)
                }
            }
            return evaluate(value, in: .propertyValue(text), isCaseSensitive: isCaseSensitive, context: &context)
        }
    }

    private mutating func matches(_ term: SearchTerm, in target: Target, isCaseSensitive: Bool, context: inout FileContext) -> Bool {
        let file = context.file
        switch target {
        case .note:
            if term.kind == .regularExpression {
                return regularExpressionMatches(term.text, in: file.path.name, isCaseSensitive: isCaseSensitive)
                    || regularExpressionMatches(term.text, in: file.path.rawValue, isCaseSensitive: isCaseSensitive)
                    || file.content.map { content in regularExpressionMatches(term.text, in: content, isCaseSensitive: isCaseSensitive) } == true
            }
            if nameMatches(term, of: file.path, isCaseSensitive: isCaseSensitive) { return true }
            if wordsMatch(term, in: Self.searchedPath(of: file.path), isCaseSensitive: isCaseSensitive) { return true }
            return contentMatches(term, isCaseSensitive: isCaseSensitive, context: &context)
        case .fileName:
            return substringMatches(term, in: file.path.name, isCaseSensitive: isCaseSensitive)
        case .filePath:
            return substringMatches(term, in: file.path.rawValue, isCaseSensitive: isCaseSensitive)
        case .content:
            return contentMatches(term, isCaseSensitive: isCaseSensitive, context: &context)
        case .tags(let tags):
            if term.kind == .regularExpression {
                return tags.contains { tag in regularExpressionMatches(term.text, in: tag, isCaseSensitive: isCaseSensitive) }
            }
            let searchedTag = term.text.hasPrefix("#") ? String(term.text.dropFirst()) : term.text
            return tags.contains { tag in TagSyntax.tag(tag, isWithin: searchedTag) }
        case .contentPart(let text), .propertyValue(let text):
            if term.kind == .regularExpression { return regularExpressionMatches(term.text, in: text, isCaseSensitive: isCaseSensitive) }
            return wordsMatch(term, in: text, isCaseSensitive: isCaseSensitive)
        }
    }

    /// Whether a plain word or phrase is in a file's name. A note's name is shown without
    /// `.md`, so a term that is only part of that extension (`md`, `.md`) does not find every
    /// note; a term reaching into it from the name (`Work.md`) still finds the note.
    private mutating func nameMatches(_ term: SearchTerm, of path: VaultPath, isCaseSensitive: Bool) -> Bool {
        guard DocumentKind(path: path) == .markdown else { return substringMatches(term, in: path.name, isCaseSensitive: isCaseSensitive) }
        if substringMatches(term, in: path.stem, isCaseSensitive: isCaseSensitive) { return true }
        let options: String.CompareOptions = isCaseSensitive ? [] : [.caseInsensitive]
        let isPartOfExtension = ("." + path.fileExtension).range(of: WikiLinkResolver.comparisonKey(term.text), options: options) != nil
        return !isPartOfExtension && substringMatches(term, in: path.name, isCaseSensitive: isCaseSensitive)
    }

    /// The path whose words plain search reads: without a note's `.md`, which every note shares.
    static func searchedPath(of path: VaultPath) -> String {
        DocumentKind(path: path) == .markdown ? (path.rawValue as NSString).deletingPathExtension : path.rawValue
    }

    /// Whether a note's name and path, read whole, could contain the word or phrase `term`
    /// through the note's extension alone (`md`, `.md`, `mark`), where plain search does not
    /// look. The index, which stores whole names and paths, leaves such terms to the matcher.
    public static func mayMatchNoteExtension(_ term: SearchTerm) -> Bool {
        guard term.kind != .regularExpression else { return false }
        let noteExtensions = ["md", "markdown"]
        let searchedText = WikiLinkResolver.comparisonKey(term.text)
        if noteExtensions.contains(where: { noteExtension in ("." + noteExtension).range(of: searchedText, options: .caseInsensitive) != nil }) { return true }
        return SearchTextTokens.queryTokens(of: term.text).contains { queryToken in
            noteExtensions.contains { noteExtension in noteExtension.hasPrefix(queryToken) }
        }
    }

    private mutating func contentMatches(_ term: SearchTerm, isCaseSensitive: Bool, context: inout FileContext) -> Bool {
        guard let content = context.file.content else { return false }
        if term.kind == .regularExpression { return regularExpressionMatches(term.text, in: content, isCaseSensitive: isCaseSensitive) }
        let foldsCase = !isCaseSensitive
        let queryTokens = queryTokens(of: term, foldsCase: foldsCase)
        guard !queryTokens.isEmpty else { return Self.symbolsMatch(term, in: content) }
        if context.contentTokens[foldsCase] == nil { context.contentTokens[foldsCase] = SearchTextTokens(content, foldsCase: foldsCase) }
        return context.contentTokens[foldsCase]?.contains(queryTokens, lastIsPrefix: term.kind == .word) == true
    }

    private mutating func wordsMatch(_ term: SearchTerm, in text: String, isCaseSensitive: Bool) -> Bool {
        let foldsCase = !isCaseSensitive
        let queryTokens = queryTokens(of: term, foldsCase: foldsCase)
        guard !queryTokens.isEmpty else { return Self.symbolsMatch(term, in: text) }
        return SearchTextTokens(text, foldsCase: foldsCase).contains(queryTokens, lastIsPrefix: term.kind == .word)
    }

    /// A term without words, such as an emoji, is looked for as written, as the index looks
    /// for it; punctuation or whitespace alone has nothing to look for and asks for nothing.
    private static func symbolsMatch(_ term: SearchTerm, in text: String) -> Bool {
        guard let symbols = SearchTextTokens.literalSymbols(of: term.text) else { return true }
        return text.range(of: symbols, options: .literal) != nil
    }

    private mutating func queryTokens(of term: SearchTerm, foldsCase: Bool) -> [String] {
        let key = (foldsCase ? "0" : "1") + term.text
        if let cached = queryTokensByTerm[key] { return cached }
        let queryTokens = SearchTextTokens.queryTokens(of: term.text, foldsCase: foldsCase)
        queryTokensByTerm[key] = queryTokens
        return queryTokens
    }

    /// The tags written in `text`, without their `#`.
    private static func tags(writtenIn text: String) -> [String] {
        let bridgedText = text as NSString
        return TagSyntax.pattern.matches(in: text, range: NSRange(location: 0, length: bridgedText.length)).map { match in bridgedText.substring(with: match.range(at: 1)) }
    }

    /// Names and paths are compared folded as the index stores them (`caseFoldedKey`), code
    /// unit by code unit as SQL's LIKE compares them, so the index can answer for the matcher.
    private mutating func substringMatches(_ term: SearchTerm, in text: String, isCaseSensitive: Bool) -> Bool {
        if term.kind == .regularExpression { return regularExpressionMatches(term.text, in: text, isCaseSensitive: isCaseSensitive) }
        let foldedText = isCaseSensitive ? WikiLinkResolver.comparisonKey(text) : WikiLinkResolver.caseFoldedKey(text)
        let foldedTerm = isCaseSensitive ? WikiLinkResolver.comparisonKey(term.text) : WikiLinkResolver.caseFoldedKey(term.text)
        return foldedText.range(of: foldedTerm, options: String.CompareOptions.literal) != nil
    }

    /// A pattern that runs past its time limit counts as no match, and
    /// `hasExceededRegularExpressionTimeLimit` records it so the search can report it.
    private mutating func regularExpressionMatches(_ pattern: String, in text: String, isCaseSensitive: Bool) -> Bool {
        guard let regularExpression = regularExpression(pattern, isCaseSensitive: isCaseSensitive) else { return false }
        do {
            return try TimeLimitedRegularExpression.firstMatch(of: regularExpression, in: text) != nil
        } catch TimeLimitedRegularExpression.Interruption.timeLimitExceeded {
            hasExceededRegularExpressionTimeLimit = true
            return false
        } catch {
            return false
        }
    }

    private mutating func regularExpression(_ pattern: String, isCaseSensitive: Bool) -> NSRegularExpression? {
        let key = (isCaseSensitive ? "1" : "0") + pattern
        if let cached = regularExpressions[key] { return cached }
        let compiled = try? NSRegularExpression(pattern: pattern, options: isCaseSensitive ? [] : [.caseInsensitive])
        if let compiled { regularExpressions[key] = compiled }
        return compiled
    }
}

/// `[duration:<5]` and `[duration:>5]` in a property search.
struct NumericComparison {
    let isLessThan: Bool
    let bound: Double

    init?(_ text: String) {
        guard let first = text.first, first == "<" || first == ">", let bound = Double(text.dropFirst().trimmingCharacters(in: .whitespaces)) else { return nil }
        isLessThan = first == "<"
        self.bound = bound
    }

    func accepts(_ number: Double) -> Bool { isLessThan ? number < bound : number > bound }
}

/// The lines, blocks, sections, and tasks `line:`, `block:`, `section:` and `task:` look in.
public enum SearchContentParts {
    private static let taskPattern = try? NSRegularExpression(pattern: "^\\s*(?:>\\s*)*(?:[-*+]|\\d+[.)])\\s+\\[(.)\\]\\s?(.*)$", options: [.anchorsMatchLines])

    public static func parts(of content: String, scope: SearchScope) -> [String] {
        switch scope {
        case .line:
            return lines(of: content)
        case .block:
            return blocks(of: content)
        case .section:
            return sections(of: content)
        case .task, .taskTodo, .taskDone:
            return tasks(of: content, scope: scope)
        default:
            return [content]
        }
    }

    /// The lines of `content`. A Windows line ending (`\r\n`) is one break, not two with an
    /// empty line between them that would split every paragraph of a synced note.
    static func lines(of content: String) -> [String] {
        content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    }

    /// Paragraphs and list items, as Obsidian divides a note into blocks.
    static func blocks(of content: String) -> [String] {
        var blocks: [String] = []
        var current: [String] = []
        func finish() { if !current.isEmpty { blocks.append(current.joined(separator: "\n")); current = [] } }
        for line in lines(of: content) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty { finish(); continue }
            if isListItem(trimmedLine) || trimmedLine.hasPrefix("#") { finish() }
            current.append(line)
        }
        finish()
        return blocks
    }

    /// Text between headings.
    static func sections(of content: String) -> [String] {
        var sections: [String] = []
        var current: [String] = []
        var fences = CodeFenceTracker()
        for line in lines(of: content) {
            let isCode = fences.isCodeLine(line.trimmingCharacters(in: .whitespaces))
            if !isCode, MarkdownEditing.headingLevel(of: line) != nil, !current.isEmpty {
                sections.append(current.joined(separator: "\n"))
                current = []
            }
            current.append(line)
        }
        if !current.isEmpty { sections.append(current.joined(separator: "\n")) }
        return sections
    }

    static func tasks(of content: String, scope: SearchScope) -> [String] {
        guard let taskPattern else { return [] }
        let text = content as NSString
        return taskPattern.matches(in: content, range: NSRange(location: 0, length: text.length)).compactMap { match in
            let status = text.substring(with: match.range(at: 1))
            if scope == .taskTodo && status != " " { return nil }
            if scope == .taskDone && status == " " { return nil }
            return text.substring(with: match.range(at: 2))
        }
    }

    private static func isListItem(_ trimmedLine: String) -> Bool {
        trimmedLine.range(of: "^(?:[-*+]|\\d+[.)])\\s", options: .regularExpression) != nil
    }
}

// MARK: - Excerpts

/// A place in a note that matched a search, with the surrounding text to show.
public struct SearchMatch: Hashable, Sendable {
    /// The line around the match, shortened.
    public let excerpt: String
    /// The matched words within `excerpt`, as UTF-16 offsets.
    public let highlightedRanges: [Range<Int>]
    /// Where the first match is in the note's text (UTF-16), frontmatter included.
    public let location: Int
    public let length: Int

    public init(excerpt: String, highlightedRanges: [Range<Int>], location: Int, length: Int) {
        self.excerpt = excerpt; self.highlightedRanges = highlightedRanges; self.location = location; self.length = length
    }
}

public enum SearchExcerpts {
    /// Characters of context kept on each side of the first match in a line.
    static let contextLength = 70

    /// The places in `content` that the query's words, phrases, and regular expressions
    /// match, one per line, in order. Excluded (`-`) terms are not highlighted.
    public static func matches(of expression: SearchExpression, in content: String, limit: Int) -> (matches: [SearchMatch], totalCount: Int) {
        var terms: [(SearchTerm, Bool)] = []
        collectHighlightedTerms(expression, isCaseSensitive: false, into: &terms)
        guard !terms.isEmpty else { return ([], 0) }
        let text = content as NSString
        var ranges: [NSRange] = []
        var tokensByCase: [Bool: SearchTextTokens] = [:]
        for (term, isCaseSensitive) in terms {
            switch term.kind {
            case .regularExpression:
                let options: NSRegularExpression.Options = isCaseSensitive ? [] : [.caseInsensitive]
                guard let regularExpression = try? NSRegularExpression(pattern: term.text, options: options) else { continue }
                // Excerpts are extras: a pattern too slow to finish shows none.
                let matches = (try? TimeLimitedRegularExpression.matches(of: regularExpression, in: content)) ?? []
                ranges += matches.map(\.range).filter { range in range.length > 0 }
            case .word, .phrase:
                let foldsCase = !isCaseSensitive
                let queryTokens = SearchTextTokens.queryTokens(of: term.text, foldsCase: foldsCase)
                guard !queryTokens.isEmpty else {
                    if let symbols = SearchTextTokens.literalSymbols(of: term.text) { ranges += SearchTextTokens.literalRanges(of: symbols, in: text) }
                    continue
                }
                if tokensByCase[foldsCase] == nil { tokensByCase[foldsCase] = SearchTextTokens(content, foldsCase: foldsCase) }
                ranges += tokensByCase[foldsCase]?.matches(of: queryTokens, lastIsPrefix: term.kind == .word) ?? []
            }
        }
        guard !ranges.isEmpty else { return ([], 0) }
        ranges.sort { leftRange, rightRange in leftRange.location < rightRange.location }
        var matchesByLine: [(lineRange: NSRange, ranges: [NSRange])] = []
        for range in ranges {
            let lineRange = text.lineRange(for: NSRange(location: range.location, length: 0))
            if let last = matchesByLine.last, last.lineRange == lineRange {
                matchesByLine[matchesByLine.count - 1].ranges.append(range)
            } else {
                matchesByLine.append((lineRange, [range]))
            }
        }
        let matches = matchesByLine.prefix(limit).map { line in excerpt(for: line.ranges, in: line.lineRange, of: text) }
        return (matches, matchesByLine.count)
    }

    /// The line around `range` of `text`, shortened, with the range marked, as search and
    /// backlinks show it.
    public static func excerpt(around range: NSRange, in text: NSString) -> SearchMatch {
        excerpt(for: [range], in: text.lineRange(for: NSRange(location: range.location, length: 0)), of: text)
    }

    private static func excerpt(for ranges: [NSRange], in lineRange: NSRange, of text: NSString) -> SearchMatch {
        var contentEnd = NSMaxRange(lineRange)
        while contentEnd > lineRange.location, [10, 13].contains(text.character(at: contentEnd - 1)) { contentEnd -= 1 }
        let first = ranges[0]
        let start = max(lineRange.location, first.location - contextLength)
        let end = min(contentEnd, max(NSMaxRange(first) + contextLength, start + 2 * contextLength))
        // Whole composed characters only, so an emoji or accent is never cut in half.
        let excerptRange = text.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: max(0, end - start)))
        let prefix = excerptRange.location > lineRange.location ? "…" : ""
        let suffix = NSMaxRange(excerptRange) < contentEnd ? "…" : ""
        let body = text.substring(with: excerptRange)
        let trimmedBody = body.trimmingCharacters(in: .whitespaces)
        // Positions move back by whatever trimming removed from the start, with or without
        // an ellipsis before it, and whichever whitespace it was (a tab, or the ideographic
        // space that indents Japanese paragraphs).
        let leadingWhitespaceLength = body.unicodeScalars.prefix { scalar in CharacterSet.whitespaces.contains(scalar) }
            .reduce(0) { length, scalar in length + scalar.utf16.count }
        let excerpt = prefix + trimmedBody + suffix
        let prefixLength = (prefix as NSString).length
        let shift = prefixLength - excerptRange.location - leadingWhitespaceLength
        let bodyEnd = prefixLength + (trimmedBody as NSString).length
        let highlightedRanges = ranges.compactMap { range -> Range<Int>? in
            // A regular expression may match trimmed whitespace; only what is shown is marked.
            let lower = max(range.location + shift, prefixLength), upper = min(NSMaxRange(range) + shift, bodyEnd)
            guard lower < upper else { return nil }
            return lower..<upper
        }
        return SearchMatch(excerpt: excerpt, highlightedRanges: highlightedRanges, location: first.location, length: first.length)
    }

    private static func collectHighlightedTerms(_ expression: SearchExpression, isCaseSensitive: Bool, into terms: inout [(SearchTerm, Bool)]) {
        switch expression {
        case .all(let items), .any(let items):
            for item in items { collectHighlightedTerms(item, isCaseSensitive: isCaseSensitive, into: &terms) }
        case .not, .property:
            return
        case .term(let term):
            terms.append((term, isCaseSensitive))
        case .scoped(let scope, let operand):
            switch scope {
            case .file, .path, .tag: return
            case .matchCase: collectHighlightedTerms(operand, isCaseSensitive: true, into: &terms)
            case .ignoreCase: collectHighlightedTerms(operand, isCaseSensitive: false, into: &terms)
            default: collectHighlightedTerms(operand, isCaseSensitive: isCaseSensitive, into: &terms)
            }
        }
    }
}
