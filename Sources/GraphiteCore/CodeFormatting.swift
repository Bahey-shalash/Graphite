import Foundation

/// Tidies the code of a fenced block: indentation by its structure, trailing spaces, runs
/// of blank lines, and a few spaces inside lines (`main(){` becomes `main() {`, `f(a,b)`
/// becomes `f(a, b)`). Strings and comments are never changed inside, and a language whose
/// indentation is its meaning (Python, YAML) keeps its indentation. It is lexical, as the
/// highlighting is: code is indented by its brackets and block keywords, not parsed.
public enum CodeFormatter {
    /// Whether Graphite formats code in `language`.
    public static func formats(_ language: CodeLanguage) -> Bool {
        CodeFormattingStyle.style(for: language) != nil
    }

    /// `code`, the text between a block's fences (its last line break included when it has
    /// one), formatted; nil when Graphite does not format the language.
    public static func formatted(_ code: String, language: CodeLanguage) -> String? {
        guard let style = CodeFormattingStyle.style(for: language) else { return nil }
        let units = Array(code.utf16)
        let lineBreak = code.contains("\r\n") ? "\r\n" : "\n"
        var lineRanges = CodeSyntaxHighlighter.lineRanges(in: units)
        // Text ending in a line break gives an empty last range, which is not a line.
        let endsWithLineBreak = units.last == CodeUnits.lineFeed || units.last == CodeUnits.carriageReturn
        if endsWithLineBreak, lineRanges.count > 1 { lineRanges.removeLast() }
        var formatter = LineFormatter(language: language, style: style, units: units, lineRanges: lineRanges)
        let lines = formatter.formattedLines()
        guard !lines.isEmpty else { return code }
        return lines.joined(separator: lineBreak) + (endsWithLineBreak ? lineBreak : "")
    }
}

/// How one language is formatted.
struct CodeFormattingStyle {
    enum Structure {
        /// Indentation is left as written.
        case none
        /// Brackets alone: `{`, `(` and `[`.
        case brackets
        /// Brackets and block keywords, read by `CodeBlockKeywords`.
        case keywords
    }

    let structure: Structure
    /// The indentation used when the code has none to follow.
    let defaultIndentation: String
    /// `f(a,b)` becomes `f(a, b)`.
    let spacesAfterCommas: Bool
    /// `){` and `else{` take a space before `{`, and `if(` one before `(`.
    let spacesAroundBlockBraces: Bool
    /// Blank lines kept in a row.
    let maximumBlankLines: Int
    /// C's `#include` and `#define` lines start at the left edge.
    let preprocessorLinesAtLeftEdge: Bool

    static func style(for language: CodeLanguage) -> CodeFormattingStyle? {
        switch language.name {
        case "c", "cpp", "objectivec", "csharp", "java", "kotlin", "javascript", "typescript", "swift", "rust":
            let indentation = ["javascript", "typescript"].contains(language.name) ? "  " : "    "
            return CodeFormattingStyle(structure: .brackets, defaultIndentation: indentation, spacesAfterCommas: true, spacesAroundBlockBraces: true,
                                       maximumBlankLines: 1, preprocessorLinesAtLeftEdge: ["c", "cpp", "objectivec", "csharp"].contains(language.name))
        case "go":
            return CodeFormattingStyle(structure: .brackets, defaultIndentation: "\t", spacesAfterCommas: true, spacesAroundBlockBraces: true,
                                       maximumBlankLines: 1, preprocessorLinesAtLeftEdge: false)
        case "json", "css":
            return CodeFormattingStyle(structure: .brackets, defaultIndentation: "  ", spacesAfterCommas: language.name == "json",
                                       spacesAroundBlockBraces: false, maximumBlankLines: 1, preprocessorLinesAtLeftEdge: false)
        case "vhdl", "verilog", "matlab", "lua", "ruby":
            let indentation = ["lua", "ruby"].contains(language.name) ? "  " : "    "
            return CodeFormattingStyle(structure: .keywords, defaultIndentation: indentation, spacesAfterCommas: true, spacesAroundBlockBraces: false,
                                       maximumBlankLines: 1, preprocessorLinesAtLeftEdge: false)
        case "shell", "latex":
            return CodeFormattingStyle(structure: .keywords, defaultIndentation: language.name == "shell" ? "    " : "  ", spacesAfterCommas: false,
                                       spacesAroundBlockBraces: false, maximumBlankLines: 1, preprocessorLinesAtLeftEdge: false)
        case "python":
            return CodeFormattingStyle(structure: .none, defaultIndentation: "    ", spacesAfterCommas: true, spacesAroundBlockBraces: false,
                                       maximumBlankLines: 2, preprocessorLinesAtLeftEdge: false)
        case "sql":
            return CodeFormattingStyle(structure: .none, defaultIndentation: "    ", spacesAfterCommas: true, spacesAroundBlockBraces: false,
                                       maximumBlankLines: 1, preprocessorLinesAtLeftEdge: false)
        case "yaml", "assembly", "markup":
            return CodeFormattingStyle(structure: .none, defaultIndentation: "  ", spacesAfterCommas: false, spacesAroundBlockBraces: false,
                                       maximumBlankLines: 1, preprocessorLinesAtLeftEdge: false)
        default:
            // Markdown's trailing spaces are line breaks, and its indentation is structure.
            return nil
        }
    }
}

