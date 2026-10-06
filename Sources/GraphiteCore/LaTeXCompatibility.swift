import Foundation

/// A display formula with the equation numbers its `\tag` commands give it. Obsidian's
/// MathJax numbers nothing by itself (its `tags` option is left at `none`), so a number
/// is drawn only where `\tag` asks for one: at the right of the formula, or of the row it
/// is written in when the formula is an environment of rows such as `align` or `gather`.
public struct NumberedEquation: Equatable, Sendable {
    public struct Tag: Equatable, Sendable {
        /// The row the tag numbers in a formula that is an environment of rows; nil for
        /// the tag of a whole formula.
        public let rowIndex: Int?
        /// What `\tag` was given, as written.
        public let content: String
        /// False for `\tag*`, which is drawn without parentheses.
        public let hasParentheses: Bool

        /// The tag as plain text, for when the typesetter cannot draw `latex`.
        public var text: String { hasParentheses ? "(" + content + ")" : content }

        /// The tag as MathJax typesets it: text in the math font, with any `$…$` in it as math.
        public var latex: String {
            var latex = hasParentheses ? "\\text{(}" : ""
            for (segmentIndex, segment) in content.components(separatedBy: "$").enumerated() where !segment.isEmpty {
                latex += segmentIndex % 2 == 0 ? "\\text{" + segment + "}" : LaTeXCompatibility.normalized(segment)
            }
            return latex + (hasParentheses ? "\\text{)}" : "")
        }
    }

    /// One row of a formula that is an environment of rows.
    public struct Row: Equatable, Sendable {
        /// The row's cells as one formula, which is as tall and as deep as the row.
        public let latex: String
        /// The row as the formula writes it, and the row break after it.
        fileprivate let text: String
        fileprivate let separator: String
    }

    /// The formula without its tags, as the typesetter draws it.
    public let latex: String
    public let tags: [Tag]
    /// The rows of a formula that is one environment of rows, where each tag belongs to a
    /// row; empty for any other formula, which has one tag.
    public let rows: [Row]
    /// The environment that holds `rows`.
    fileprivate let rowEnvironment: String

    /// A formula of one row after another, as tall as the first rows of this formula down
    /// to the row at `rowIndex`. Its height, less that row's depth, is how far below the
    /// top of the formula the row's baseline is: the typesetter places rows from the top,
    /// each by the rows above it alone.
    public func stackedRowsLatex(through rowIndex: Int) -> String {
        let stackedRows = rows.prefix(rowIndex + 1)
        return "\\begin{gather}" + stackedRows.dropLast().map { row in row.latex + row.separator }.joined() + (stackedRows.last?.latex ?? "") + "\\end{gather}"
    }

    /// The formula with each tag written after its row, for places that cannot put it at
    /// the right of the text column, such as a formula inside a list item.
    public var latexWithTagsInline: String {
        let spaceBeforeTag = " \\qquad "
        guard !rows.isEmpty else { return latex + (tags.first.map { tag in spaceBeforeTag + tag.latex } ?? "") }
        let taggedRows = rows.enumerated().map { rowIndex, row in
            row.text + (tags.first { tag in tag.rowIndex == rowIndex }.map { tag in spaceBeforeTag + tag.latex } ?? "") + row.separator
        }
        return "\\begin{\(rowEnvironment)}" + taggedRows.joined() + "\\end{\(rowEnvironment)}"
    }
}

