import Foundation

/// The reading-view rewrite of a note's inline Obsidian syntax that Markdown renderers do
/// not know: tasks, color sections and highlights become `ReadingMarkers`, which the view
/// turns into checkboxes and attributes, and block identifiers are removed.
enum ReadingInlineMarking {
    private static let highlightPattern = ReadingInlineMarkingPattern.highlightPattern.compiled()

    /// Writes each task's brackets as `ReadingTasks.markedText(for:)`, which the reading view
    /// draws as a checkbox.
    /// - Parameters:
    ///   - lineIndices: For each line of `markdown`, the index `taskLocation` knows it by;
    ///     nil when the lines cannot be told apart any more.
    ///   - taskLocation: Where a line's task is in the note; see `preparedForReading`.
    static func markingTasks(in markdown: String, lineIndices: [Int]? = nil,
                             taskLocation: ((_ lineIndex: Int, _ status: Unicode.Scalar) -> ReadingTasks.Location?)? = nil) -> String {
        let taskPattern = ReadingTasks.pattern
        var fenceTracker = CodeFenceTracker()
        let lines = markdown.components(separatedBy: "\n")
        let knownLineIndices = lineIndices?.count == lines.count ? lineIndices : nil
        return lines.enumerated().map { linePosition, line in
            if fenceTracker.isCodeLine(untrimmedLine: line) { return line }
            let source = line as NSString
            guard let match = taskPattern.firstMatch(in: line, range: NSRange(location: 0, length: source.length)),
                  let status = source.substring(with: match.range(at: 2)).unicodeScalars.first else { return line }
            let location = knownLineIndices.flatMap { knownLineIndices in taskLocation?(knownLineIndices[linePosition], status) }
            return source.substring(with: match.range(at: 1)) + ReadingTasks.markedText(for: ReadingTasks.MarkedTask(status: status, location: location))
                + source.substring(from: NSMaxRange(match.range))
        }.joined(separator: "\n")
    }

    private static let blockIdentifierPattern = ReadingInlineMarkingPattern.blockIdentifierPattern.compiled()

    /// Block `^id`s mark blocks for links; Obsidian does not show them when reading. Code
    /// and display math are left alone, so `x ^2` at the end of a formula line stays.
    static func removingBlockIdentifiers(from markdown: String) -> String {
        guard markdown.contains("^") else { return markdown }
        let lines = markdown.components(separatedBy: "\n")
        let mathLines = DisplayMathLines(lines)
        var fenceTracker = CodeFenceTracker()
        var mathClosingLineIndex: Int?
        var outputLines: [String] = []
        outputLines.reserveCapacity(lines.count)
        for (lineIndex, line) in lines.enumerated() {
            let source = line as NSString
            var searchStart = 0
            if let closingLineIndex = mathClosingLineIndex {
                guard lineIndex == closingLineIndex, let closingOffset = DisplayMathLines.closingDelimiterOffset(in: line) else {
                    outputLines.append(line)
                    continue
                }
                // An identifier may follow the closing `$$` of a formula.
                mathClosingLineIndex = nil
                searchStart = closingOffset + 2
            } else if fenceTracker.isCodeLine(untrimmedLine: line) {
                outputLines.append(line)
                continue
            } else if let opening = mathLines.opening(at: lineIndex) {
                // The end of the line, where an identifier would be, is inside the formula.
                mathClosingLineIndex = opening.closingLineIndex ?? lines.count
                outputLines.append(line)
                continue
            }
            let searchRange = NSRange(location: searchStart, length: source.length - searchStart)
            outputLines.append(blockIdentifierPattern.stringByReplacingMatches(in: line, range: searchRange, withTemplate: ""))
        }
        return outputLines.joined(separator: "\n")
    }

    static func markingColors(in markdown: String, paletteHexByName: [String: String]) -> String {
        let source = markdown as NSString
        let sections = TextColorMarkup.sections(in: source, paletteHexByName: paletteHexByName)
        guard !sections.isEmpty else { return markdown }
        // Replacements are applied from the end so earlier ranges stay valid.
        var replacements: [(range: NSRange, text: String)] = []
        for section in sections {
            let openingMarkers = String(ReadingMarkers.colorStartMarker) + section.hexColor + String(ReadingMarkers.colorHexEndMarker)
            replacements.append((section.openingMarkerRange, openingMarkers))
            if let closingRange = section.closingMarkerRange {
                replacements.append((closingRange, String(ReadingMarkers.colorEndMarker)))
            } else {
                replacements.append((NSRange(location: NSMaxRange(section.contentRange), length: 0), String(ReadingMarkers.colorEndMarker)))
            }
        }
        let output = NSMutableString(string: markdown)
        for replacement in replacements.sorted(by: { firstReplacement, secondReplacement in
            firstReplacement.range.location > secondReplacement.range.location
                || (firstReplacement.range.location == secondReplacement.range.location && firstReplacement.range.length > secondReplacement.range.length)
        }) {
            output.replaceCharacters(in: replacement.range, with: replacement.text)
        }
        return output as String
    }

    static func markingHighlights(in markdown: String) -> String {
        var fenceTracker = CodeFenceTracker()
        return markdown.components(separatedBy: "\n").map { line in
            if fenceTracker.isCodeLine(untrimmedLine: line) { return line }
            guard line.contains("==") else { return line }
            let source = line as NSString
            // `==` in a code span, of any number of backticks, is not a highlight.
            let codeRanges = MarkdownCodeRanges.codeSpans(in: source, range: NSRange(location: 0, length: source.length)).map(\.range)
            let output = NSMutableString(string: line)
            for match in highlightPattern.matches(in: line, range: NSRange(location: 0, length: source.length)).reversed()
            where !codeRanges.contains(where: { codeRange in NSIntersectionRange(codeRange, match.range).length > 0 }) {
                let highlighted = String(ReadingMarkers.highlightStartMarker) + source.substring(with: match.range(at: 1)) + String(ReadingMarkers.highlightEndMarker)
                output.replaceCharacters(in: match.range, with: highlighted)
            }
            return output as String
        }.joined(separator: "\n")
    }
}

/// The constant patterns of `ReadingInlineMarking`; `StaticPatternTests` compiles every case.
enum ReadingInlineMarkingPattern: String, StaticPatternSet {
    case highlightPattern = #"(?<![=~])==(?![\s=~])([^=\n]+?)(?<!\s)==(?!=)"#
    case blockIdentifierPattern = #"(?:[ \t]+|^)\^[A-Za-z0-9-]+[ \t]*$"#
}