/// Formats the lines of one block, in order.
private struct LineFormatter {
    let language: CodeLanguage
    let style: CodeFormattingStyle
    let units: [UInt16]
    let lineRanges: [Range<Int>]
    private var keywords: CodeBlockKeywords
    private let indentation: String

    init(language: CodeLanguage, style: CodeFormattingStyle, units: [UInt16], lineRanges: [Range<Int>]) {
        self.language = language
        self.style = style
        self.units = units
        self.lineRanges = lineRanges
        keywords = CodeBlockKeywords(language: language)
        indentation = Self.indentation(of: units, lineRanges: lineRanges, ignoresPreprocessorLines: style.preprocessorLinesAtLeftEdge)
            ?? style.defaultIndentation
    }

    /// The indentation the code already uses: a tab, or the narrowest run of two to eight
    /// spaces that starts a line. Nil when no line is indented that way. A `#define` indented
    /// by mistake says nothing about the code's indentation.
    private static func indentation(of units: [UInt16], lineRanges: [Range<Int>], ignoresPreprocessorLines: Bool) -> String? {
        var narrowestSpaces = Int.max
        for lineRange in lineRanges where !lineRange.isEmpty {
            if units[lineRange.lowerBound] == CodeUnits.tab { return "\t" }
            var spaces = 0
            while lineRange.lowerBound + spaces < lineRange.upperBound, units[lineRange.lowerBound + spaces] == CodeUnits.space { spaces += 1 }
            guard lineRange.lowerBound + spaces < lineRange.upperBound else { continue }
            if ignoresPreprocessorLines, units[lineRange.lowerBound + spaces] == CodeUnits.hash { continue }
            if spaces >= 2 { narrowestSpaces = min(narrowestSpaces, spaces) }
        }
        return (2...8).contains(narrowestSpaces) ? String(repeating: " ", count: narrowestSpaces) : nil
    }

    /// One line as the highlighter reads it.
    private struct ScannedLine {
        let range: Range<Int>
        let entryState: CodeLineState
        let exitState: CodeLineState
        /// Whether each unit of the line is code, not string or comment text.
        let isCode: [Bool]
    }

    private func scannedLines() -> [ScannedLine] {
        var highlighter = CodeLineHighlighter(language: language)
        return lineRanges.map { lineRange in
            let entryState = highlighter.state
            let tokens = highlighter.tokens(inLine: lineRange, of: units)
            var isCode = [Bool](repeating: true, count: lineRange.count)
            for token in tokens where token.kind == .string || token.kind == .comment {
                let start = max(token.range.location, lineRange.lowerBound) - lineRange.lowerBound
                let end = min(NSMaxRange(token.range), lineRange.upperBound) - lineRange.lowerBound
                if start < end { for offset in start..<end { isCode[offset] = false } }
            }
            return ScannedLine(range: lineRange, entryState: entryState, exitState: highlighter.state, isCode: isCode)
        }
    }