/// Rewrites LaTeX that Obsidian's MathJax accepts but Graphite's typesetter does not
/// into an equivalent it can draw. Only the text handed to the renderer changes.
public enum LaTeXCompatibility {
    private static let replacements: [(pattern: NSRegularExpression?, template: String)] = [
        (try? NSRegularExpression(pattern: "\\\\(begin|end)\\{(?:gather|multline)\\*?\\}"), "\\\\$1{gather}"),
        // The typesetter draws `eqnarray` itself, with its three columns; only the
        // unnumbered spelling is unknown to it.
        (try? NSRegularExpression(pattern: "\\\\(begin|end)\\{eqnarray\\*\\}"), "\\\\$1{eqnarray}"),
        // `equation` only numbers its content.
        (try? NSRegularExpression(pattern: "\\\\(?:begin|end)\\{equation\\*?\\}"), ""),
        (try? NSRegularExpression(pattern: "\\\\(?:nonumber|notag)\\b"), ""),
    ]
    /// Numbered labels, whose argument may hold braces of its own (`\tag{\ref{a}}`).
    private static let labelCommandPattern = try? NSRegularExpression(pattern: "\\\\(?:tag\\*?|label)[ \\t]*(?=\\{)")
    private static let tagCommandPattern = try? NSRegularExpression(pattern: "\\\\tag(\\*?)[ \\t]*(?=\\{)")
    /// The environments whose rows MathJax numbers one by one, around a whole formula.
    private static let numberedRowsEnvironmentPattern = try? NSRegularExpression(
        pattern: "\\A\\s*\\\\begin\\{((?:align|alignat|flalign|gather|eqnarray|multline)\\*?)\\}(?:\\{\\d+\\})?")
    /// What `normalized` makes of those environments.
    private static let drawnRowsEnvironmentPattern = try? NSRegularExpression(pattern: "\\A\\s*\\\\begin\\{(aligned|gather|eqnarray)\\}")
    /// Alignment environments MathJax draws as pairs of right- and left-aligned columns.
    /// The typesetter only knows `aligned`, with exactly two columns.
    private static let alignmentBeginPattern = try? NSRegularExpression(pattern: "\\\\begin\\{(align\\*?|flalign\\*?|alignat\\*?|alignedat|aligned)\\}(?:\\{\\d+\\})?")

