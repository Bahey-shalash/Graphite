import Foundation

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
        return rewritingAlignments(in: text)
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