    mutating func formattedLines() -> [String] {
        var output: [String] = []
        var pendingBlankLines = 0
        /// Whether the last line written opened a block, after which a blank line is dropped.
        var lastLineOpened = false
        /// The indentation of the last line that opened a block comment, for its other lines.
        var commentIndentation = ""
        for line in scannedLines() {
            let isInsideString = if case .string = line.entryState { true } else { false }
            if isInsideString {
                // The text of a string spanning lines is kept exactly, its blank lines too.
                output.append(contentsOf: Array(repeating: "", count: pendingBlankLines))
                pendingBlankLines = 0
                output.append(String(decoding: units[line.range], as: UTF16.self))
                lastLineOpened = false
                continue
            }
            let content = tidiedContent(of: line)
            if content.isEmpty, case .normal = line.entryState {
                pendingBlankLines += 1
                continue
            }
            var lineIndentation: String
            if case .blockComment = line.entryState {
                // A comment's later lines under its first: ` * ` lines one space in.
                lineIndentation = commentIndentation + (content.hasPrefix("*") ? " " : (style.structure == .none ? "" : indentation))
                if style.structure == .none { lineIndentation = leadingWhitespace(of: line) }
            } else if style.structure == .none {
                lineIndentation = leadingWhitespace(of: line)
            } else if style.preprocessorLinesAtLeftEdge, content.hasPrefix("#") {
                lineIndentation = ""
            } else {
                let depthAtLine = keywords.indentationDepth(ofLineWithCode: codeUnits(of: line))
                lineIndentation = String(repeating: indentation, count: max(0, depthAtLine))
            }
            let depthBefore = keywords.depth
            let readsStructure = style.structure != .none && !(style.preprocessorLinesAtLeftEdge && content.hasPrefix("#"))
            if readsStructure { keywords.advance(pastLineWithCode: codeUnits(of: line)) }
            let closesBlock = readsStructure && keywords.lastLineStartedWithClosing
            if pendingBlankLines > 0 {
                // No blank line just inside a block's opening or closing line.
                let dropsBlankLines = output.isEmpty || (style.structure != .none && (lastLineOpened || closesBlock))
                if !dropsBlankLines { output.append(contentsOf: Array(repeating: "", count: min(pendingBlankLines, style.maximumBlankLines))) }
                pendingBlankLines = 0
            }
            output.append(lineIndentation + content)
            if case .blockComment = line.exitState, !(line.entryState.isBlockComment) { commentIndentation = lineIndentation }
            lastLineOpened = keywords.depth > depthBefore
        }
        return output
    }

    private func leadingWhitespace(of line: ScannedLine) -> String {
        var end = line.range.lowerBound
        while end < line.range.upperBound, CodeUnits.isSpace(units[end]) { end += 1 }
        return String(decoding: units[line.range.lowerBound..<end], as: UTF16.self)
    }

    /// The line's units with string and comment text blanked, which keywords and brackets
    /// are read from.
    private func codeUnits(of line: ScannedLine) -> [UInt16] {
        var code = Array(units[line.range])
        for offset in code.indices where !line.isCode[offset] { code[offset] = CodeUnits.space }
        return code
    }

