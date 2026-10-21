import Foundation

/// Prepares a note's math for the reading view: display math in table cells made inline,
/// every formula protected from Markdown parsing, and formulas with equation numbers kept
/// between `ReadingMarkers` for the view to lay out.
package enum ReadingMathPreparation {
    private static let tableDisplayMathPattern = ReadingMathPreparationPattern.tableDisplayMathPattern.compiled()
    /// `$$…$$` within a line, or inline `$…$` as `MarkdownInlineMathSyntax` reads it, in one
    /// pass over each line (`InlineMathRuleTests` holds the second half to that rule).
    private static let mathSpanPattern = ReadingMathPreparationPattern.mathSpanPattern.compiled()
    private static let quotePrefixPattern = ReadingMathPreparationPattern.quotePrefixPattern.compiled()

    /// A `$$…$$` inside a table row would render as a block and break the row, so it is
    /// shown as inline math there. A table written in a code block is left as written.
    static func displayMathInTableCellsMadeInline(_ markdown: String) -> String {
        guard markdown.contains("$$") else { return markdown }
        var fenceTracker = CodeFenceTracker()
        return markdown.components(separatedBy: "\n").map { line in
            if fenceTracker.isCodeLine(untrimmedLine: line) { return line }
            guard line.trimmingCharacters(in: .whitespaces).hasPrefix("|") else { return line }
            let source = line as NSString
            return tableDisplayMathPattern.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: source.length), withTemplate: "\\$$1\\$")
        }.joined(separator: "\n")
    }

    /// Makes every formula reach the math renderer exactly as written. The renderer finds
    /// math in the text Markdown leaves behind, so a display block is put on one line (a
    /// line break would split it), and Markdown punctuation inside math is backslash-escaped
    /// so `\\{`, `\\\\`, `*` and `_` survive parsing as LaTeX. Code is left alone. With the
    /// text comes the index in `markdown` of the line each line of the result starts with:
    /// a display block written over several lines becomes one.
    static func protectingMathKeepingLineIndices(in markdown: String) -> (text: String, lineIndices: [Int]) {
        let lines = markdown.components(separatedBy: "\n")
        let mathLines = DisplayMathLines(lines)
        var fenceTracker = CodeFenceTracker()
        var outputLines: [String] = []
        var outputLineIndices: [Int] = []
        var lineIndex = 0
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let prefixLength = quotePrefixLength(of: line)
            let content = String(line.dropFirst(prefixLength))
            outputLineIndices.append(lineIndex)
            if fenceTracker.isCodeLine(untrimmedLine: content) {
                outputLines.append(line)
                lineIndex += 1
                continue
            }
            guard let opening = mathLines.opening(at: lineIndex) else {
                outputLines.append(protectingInlineMath(in: line))
                lineIndex += 1
                continue
            }
            // An unclosed display block runs to the end, as in Obsidian.
            let closingLineIndex = opening.closingLineIndex ?? lines.count - 1
            outputLines.append(joinedDisplayMath(opening: opening, openingLine: line, openingQuotePrefixLength: prefixLength,
                                                 followingLines: lines[(lineIndex + 1)..<(closingLineIndex + 1)],
                                                 isClosed: opening.closingLineIndex != nil))
            lineIndex = closingLineIndex + 1
        }
        return (outputLines.joined(separator: "\n"), outputLineIndices)
    }

    /// One line holding a display formula that was written over several: the text before
    /// the opening `$$` (only its quote markers when the formula starts the line), the
    /// LaTeX between the delimiters, and any text after the closing `$$`.
    private static func joinedDisplayMath(opening: DisplayMathLines.Opening, openingLine: String, openingQuotePrefixLength: Int,
                                          followingLines: ArraySlice<String>, isClosed: Bool) -> String {
        let openingSource = openingLine as NSString
        let leadingText = opening.isAtLineStart
            ? String(openingLine.prefix(openingQuotePrefixLength))
            : protectingInlineMath(in: openingSource.substring(to: opening.delimiterOffset))
        var latexLines = [openingSource.substring(from: opening.delimiterOffset + 2)]
        var trailingText = ""
        for (position, line) in zip(followingLines.indices, followingLines) {
            let lineSource = line as NSString
            let quotePrefixEnd = (String(line.prefix(quotePrefixLength(of: line))) as NSString).length
            guard isClosed, position == followingLines.indices.last, let closingOffset = DisplayMathLines.closingDelimiterOffset(in: line) else {
                latexLines.append(lineSource.substring(from: quotePrefixEnd))
                continue
            }
            let latexStart = min(quotePrefixEnd, closingOffset)
            latexLines.append(lineSource.substring(with: NSRange(location: latexStart, length: closingOffset - latexStart)))
            trailingText = protectingInlineMath(in: lineSource.substring(from: closingOffset + 2))
        }
        let latex = latexLines.map(withoutLaTeXComment).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return leadingText + displayMath(latex) + trailingText
    }

    /// A display formula as the reading view takes it: between `$$`, in LaTeX the
    /// typesetter draws, or, when it has equation numbers, as written between the
    /// numbered-equation markers.
    private static func displayMath(_ latex: String) -> String {
        guard LaTeXCompatibility.numberedEquation(latex) != nil else {
            return "$$ " + escapedForMarkdown(LaTeXCompatibility.normalized(latex), isInTableRow: false) + " $$"
        }
        return String(ReadingMarkers.numberedEquationStartMarker) + escapedForMarkdown(latex, isInTableRow: false)
            + String(ReadingMarkers.numberedEquationEndMarker)
    }

    /// The display formula with equation numbers that is all of `markdown`, which the
    /// reading view draws with each number at the right of the text column.
    package static func numberedEquation(aloneIn markdown: String) -> NumberedEquation? {
        // Markers are single scalars and are found as scalars: one followed by a combining
        // mark is one Character with it.
        let scalars = markdown.unicodeScalars
        guard let start = scalars.firstIndex(where: { scalar in !scalar.properties.isWhitespace }),
              scalars[start] == ReadingMarkers.numberedEquationStartScalar,
              let end = scalars.lastIndex(where: { scalar in !scalar.properties.isWhitespace }),
              scalars[end] == ReadingMarkers.numberedEquationEndScalar else { return nil }
        let escapedLatex = scalars[scalars.index(after: start)..<end]
        guard !escapedLatex.contains(ReadingMarkers.numberedEquationStartScalar),
              !escapedLatex.contains(ReadingMarkers.numberedEquationEndScalar) else { return nil }
        return LaTeXCompatibility.numberedEquation(unescapedFromMarkdown(String(String.UnicodeScalarView(escapedLatex))))
    }

    /// Writes every display formula with equation numbers between `$$`, its numbers after
    /// their rows, for text drawn where a number cannot stand at the right of the column.
    package static func inliningEquationNumbers(in markdown: String) -> String {
        let scalars = markdown.unicodeScalars
        guard scalars.contains(ReadingMarkers.numberedEquationStartScalar) else { return markdown }
        var output = String.UnicodeScalarView()
        var remainder = scalars[...]
        while let start = remainder.firstIndex(of: ReadingMarkers.numberedEquationStartScalar),
              let end = remainder[start...].firstIndex(of: ReadingMarkers.numberedEquationEndScalar) {
            output.append(contentsOf: remainder[..<start])
            let latex = unescapedFromMarkdown(String(String.UnicodeScalarView(remainder[remainder.index(after: start)..<end])))
            let drawnLatex = LaTeXCompatibility.numberedEquation(latex)?.latexWithTagsInline ?? LaTeXCompatibility.normalized(latex)
            output.append(contentsOf: ("$$ " + escapedForMarkdown(drawnLatex, isInTableRow: false) + " $$").unicodeScalars)
            remainder = remainder[remainder.index(after: end)...]
        }
        output.append(contentsOf: remainder)
        return String(output)
    }

    private static func protectingInlineMath(in line: String) -> String {
        guard line.contains("$") else { return line }
        let source = line as NSString
        let wholeLine = NSRange(location: 0, length: source.length)
        let codeRanges = MarkdownCodeRanges.codeSpans(in: source, range: wholeLine).map(\.range)
        let isInTableRow = line.trimmingCharacters(in: .whitespaces).hasPrefix("|")
        let output = NSMutableString(string: line)
        for match in mathSpanPattern.matches(in: line, range: wholeLine).reversed()
        where !codeRanges.contains(where: { codeRange in NSIntersectionRange(codeRange, match.range).length > 0 }) {
            let isDisplayMath = match.range(at: 1).location != NSNotFound
            let contentRange = isDisplayMath ? match.range(at: 1) : match.range(at: 2)
            let latex = source.substring(with: contentRange)
            // An equation number belongs to a display formula. Inline math has none, as in
            // MathJax, and neither has a formula in a table cell, which is drawn inline.
            if isDisplayMath, !isInTableRow, LaTeXCompatibility.numberedEquation(latex) != nil {
                output.replaceCharacters(in: match.range, with: displayMath(latex.trimmingCharacters(in: .whitespaces)))
            } else {
                output.replaceCharacters(in: contentRange, with: escapedForMarkdown(LaTeXCompatibility.normalized(latex), isInTableRow: isInTableRow))
            }
        }
        return output as String
    }

    /// Backslash-escapes ASCII punctuation, which CommonMark then reads as the character
    /// itself. In a table row, `\\|` is how a pipe is written inside a cell, so it stays one.
    private static func escapedForMarkdown(_ latex: String, isInTableRow: Bool) -> String {
        let text = isInTableRow ? latex.replacingOccurrences(of: "\\|", with: "|") : latex
        var escaped = ""
        escaped.reserveCapacity(text.utf8.count * 2)
        for character in text {
            if character.isASCII, character.isPunctuation || character.isSymbol { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    /// The text `escapedForMarkdown` was given, outside a table row.
    private static func unescapedFromMarkdown(_ escapedText: String) -> String {
        var text = ""
        text.reserveCapacity(escapedText.utf8.count)
        var isEscaped = false
        for character in escapedText {
            if character == "\\", !isEscaped {
                isEscaped = true
            } else {
                text.append(character)
                isEscaped = false
            }
        }
        return text
    }

    /// LaTeX ignores everything after an unescaped `%`; joined lines must not inherit that.
    private static func withoutLaTeXComment(_ line: String) -> String {
        var isEscaped = false
        for (offset, character) in line.enumerated() {
            if character == "%" && !isEscaped { return String(line.prefix(offset)) }
            isEscaped = character == "\\" && !isEscaped
        }
        return line
    }

    private static func quotePrefixLength(of line: String) -> Int {
        guard line.hasPrefix(">") || line.first?.isWhitespace == true else { return 0 }
        let prefixRange = quotePrefixPattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))?.range
        // Only a quote prefix counts; plain indentation stays part of the line.
        guard let prefixRange, (line as NSString).substring(with: prefixRange).contains(">") else { return 0 }
        return (line as NSString).substring(with: prefixRange).count
    }
}

/// The constant patterns of `ReadingMathPreparation`; `StaticPatternTests` compiles every case.
enum ReadingMathPreparationPattern: String, StaticPatternSet {
    case tableDisplayMathPattern = #"\$\$([^$\n]+)\$\$"#
    /// `$$…$$`, or `MarkdownInlineMathPattern.formula` after the `|`.
    case mathSpanPattern = #"\$\$(?!\$)([^\n]+?)\$\$|(?<![\\$])\$(?![\s$])((?:[^$\r\n\\]++|\\.)++)(?<!\s)\$(?![$\d])"#
    case quotePrefixPattern = #"^\s*(?:>\s?)*"#
}