    public static func normalized(_ latex: String) -> String {
        guard latex.contains("\\") else { return latex }
        var text = removingLabelCommands(from: latex)
        for replacement in replacements {
            guard let pattern = replacement.pattern else { continue }
            text = pattern.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: replacement.template)
        }
        return rewritingColorDeclarationsAndOperatorNames(in: rewritingAlignments(in: text))
    }

    /// The display formula `latex` with its equation numbers, or nil when it has none and
    /// `normalized` draws all of it. A row takes its first `\tag`, as does a formula that
    /// is not an environment of rows; MathJax reports a second one as an error, and here
    /// it is left out. `multline` has one number, on its last row.
    public static func numberedEquation(_ latex: String) -> NumberedEquation? {
        guard latex.contains("\\tag") else { return nil }
        let source = latex as NSString
        guard let environmentMatch = numberedRowsEnvironmentPattern?.firstMatch(in: latex, range: NSRange(location: 0, length: source.length)),
              let environmentEnd = environmentEnd(named: source.substring(with: environmentMatch.range(at: 1)), in: source, bodyStart: NSMaxRange(environmentMatch.range)),
              source.substring(from: environmentEnd.environmentEnd).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let (untaggedLatex, tag) = removingFirstTag(from: latex)
            guard let tag else { return nil }
            return NumberedEquation(latex: normalized(untaggedLatex), tags: [NumberedEquation.Tag(rowIndex: nil, content: tag.content, hasParentheses: tag.hasParentheses)],
                                    rows: [], rowEnvironment: "")
        }
        let environment = source.substring(with: environmentMatch.range(at: 1))
        let body = source.substring(with: NSRange(location: NSMaxRange(environmentMatch.range), length: environmentEnd.bodyEnd - NSMaxRange(environmentMatch.range)))
        let sourceRows = topLevelRows(of: body)
        var tags: [NumberedEquation.Tag] = []
        var untaggedBody = ""
        for (rowIndex, row) in sourceRows.enumerated() {
            let (untaggedRow, tag) = removingFirstTag(from: row.cells.joined(separator: "&"))
            untaggedBody += untaggedRow + row.separator
            guard let tag else { continue }
            let numbersWholeEnvironment = environment.hasPrefix("multline")
            if numbersWholeEnvironment, !tags.isEmpty { continue }
            tags.append(NumberedEquation.Tag(rowIndex: numbersWholeEnvironment ? sourceRows.count - 1 : rowIndex, content: tag.content, hasParentheses: tag.hasParentheses))
        }
        guard !tags.isEmpty else { return nil }
        let untaggedLatex = source.substring(to: NSMaxRange(environmentMatch.range)) + untaggedBody + source.substring(from: environmentEnd.bodyEnd)
        let drawnLatex = normalized(untaggedLatex)
        guard let drawnRows = rows(ofDrawnEnvironment: drawnLatex), drawnRows.rows.count == sourceRows.count else {
            // Without rows to stand beside, the formula keeps its first number.
            return NumberedEquation(latex: drawnLatex, tags: [NumberedEquation.Tag(rowIndex: nil, content: tags[0].content, hasParentheses: tags[0].hasParentheses)],
                                    rows: [], rowEnvironment: "")
        }
        return NumberedEquation(latex: drawnLatex, tags: tags, rows: drawnRows.rows, rowEnvironment: drawnRows.environment)
    }

    /// `latex` without its first `\tag{…}` or `\tag*{…}`, and what that tag holds.
    private static func removingFirstTag(from latex: String) -> (latex: String, tag: (content: String, hasParentheses: Bool)?) {
        guard let tagCommandPattern, latex.contains("\\tag") else { return (latex, nil) }
        let source = latex as NSString
        for match in tagCommandPattern.matches(in: latex, range: NSRange(location: 0, length: source.length)) {
            guard let argumentEnd = balancedGroupEnd(in: source, openingBraceAt: NSMaxRange(match.range)) else { continue }
            let content = source.substring(with: NSRange(location: NSMaxRange(match.range) + 1, length: argumentEnd - NSMaxRange(match.range) - 2))
            let untaggedLatex = source.replacingCharacters(in: NSRange(location: match.range.location, length: argumentEnd - match.range.location), with: "")
            return (untaggedLatex, (content.trimmingCharacters(in: .whitespaces), match.range(at: 1).length == 0))
        }
        return (latex, nil)
    }

    /// The rows of a formula that is one environment of rows the typesetter draws.
    private static func rows(ofDrawnEnvironment latex: String) -> (environment: String, rows: [NumberedEquation.Row])? {
        let source = latex as NSString
        guard let environmentMatch = drawnRowsEnvironmentPattern?.firstMatch(in: latex, range: NSRange(location: 0, length: source.length)),
              let environmentEnd = environmentEnd(named: source.substring(with: environmentMatch.range(at: 1)), in: source, bodyStart: NSMaxRange(environmentMatch.range)),
              source.substring(from: environmentEnd.environmentEnd).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let body = source.substring(with: NSRange(location: NSMaxRange(environmentMatch.range), length: environmentEnd.bodyEnd - NSMaxRange(environmentMatch.range)))
        let rows = topLevelRows(of: body).map { row in
            NumberedEquation.Row(latex: row.cells.joined(separator: " "), text: row.cells.joined(separator: "&"), separator: row.separator)
        }
        return (source.substring(with: environmentMatch.range(at: 1)), rows)
    }

    /// MathJax's `\color{…}` changes the remainder of its brace group; the native
    /// typesetter instead consumes just one following atom. Convert declarations to
    /// explicit `\textcolor` groups, closing them before the enclosing brace. Nested
    /// declarations override their parent color without leaking out of their group.
    /// The typesetter also lacks `\operatorname`; upright names use `\mathrm`.
    /// Starred operators (which need limit placement) are deliberately left unchanged.
    private static func rewritingColorDeclarationsAndOperatorNames(in latex: String) -> String {
        let characters = Array(latex)
        var output = ""
        var pendingColorClosures = [0]
        var position = 0
        while position < characters.count {
            let character = characters[position]
            if character == "\\", position + 1 < characters.count {
                let commandStart = position
                position += 1
                while position < characters.count, characters[position].isASCII, characters[position].isLetter {
                    position += 1
                }
                if position == commandStart + 1 {
                    // Escaped braces and row breaks are not group boundaries.
                    output += String(characters[commandStart...position])
                    position += 1
                    continue
                }
                let command = String(characters[(commandStart + 1)..<position])
                var argumentStart = position
                while argumentStart < characters.count, characters[argumentStart].isWhitespace { argumentStart += 1 }
                if command == "color", argumentStart < characters.count, characters[argumentStart] == "{",
                   let argumentEnd = characters[(argumentStart + 1)...].firstIndex(of: "}"),
                   !characters[(argumentStart + 1)..<argumentEnd].contains("{") {
                    output += "\\textcolor" + String(characters[argumentStart...argumentEnd]) + "{"
                    pendingColorClosures[pendingColorClosures.count - 1] += 1
                    position = argumentEnd + 1
                } else if command == "operatorname", argumentStart < characters.count, characters[argumentStart] == "{" {
                    output += "\\mathrm"
                } else {
                    output += String(characters[commandStart..<position])
                }
                continue
            }
            if character == "{" {
                pendingColorClosures.append(0)
            } else if character == "}", pendingColorClosures.count > 1 {
                output += String(repeating: "}", count: pendingColorClosures.removeLast())
            }
            output.append(character)
            position += 1
        }
        // Leave malformed, unclosed source groups for the typesetter to reject.
        if pendingColorClosures.count == 1 {
            output += String(repeating: "}", count: pendingColorClosures[0])
        }
        return output
    }

    /// Removes `\tag{…}`, `\tag*{…}` and `\label{…}` with their whole braced argument.
    private static func removingLabelCommands(from latex: String) -> String {
        guard let labelCommandPattern, latex.contains("\\tag") || latex.contains("\\label") else { return latex }
        let output = NSMutableString(string: latex)
        for match in labelCommandPattern.matches(in: latex, range: NSRange(location: 0, length: output.length)).reversed() {
            guard let argumentEnd = balancedGroupEnd(in: output, openingBraceAt: NSMaxRange(match.range)) else { continue }
            output.deleteCharacters(in: NSRange(location: match.range.location, length: argumentEnd - match.range.location))
        }
        return output as String
    }

    /// The offset just past the `}` that closes the `{` at `openingOffset`, or nil when it
    /// is never closed. Escaped braces (`\{`) do not count.
    private static func balancedGroupEnd(in text: NSString, openingBraceAt openingOffset: Int) -> Int? {
        var depth = 0
        var offset = openingOffset
        while offset < text.length {
            switch text.character(at: offset) {
            case backslash: offset += 1
            case openingBrace: depth += 1
            case closingBrace:
                depth -= 1
                if depth == 0 { return offset + 1 }
            default: break
            }
            offset += 1
        }
        return nil
    }

    /// Turns every alignment environment into a two-column `aligned`. A formula without
    /// `&` gains an empty second column, keeping its rows right-aligned as MathJax draws
    /// them. Columns past the second, as in `alignat{2}` or several equations per row,
    /// join the second column with a `\qquad` between equations, so the formula still
    /// draws, though only the first pair stays aligned across rows.
    private static func rewritingAlignments(in latex: String) -> String {
        guard let alignmentBeginPattern, latex.contains("align") else { return latex }
        let source = latex as NSString
        var output = ""
        var copiedUpTo = 0
        var searchStart = 0
        while searchStart < source.length,
              let match = alignmentBeginPattern.firstMatch(in: latex, range: NSRange(location: searchStart, length: source.length - searchStart)) {
            let environment = source.substring(with: match.range(at: 1))
            guard let end = environmentEnd(named: environment, in: source, bodyStart: NSMaxRange(match.range)) else { break }
            let body = source.substring(with: NSRange(location: NSMaxRange(match.range), length: end.bodyEnd - NSMaxRange(match.range)))
            output += source.substring(with: NSRange(location: copiedUpTo, length: match.range.location - copiedUpTo))
            output += "\\begin{aligned}" + twoColumnBody(rewritingAlignments(in: body)) + "\\end{aligned}"
            copiedUpTo = end.environmentEnd
            searchStart = end.environmentEnd
        }
        output += source.substring(from: copiedUpTo)
        return output
    }

    /// Where the `\end{environment}` matching an opened environment starts and ends.
    /// Environments of the same name nested inside are skipped.
    private static func environmentEnd(named environment: String, in source: NSString, bodyStart: Int) -> (bodyEnd: Int, environmentEnd: Int)? {
        let beginMarker = "\\begin{\(environment)}"
        let endMarker = "\\end{\(environment)}"
        var depth = 1
        var searchStart = bodyStart
        while searchStart < source.length {
            let searchRange = NSRange(location: searchStart, length: source.length - searchStart)
            let nextEnd = source.range(of: endMarker, range: searchRange)
            guard nextEnd.location != NSNotFound else { return nil }
            let nextBegin = source.range(of: beginMarker, range: searchRange)
            if nextBegin.location != NSNotFound, nextBegin.location < nextEnd.location {
                depth += 1
                searchStart = NSMaxRange(nextBegin)
                continue
            }
            depth -= 1
            if depth == 0 { return (nextEnd.location, NSMaxRange(nextEnd)) }
            searchStart = NSMaxRange(nextEnd)
        }
        return nil
    }

    /// The body with exactly two top-level columns. Separators inside braces or inside a
    /// nested environment (a matrix, `cases`) belong to that group and are kept.
    private static func twoColumnBody(_ body: String) -> String {
        let rows = topLevelRows(of: body)
        let columnCount = rows.map { row in row.cells.count }.max() ?? 1
        guard columnCount != 2 else { return body }
        var output = ""
        for (rowIndex, row) in rows.enumerated() {
            var line = row.cells[0]
            if row.cells.count > 1 {
                line += "&" + row.cells[1]
                for (cellIndex, cell) in row.cells.enumerated().dropFirst(2) {
                    // MathJax columns come in right-left pairs; a new pair is a new equation.
                    line += (cellIndex % 2 == 0 ? "\\qquad " : "") + cell
                }
            } else if rowIndex == 0 {
                line += "&"
            }
            output += line + row.separator
        }
        return output
    }

    /// Splits the body at top-level `\\` row breaks and `&` column separators. Each row
    /// keeps the break that ended it, with any `[2pt]` spacing, so rows join back exactly.
    private static func topLevelRows(of body: String) -> [(cells: [String], separator: String)] {
        let source = body as NSString
        var rows: [(cells: [String], separator: String)] = []
        var cells: [String] = []
        var cellStart = 0
        var braceDepth = 0
        var environmentDepth = 0
        var offset = 0
        while offset < source.length {
            let character = source.character(at: offset)
            if character == backslash {
                let rest = NSRange(location: offset, length: source.length - offset)
                if source.range(of: "\\begin{", options: .anchored, range: rest).location != NSNotFound {
                    environmentDepth += 1
                } else if source.range(of: "\\end{", options: .anchored, range: rest).location != NSNotFound {
                    environmentDepth = max(0, environmentDepth - 1)
                } else if braceDepth == 0, environmentDepth == 0, offset + 1 < source.length, source.character(at: offset + 1) == backslash {
                    cells.append(source.substring(with: NSRange(location: cellStart, length: offset - cellStart)))
                    let separatorEnd = rowBreakEnd(in: source, after: offset + 2)
                    rows.append((cells, source.substring(with: NSRange(location: offset, length: separatorEnd - offset))))
                    cells = []
                    cellStart = separatorEnd
                    offset = separatorEnd
                    continue
                }
                offset += 2
                continue
            }
            if character == openingBrace { braceDepth += 1 }
            if character == closingBrace { braceDepth = max(0, braceDepth - 1) }
            if character == ampersand, braceDepth == 0, environmentDepth == 0 {
                cells.append(source.substring(with: NSRange(location: cellStart, length: offset - cellStart)))
                cellStart = offset + 1
            }
            offset += 1
        }
        cells.append(source.substring(from: min(cellStart, source.length)))
        rows.append((cells, ""))
        return rows
    }

    /// The end of a row break's optional spacing argument, such as `[2pt]`.
    private static func rowBreakEnd(in source: NSString, after offset: Int) -> Int {
        guard offset < source.length, source.character(at: offset) == openingBracket else { return offset }
        let closing = source.range(of: "]", range: NSRange(location: offset, length: source.length - offset))
        return closing.location == NSNotFound ? offset : NSMaxRange(closing)
    }

    private static let backslash = UInt16(UInt8(ascii: "\\"))
    private static let openingBrace = UInt16(UInt8(ascii: "{"))
    private static let closingBrace = UInt16(UInt8(ascii: "}"))
    private static let openingBracket = UInt16(UInt8(ascii: "["))
    private static let ampersand = UInt16(UInt8(ascii: "&"))
}