    /// The line without its indentation and trailing spaces, with spaces added inside it
    /// where the style asks, in code only. A line that ends inside a string keeps its end.
    private func tidiedContent(of line: ScannedLine) -> String {
        var start = line.range.lowerBound
        if !line.entryState.isString { while start < line.range.upperBound, CodeUnits.isSpace(units[start]) { start += 1 } }
        var end = line.range.upperBound
        if !line.exitState.isString { while end > start, CodeUnits.isSpace(units[end - 1]) { end -= 1 } }
        var tidied: [UInt16] = []
        tidied.reserveCapacity(end - start + 8)
        var index = start
        while index < end {
            let unit = units[index]
            let offset = index - line.range.lowerBound
            tidied.append(unit)
            index += 1
            guard line.isCode[offset], index < end, line.isCode[index - line.range.lowerBound] else { continue }
            let nextUnit = units[index]
            if style.spacesAfterCommas, unit == CodeUnits.comma, !CodeUnits.isSpace(nextUnit),
               ![CodeUnits.closingParenthesis, CodeUnits.closingBracket, CodeUnits.closingBrace, CodeUnits.comma].contains(nextUnit) {
                tidied.append(CodeUnits.space)
            } else if style.spacesAroundBlockBraces, unit == CodeUnits.closingParenthesis, nextUnit == CodeUnits.openingBrace {
                tidied.append(CodeUnits.space)
            } else if style.spacesAroundBlockBraces, unit == CodeUnits.closingBrace, isWord(at: index, oneOf: Self.wordsAfterClosingBrace, lineEnd: end) {
                tidied.append(CodeUnits.space)
            } else if style.spacesAroundBlockBraces, nextUnit == CodeUnits.openingBrace || nextUnit == CodeUnits.openingParenthesis,
                      endsWord(at: index, oneOf: nextUnit == CodeUnits.openingBrace ? Self.wordsBeforeBrace : Self.wordsBeforeParenthesis, lineStart: start) {
                tidied.append(CodeUnits.space)
            }
        }
        return String(decoding: tidied, as: UTF16.self)
    }

    private static let wordsAfterClosingBrace: Set<String> = ["else", "catch", "finally", "while"]
    private static let wordsBeforeBrace: Set<String> = ["else", "try", "do", "finally", "defer", "repeat"]
    private static let wordsBeforeParenthesis: Set<String> = ["if", "for", "while", "switch", "catch", "foreach", "using", "lock", "when", "guard"]

    private func isIdentifierUnit(_ unit: UInt16) -> Bool {
        CodeUnits.isASCIILetter(unit) || CodeUnits.isDigit(unit) || unit == CodeUnits.underscore
    }

    /// Whether one of `words` starts at `index` and ends there as a word.
    private func isWord(at index: Int, oneOf words: Set<String>, lineEnd: Int) -> Bool {
        var end = index
        while end < lineEnd, isIdentifierUnit(units[end]) { end += 1 }
        return end > index && words.contains(String(decoding: units[index..<end], as: UTF16.self))
    }

    /// Whether one of `words` ends just before `index`, as a whole word.
    private func endsWord(at index: Int, oneOf words: Set<String>, lineStart: Int) -> Bool {
        var start = index
        while start > lineStart, isIdentifierUnit(units[start - 1]) { start -= 1 }
        return start < index && words.contains(String(decoding: units[start..<index], as: UTF16.self))
    }
}

extension CodeLineState {
    var isString: Bool { if case .string = self { true } else { false } }
    var isBlockComment: Bool { if case .blockComment = self { true } else { false } }
}

/// The blocks code is nested in, line by line: brackets, and for some languages block
/// keywords (`begin … end`, `if … end if`, `then … fi`). Each open block adds a level of
/// indentation, some keywords two (a `case` whose `when` lines sit one level in).
struct CodeBlockKeywords {
    private let language: CodeLanguage
    /// The open blocks, innermost last: what opened each, and the levels it adds.
    private var openBlocks: [(opener: String, levels: Int)] = []
    /// Whether the last line read started by closing a block, as `}` or `end if;` do.
    private(set) var lastLineStartedWithClosing = false

    init(language: CodeLanguage) {
        self.language = language
    }

    var depth: Int { openBlocks.reduce(0) { total, block in total + block.levels } }

    /// A bracket or a word of a line's code, in order, with whether only closing brackets
    /// and words, spaces and `;` or `,` come before it.
    private struct Item {
        let text: String
        let isLeading: Bool
    }

    private enum Role {
        case none, open(levels: Int), close
        /// A line such as `else` or `when` sits one level out, and changes no block.
        case middle
    }

    /// The depth a line is indented to: the depth before it, less the blocks it starts by
    /// closing and the level a middle keyword it starts with steps out.
    func indentationDepth(ofLineWithCode code: [UInt16]) -> Int {
        var copy = self
        var lineDepth = depth
        let items = copy.items(of: code)
        let wordList = items.map(\.text)
        leadingItems: for (itemIndex, item) in items.enumerated() where item.isLeading {
            switch copy.role(of: item.text, at: itemIndex, in: wordList, code: code) {
            case .close:
                copy.closeBlock()
                lineDepth = copy.depth
            case .middle:
                lineDepth = copy.depth - 1
            case .open, .none:
                break leadingItems
            }
        }
        // A shell `case` pattern (`start|begin)`) sits one level out, before its commands.
        if language.name == "shell", copy.openBlocks.last?.opener == "case", wordList.contains(")"), !wordList.contains("(") {
            lineDepth = min(lineDepth, copy.depth - 1)
        }
        return lineDepth
    }

    mutating func advance(pastLineWithCode code: [UInt16]) {
        let items = items(of: code)
        let wordList = items.map(\.text)
        lastLineStartedWithClosing = false
        for (itemIndex, item) in items.enumerated() {
            switch role(of: item.text, at: itemIndex, in: wordList, code: code) {
            case .open(let levels):
                openBlocks.append((item.text, levels))
            case .close:
                if item.isLeading { lastLineStartedWithClosing = true }
                closeBlock()
            case .middle:
                if item.isLeading { lastLineStartedWithClosing = true }
            case .none:
                break
            }
        }
    }

    private mutating func closeBlock() {
        if !openBlocks.isEmpty { openBlocks.removeLast() }
    }

    private var usesKeywords: Bool { ["vhdl", "verilog", "matlab", "lua", "ruby", "shell", "latex"].contains(language.name) }

    private func items(of code: [UInt16]) -> [Item] {
        var items: [Item] = []
        var isLeading = true
        var index = 0
        while index < code.count {
            let unit = code[index]
            if CodeUnits.isSpace(unit) || unit == CodeUnits.semicolon || unit == CodeUnits.comma {
                index += 1
                continue
            }
            if [CodeUnits.openingBrace, CodeUnits.openingParenthesis, CodeUnits.openingBracket].contains(unit) {
                items.append(Item(text: String(decoding: [unit], as: UTF16.self), isLeading: false))
                isLeading = false
                index += 1
                continue
            }
            if [CodeUnits.closingBrace, CodeUnits.closingParenthesis, CodeUnits.closingBracket].contains(unit) {
                items.append(Item(text: String(decoding: [unit], as: UTF16.self), isLeading: isLeading))
                index += 1
                continue
            }
            let isWordStart = CodeUnits.isASCIILetter(unit) || unit == CodeUnits.underscore || (unit == CodeUnits.backslash && language.name == "latex")
            if usesKeywords, isWordStart {
                var end = index + 1
                while end < code.count, CodeUnits.isASCIILetter(code[end]) || CodeUnits.isDigit(code[end]) || code[end] == CodeUnits.underscore { end += 1 }
                var word = String(decoding: code[index..<end], as: UTF16.self)
                if language.ignoresCase { word = word.lowercased() }
                if language.name == "latex", word == "\\begin" || word == "\\end", end < code.count, code[end] == CodeUnits.openingBrace {
                    // `\begin{itemize}`: the environment's name decides; its braces are part of it.
                    var closing = end + 1
                    while closing < code.count, code[closing] != CodeUnits.closingBrace { closing += 1 }
                    let environment = String(decoding: code[(end + 1)..<min(closing, code.count)], as: UTF16.self)
                    items.append(Item(text: environment == "document" ? "\\document" : word, isLeading: isLeading && word == "\\end"))
                    isLeading = false
                    index = min(closing + 1, code.count)
                    continue
                }
                items.append(Item(text: word, isLeading: isLeading))
                index = end
                // A word that does not close or step out ends the leading part; `role` decides.
                if !Self.leadingWords.contains(word) { isLeading = false }
                continue
            }
            isLeading = false
            index += 1
        }
        return items
    }

    /// Words that can start a line before its other code without ending its leading part.
    private static let leadingWords: Set<String> = [
        "end", "else", "elsif", "elseif", "elif", "when", "begin", "fi", "done", "esac", "until", "catch", "otherwise", "case", "rescue",
        "ensure", "endcase", "endmodule", "endfunction", "endtask", "endclass", "endinterface", "endpackage", "endgenerate", "join",
        "join_any", "join_none", "endprogram", "endgroup", "endproperty", "endsequence", "endclocking", "endprimitive", "endspecify",
        "endtable", "endconfig", "endchecker", "\\end",
    ]

    private func role(of text: String, at itemIndex: Int, in items: [String], code: [UInt16]) -> Role {
        switch text {
        case "{", "(", "[":
            return .open(levels: 1)
        case "}", ")", "]":
            if language.name == "shell", text == ")", openBlocks.last?.opener == "case", !items.contains("(") { return .middle }
            return .close
        default:
            break
        }
        switch language.name {
        case "vhdl": return vhdlRole(of: text, at: itemIndex, in: items, code: code)
        case "verilog": return verilogRole(of: text, at: itemIndex, in: items)
        case "matlab": return matlabRole(of: text, at: itemIndex, in: items)
        case "lua": return luaRole(of: text, at: itemIndex, in: items)
        case "ruby": return rubyRole(of: text, at: itemIndex, in: items)
        case "shell": return shellRole(of: text, at: itemIndex, in: items)
        case "latex": return text == "\\begin" ? .open(levels: 1) : text == "\\end" ? .close : .none
        default: return .none
        }
    }

    /// The index of a line's first word after a label (`p_clock : process`, not `x := 1`).
    private func firstWordIndex(in items: [String], code: [UInt16]) -> Int {
        guard let firstColon = code.firstIndex(of: CodeUnits.colon), firstColon + 1 < code.count, code[firstColon + 1] != CodeUnits.equals,
              items.count >= 2 else { return 0 }
        let beforeColon = String(decoding: code[..<firstColon], as: UTF16.self).trimmingCharacters(in: .whitespaces)
        guard beforeColon.allSatisfy({ character in character.isLetter || character.isNumber || character == "_" }) else { return 0 }
        let labeledWords: Set<String> = ["process", "block", "for", "if", "while", "loop", "case", "postponed", "entity", "component", "with"]
        return labeledWords.contains(items[1]) ? 1 : 0
    }

    private func vhdlRole(of word: String, at itemIndex: Int, in items: [String], code: [UInt16]) -> Role {
        let firstIndex = firstWordIndex(in: items, code: code)
        guard itemIndex == firstIndex else {
            // `if enable = '1' then x <= y; end if;` opens and closes on one line.
            return word == "end" && itemIndex > firstIndex ? .close : .none
        }
        let declarativeBlocks: Set<String> = ["process", "architecture", "function", "procedure", "pure", "impure", "block", "for", "if", "entity", "postponed"]
        switch word {
        case "end": return .close
        case "else", "elsif": return .middle
        case "begin": return declarativeBlocks.contains(openBlocks.last?.opener ?? "") ? .middle : .none
        case "when": return openBlocks.last?.opener == "case" ? .middle : .none
        case "if", "loop", "process", "block", "postponed": return .open(levels: 1)
        case "case": return .open(levels: 2)
        case "for", "while": return items.contains("loop") || items.contains("generate") ? .open(levels: 1) : .none
        case "entity", "architecture", "package", "configuration", "context", "function", "procedure", "pure", "impure":
            return items.contains("is") ? .open(levels: 1) : .none
        case "component": return firstIndex == 0 ? .open(levels: 1) : .none
        case "type": return ["record", "protected"].contains(items.last ?? "") ? .open(levels: 1) : .none
        default: return .none
        }
    }

    private static let verilogOpeners: Set<String> = [
        "begin", "case", "casex", "casez", "randcase", "module", "macromodule", "function", "task", "class", "interface", "package", "generate",
        "fork", "program", "covergroup", "property", "sequence", "clocking", "primitive", "specify", "table", "config", "checker",
    ]
    private static let verilogClosers: Set<String> = [
        "end", "endcase", "endmodule", "endfunction", "endtask", "endclass", "endinterface", "endpackage", "endgenerate", "join", "join_any",
        "join_none", "endprogram", "endgroup", "endproperty", "endsequence", "endclocking", "endprimitive", "endspecify", "endtable",
        "endconfig", "endchecker",
    ]

    private func verilogRole(of word: String, at itemIndex: Int, in items: [String]) -> Role {
        if Self.verilogClosers.contains(word) { return .close }
        guard Self.verilogOpeners.contains(word) else { return .none }
        let earlierWords = Set(items[..<itemIndex])
        // Prototypes and statements that name a block without opening one.
        if ["function", "task"].contains(word), !earlierWords.isDisjoint(with: ["extern", "pure", "import", "export"]) { return .none }
        if word == "fork", !earlierWords.isDisjoint(with: ["wait", "disable"]) { return .none }
        if word == "class", earlierWords.contains("typedef") { return .none }
        if ["property", "sequence"].contains(word), !earlierWords.isDisjoint(with: ["assert", "assume", "cover", "expect", "restrict"]) { return .none }
        if word == "interface", earlierWords.contains("virtual") { return .none }
        return .open(levels: 1)
    }

    private func matlabRole(of word: String, at itemIndex: Int, in items: [String]) -> Role {
        // `x(end)` indexes; a word inside brackets opens or closes nothing.
        var bracketDepth = 0
        for item in items[..<itemIndex] {
            if item == "(" || item == "[" || item == "{" { bracketDepth += 1 }
            if item == ")" || item == "]" || item == "}" { bracketDepth -= 1 }
        }
        guard bracketDepth <= 0 else { return .none }
        switch word {
        case "end": return .close
        case "else", "elseif", "catch": return itemIndex == 0 ? .middle : .none
        case "case", "otherwise": return itemIndex == 0 && openBlocks.last?.opener == "switch" ? .middle : .none
        case "switch": return .open(levels: 2)
        case "function", "if", "for", "parfor", "while", "try", "classdef", "properties", "methods", "events", "enumeration", "arguments", "spmd":
            return .open(levels: 1)
        default: return .none
        }
    }

    private func luaRole(of word: String, at itemIndex: Int, in items: [String]) -> Role {
        switch word {
        case "end", "until": return .close
        case "else", "elseif": return itemIndex == 0 ? .middle : .none
        case "then": return items.first == "elseif" ? .none : .open(levels: 1)
        case "function", "do", "repeat": return .open(levels: 1)
        default: return .none
        }
    }

    private func rubyRole(of word: String, at itemIndex: Int, in items: [String]) -> Role {
        switch word {
        case "end": return .close
        case "else", "elsif", "when", "rescue", "ensure", "in": return itemIndex == 0 ? .middle : .none
        case "def", "class", "module", "if", "unless", "while", "until", "case", "begin", "for":
            // `return x if y` modifies a statement; only a line's first word opens a block.
            return itemIndex == 0 ? .open(levels: 1) : .none
        case "do": return ["while", "until", "for"].contains(items.first ?? "") ? .none : .open(levels: 1)
        default: return .none
        }
    }

    private func shellRole(of word: String, at itemIndex: Int, in items: [String]) -> Role {
        switch word {
        case "fi", "done", "esac": return .close
        case "else", "elif": return itemIndex == 0 ? .middle : .none
        case "then": return items.first == "elif" ? .none : .open(levels: 1)
        case "do": return .open(levels: 1)
        case "case": return .open(levels: 2)
        default: return .none
        }
    }
}
