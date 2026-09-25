import Foundation

/// A colored section written with the Colors plugin syntax: `~={#e93147}text=~`.
public struct TextColorSection: Equatable, Sendable {
    /// The `~={token}` marker.
    public let openingMarkerRange: NSRange
    /// The `=~` marker, or nil when the section is not closed. It then ends with its block:
    /// the paragraph (at a blank line), heading, list item or table cell it is in.
    public let closingMarkerRange: NSRange?
    /// The colored text between the markers.
    public let contentRange: NSRange
    /// Canonical lowercase `#rrggbb` or `#rrggbbaa`.
    public let hexColor: String
    /// Nesting depth; deeper sections win where they overlap.
    public let depth: Int
}

/// Parses the text coloring syntax of the Colors plugin for Obsidian, so notes colored
/// in either app render the same. Notes store the hex; palette names are resolved only
/// for notes written with a name.
public enum TextColorMarkup {
    private static let openingMarkerPattern = try? NSRegularExpression(pattern: "~=\\{([^}\\s]+)\\}")
    private static let hexPattern = "^#?(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"

    /// Canonical hex for a hex literal, or nil for anything else.
    public static func canonicalHex(_ token: String) -> String? {
        guard token.range(of: hexPattern, options: .regularExpression) != nil else { return nil }
        let digits = token.hasPrefix("#") ? String(token.dropFirst()) : token
        let expanded = digits.count <= 4 ? digits.map { digit in String(repeating: String(digit), count: 2) }.joined() : digits
        return "#" + expanded.lowercased()
    }

    /// The color a marker's token names. A palette name wins over reading the same letters
    /// as hex (a palette color named `ace` is not `#aaccee`); a token written with `#` is
    /// always hex.
    private static func hexColor(forToken token: String, paletteHexByName: [String: String]) -> String? {
        if !token.hasPrefix("#"), let paletteHex = paletteHexByName[token].flatMap(canonicalHex) { return paletteHex }
        return canonicalHex(token)
    }

    public static func sections(in text: NSString, paletteHexByName: [String: String] = [:]) -> [TextColorSection] {
        guard let openingMarkerPattern, text.length > 0 else { return [] }
        let textAsString = text as String
        let blockRanges = codeAndMathBlockRanges(in: text)
        let protectedRanges = mergedRanges(protectedRanges(in: text, codeAndMathBlockRanges: blockRanges))
        // Binary search over sorted, disjoint ranges: scanning them all for every marker
        // made dense notes quadratic.
        func isProtected(_ range: NSRange) -> Bool {
            var lowerBound = 0
            var upperBound = protectedRanges.count
            while lowerBound < upperBound {
                let middle = (lowerBound + upperBound) / 2
                if NSMaxRange(protectedRanges[middle]) <= range.location { lowerBound = middle + 1 } else { upperBound = middle }
            }
            return lowerBound < protectedRanges.count && NSIntersectionRange(protectedRanges[lowerBound], range).length > 0
        }
        var sections: [TextColorSection] = []
        for paragraphRange in paragraphRanges(in: text, codeAndMathBlockRanges: blockRanges) {
            var markers: [(range: NSRange, hexColor: String?)] = []
            var openingMarkerLocations: Set<Int> = []
            for match in openingMarkerPattern.matches(in: textAsString, range: paragraphRange) where !isProtected(match.range) {
                let token = text.substring(with: match.range(at: 1))
                markers.append((match.range, hexColor(forToken: token, paletteHexByName: paletteHexByName)))
                openingMarkerLocations.insert(match.range.location)
            }
            var searchLocation = paragraphRange.location
            while searchLocation < NSMaxRange(paragraphRange) {
                let closingRange = text.range(of: "=~", range: NSRange(location: searchLocation, length: NSMaxRange(paragraphRange) - searchLocation))
                guard closingRange.location != NSNotFound else { break }
                searchLocation = closingRange.location + 1
                // `=~={`: the `~` begins an opening marker, so this is not a closer.
                let followsOpening = openingMarkerLocations.contains(closingRange.location + 1)
                if !followsOpening && !isProtected(closingRange) { markers.append((closingRange, nil)) }
            }
            markers.sort { firstMarker, secondMarker in firstMarker.range.location < secondMarker.range.location }
            var openSections: [(openingRange: NSRange, hexColor: String?)] = []
            let paragraphEnd = contentEnd(of: paragraphRange, in: text)
            for marker in markers {
                let isClosing = text.substring(with: marker.range) == "=~"
                if !isClosing {
                    openSections.append((marker.range, marker.hexColor))
                } else if let openSection = openSections.popLast() {
                    appendSection(openSection, closingRange: marker.range, end: marker.range.location, depth: openSections.count, to: &sections)
                }
            }
            while let openSection = openSections.popLast() {
                appendSection(openSection, closingRange: nil, end: paragraphEnd, depth: openSections.count, to: &sections)
            }
        }
        return sections.sorted { firstSection, secondSection in firstSection.openingMarkerRange.location < secondSection.openingMarkerRange.location }
    }

    private static func appendSection(_ openSection: (openingRange: NSRange, hexColor: String?), closingRange: NSRange?, end: Int, depth: Int, to sections: inout [TextColorSection]) {
        // An unknown palette name is left as plain text, exactly as written.
        guard let hexColor = openSection.hexColor else { return }
        let contentStart = NSMaxRange(openSection.openingRange)
        sections.append(TextColorSection(openingMarkerRange: openSection.openingRange, closingMarkerRange: closingRange,
                                         contentRange: NSRange(location: contentStart, length: max(0, end - contentStart)), hexColor: hexColor, depth: depth))
    }

    private static let headingLinePattern = try? NSRegularExpression(pattern: "^\\s{0,3}#{1,6}(?:\\s|$)")
    private static let listItemLinePattern = try? NSRegularExpression(pattern: "^\\s*(?:[-*+]|\\d+[.)])\\s")
    private static let tableRowLinePattern = try? NSRegularExpression(pattern: "^\\s*\\|")
    private static let cellBorderPattern = try? NSRegularExpression(pattern: "(?<!\\\\)\\|")
    /// A table's delimiter row, such as `--- | :---:` or `|---|`.
    private static let tableDelimiterRowPattern = try? NSRegularExpression(pattern: "^\\s*\\|?\\s*:?-+:?\\s*(?:\\|\\s*:?-+:?\\s*)*\\|?\\s*$")
    /// A thematic break, which is a block of its own.
    private static let thematicBreakLinePattern = try? NSRegularExpression(pattern: "^ {0,3}(?:(?:\\* *){3,}|(?:- *){3,}|(?:_ *){3,})\\s*$")
    /// A setext heading's underline; it makes the paragraph above it a heading.
    private static let setextUnderlinePattern = try? NSRegularExpression(pattern: "^ {0,3}(?:=+|-+)\\s*$")

    /// The blocks a color cannot leave, as rendered notes separate them: runs of
    /// non-blank lines, except that a heading, each list item, each table cell and a
    /// deeper quote are blocks of their own. Quote markers are read past, so a list
    /// item or heading inside a quote is found too. Code and `$$` blocks end the
    /// paragraph before them and belong to no paragraph.
    private static func paragraphRanges(in text: NSString, codeAndMathBlockRanges: [NSRange]) -> [NSRange] {
        var paragraphs: [NSRange] = []
        var paragraphStart: Int?
        /// The paragraph's last line, which becomes a table's header row when a delimiter row follows it.
        var lastParagraphLine: (range: NSRange, content: String)?
        func endParagraph(at end: Int) {
            if let start = paragraphStart, end > start { paragraphs.append(NSRange(location: start, length: end - start)) }
            paragraphStart = nil
            lastParagraphLine = nil
        }
        func matches(_ pattern: NSRegularExpression?, _ line: String) -> Bool {
            pattern?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
        }
        var isInTable = false
        var previousLineIsTableRow = false
        var previousQuoteDepth = 0
        var blockIndex = 0
        var lineStart = 0
        while lineStart < text.length {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            lineStart = NSMaxRange(lineRange)
            while blockIndex < codeAndMathBlockRanges.count, NSMaxRange(codeAndMathBlockRanges[blockIndex]) <= lineRange.location { blockIndex += 1 }
            if blockIndex < codeAndMathBlockRanges.count, codeAndMathBlockRanges[blockIndex].location <= lineRange.location {
                endParagraph(at: lineRange.location)
                isInTable = false
                previousLineIsTableRow = false
                previousQuoteDepth = 0
                continue
            }
            var line = text.substring(with: lineRange)
            // A byte order mark is not text; a heading after it is still a heading.
            if lineRange.location == 0, line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            let (quoteDepth, content) = quoteMarkersRemoved(from: line)
            let startsDeeperQuote = quoteDepth > previousQuoteDepth
            let isAfterTableRow = previousLineIsTableRow
            previousQuoteDepth = quoteDepth
            previousLineIsTableRow = false
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                endParagraph(at: lineRange.location)
                isInTable = false
                continue
            }
            let isHeading = matches(headingLinePattern, content)
            let isListItem = matches(listItemLinePattern, content)
            let isThematicBreak = matches(thematicBreakLinePattern, content)
            if isInTable && !isHeading && !isListItem && !isThematicBreak && !startsDeeperQuote {
                paragraphs.append(contentsOf: cellRanges(ofRow: lineRange, in: text))
                previousLineIsTableRow = true
                continue
            }
            isInTable = false
            if content.contains("|"), matches(tableDelimiterRowPattern, content) {
                // A delimiter row under a paragraph line with as many cells makes that line a
                // header row, as GitHub-flavored Markdown reads tables without outer pipes.
                if let header = lastParagraphLine, tableCellCount(of: header.content) == tableCellCount(of: content) {
                    endParagraph(at: header.range.location)
                    paragraphs.append(contentsOf: cellRanges(ofRow: header.range, in: text))
                    isInTable = true
                    previousLineIsTableRow = true
                    continue
                }
                if isAfterTableRow {
                    isInTable = true
                    previousLineIsTableRow = true
                    continue
                }
            }
            if isHeading {
                endParagraph(at: lineRange.location)
                paragraphs.append(lineRange)
            } else if isThematicBreak || paragraphStart != nil && matches(setextUnderlinePattern, content) {
                endParagraph(at: lineRange.location)
            } else if matches(tableRowLinePattern, content) {
                endParagraph(at: lineRange.location)
                paragraphs.append(contentsOf: cellRanges(ofRow: lineRange, in: text))
                previousLineIsTableRow = true
            } else {
                if isListItem || startsDeeperQuote { endParagraph(at: lineRange.location) }
                if paragraphStart == nil { paragraphStart = lineRange.location }
                lastParagraphLine = (lineRange, content)
            }
        }
        endParagraph(at: text.length)
        return paragraphs
    }

    /// The line after its `>` quote markers (each with up to three spaces before it and
    /// one optional space after it), and how many there were.
    private static func quoteMarkersRemoved(from line: String, maximumDepth: Int = .max) -> (depth: Int, content: String) {
        var remaining = Substring(line)
        var depth = 0
        while depth < maximumDepth {
            let indentation = remaining.prefix { character in character == " " }
            guard indentation.count <= 3, remaining.dropFirst(indentation.count).first == ">" else { break }
            remaining = remaining.dropFirst(indentation.count + 1)
            if remaining.first == " " || remaining.first == "\t" { remaining = remaining.dropFirst() }
            depth += 1
        }
        return (depth, String(remaining))
    }

    /// The number of cells in a table row, not counting its optional outer pipes.
    private static func tableCellCount(of rowContent: String) -> Int {
        var row = rowContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|") && !row.hasSuffix("\\|") { row.removeLast() }
        let borderCount = cellBorderPattern?.numberOfMatches(in: row, range: NSRange(location: 0, length: (row as NSString).length)) ?? 0
        return borderCount + 1
    }

    /// The text between unescaped `|` borders of a table row.
    private static func cellRanges(ofRow rowRange: NSRange, in text: NSString) -> [NSRange] {
        let borders = cellBorderPattern?.matches(in: text as String, range: rowRange).map(\.range.location) ?? []
        var cellStart = rowRange.location
        var cells: [NSRange] = []
        for border in borders + [NSMaxRange(rowRange)] {
            if border > cellStart { cells.append(NSRange(location: cellStart, length: border - cellStart)) }
            cellStart = border + 1
        }
        return cells
    }

    /// Where an unclosed color ends: the block's end, before trailing spaces and line breaks.
    private static func contentEnd(of paragraphRange: NSRange, in text: NSString) -> Int {
        var end = NSMaxRange(paragraphRange)
        while end > paragraphRange.location, let scalar = Unicode.Scalar(text.character(at: end - 1)), CharacterSet.whitespacesAndNewlines.contains(scalar) { end -= 1 }
        return end
    }

    /// A code span: a run of backticks closed by a run of the same length.
    private static let codeSpanPattern = try? NSRegularExpression(pattern: "(?<!`)(`+)(?!`)[^\\n]*?(?<!`)\\1(?!`)")
    /// Obsidian's inline math: no space inside either `$`, and no digit after the closing
    /// one, so "$5 and $10" is not math.
    private static let inlineMathPattern = try? NSRegularExpression(pattern: "(?<![\\\\$])\\$(?![\\s$])[^$\\n]*?(?<![\\s\\\\])\\$(?![\\d$])")

    /// Code fences, `$$` blocks, code spans and inline math: markup there is part of the
    /// code or formula, not markup. Color markers around a formula still color it.
    private static func protectedRanges(in text: NSString, codeAndMathBlockRanges: [NSRange]) -> [NSRange] {
        var ranges = codeAndMathBlockRanges
        let wholeText = NSRange(location: 0, length: text.length)
        let codeSpanRanges = codeSpanPattern?.matches(in: text as String, range: wholeText).map(\.range) ?? []
        ranges.append(contentsOf: codeSpanRanges)
        // A code span comes first, so a `$` inside one cannot pair with a `$` elsewhere:
        // the spans are replaced by line breaks, which inline math cannot cross, keeping
        // every other offset the same.
        var textOutsideCodeSpans = text as String
        if !codeSpanRanges.isEmpty {
            let maskedText = NSMutableString(string: text)
            for codeSpanRange in codeSpanRanges {
                maskedText.replaceCharacters(in: codeSpanRange, with: String(repeating: "\n", count: codeSpanRange.length))
            }
            textOutsideCodeSpans = maskedText as String
        }
        ranges.append(contentsOf: inlineMathPattern?.matches(in: textOutsideCodeSpans, range: wholeText).map(\.range) ?? [])
        return ranges
    }

    /// Sorted, disjoint ranges covering the same text as the given ones.
    private static func mergedRanges(_ ranges: [NSRange]) -> [NSRange] {
        var merged: [NSRange] = []
        for range in ranges.sorted(by: { firstRange, secondRange in firstRange.location < secondRange.location }) where range.length > 0 {
            if let last = merged.last, NSMaxRange(last) >= range.location {
                merged[merged.count - 1].length = max(NSMaxRange(last), NSMaxRange(range)) - last.location
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// Code blocks, fenced or indented by four spaces, and `$$` blocks, each from its first
    /// line through its last, or through the end of the note when a fence is never closed.
    /// Quote markers are read past, so a block inside a quote is found, and a fence inside
    /// a quote ends with the quote.
    private static func codeAndMathBlockRanges(in text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var fencedBlock: (start: Int, delimiter: String, quoteDepth: Int)?
        var indentedBlock: (start: Int, end: Int, quoteDepth: Int)?
        // Indented code cannot interrupt a paragraph, and inside a list item indented lines
        // are the item's text; these track both, loosely enough for a line scan.
        var previousLineEndsParagraph = true
        var previousLineIsBlank = true
        var previousQuoteDepth = 0
        var listContentIndentation: Int?
        func matches(_ pattern: NSRegularExpression?, _ line: String) -> NSTextCheckingResult? {
            pattern?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
        }
        var lineStart = 0
        while lineStart < text.length {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            lineStart = NSMaxRange(lineRange)
            let line = text.substring(with: lineRange)
            if let block = fencedBlock {
                let (quoteDepth, content) = quoteMarkersRemoved(from: line, maximumDepth: block.quoteDepth)
                if quoteDepth == block.quoteDepth {
                    let trimmedLine = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    let closes = block.delimiter == "$$"
                        ? trimmedLine.hasPrefix("$$") || trimmedLine.hasSuffix("$$")
                        : isClosingFence(trimmedLine, openingFence: block.delimiter)
                    if closes {
                        ranges.append(NSRange(location: block.start, length: NSMaxRange(lineRange) - block.start))
                        fencedBlock = nil
                        previousLineEndsParagraph = true
                        previousLineIsBlank = false
                        previousQuoteDepth = quoteDepth
                    }
                    continue
                }
                // The quote holding the block ended, and the block with it.
                ranges.append(NSRange(location: block.start, length: lineRange.location - block.start))
                fencedBlock = nil
                previousLineEndsParagraph = true
            }
            let (quoteDepth, content) = quoteMarkersRemoved(from: line)
            let trimmedLine = content.trimmingCharacters(in: .whitespacesAndNewlines)
            let isBlank = trimmedLine.isEmpty
            let indentation = indentationWidth(of: content)
            let isInNewQuoteContainer = quoteDepth != previousQuoteDepth
            // Fewer quote markers after a paragraph line is a lazy continuation of that
            // paragraph, not the start of a block.
            let startsDeeperQuote = quoteDepth > previousQuoteDepth
            if let block = indentedBlock {
                if quoteDepth == block.quoteDepth && (isBlank || indentation >= 4) {
                    if !isBlank { indentedBlock = (block.start, NSMaxRange(lineRange), block.quoteDepth) }
                    previousLineIsBlank = isBlank
                    continue
                }
                ranges.append(NSRange(location: block.start, length: block.end - block.start))
                indentedBlock = nil
                previousLineEndsParagraph = true
            }
            defer { previousQuoteDepth = quoteDepth }
            if isInNewQuoteContainer { listContentIndentation = nil }
            guard !isBlank else {
                previousLineEndsParagraph = true
                previousLineIsBlank = true
                continue
            }
            let isHeading = matches(headingLinePattern, content) != nil
            let isThematicBreak = matches(thematicBreakLinePattern, content) != nil
            let listItemMatch = isThematicBreak ? nil : matches(listItemLinePattern, content)
            if let contentIndentation = listContentIndentation, indentation < contentIndentation, listItemMatch == nil, previousLineIsBlank || isHeading {
                listContentIndentation = nil
            }
            if listContentIndentation == nil && indentation >= 4 && (previousLineEndsParagraph || startsDeeperQuote) {
                indentedBlock = (lineRange.location, NSMaxRange(lineRange), quoteDepth)
                previousLineIsBlank = false
                continue
            }
            if let fence = openingFence(of: trimmedLine) {
                fencedBlock = (lineRange.location, fence, quoteDepth)
            } else if trimmedLine.hasPrefix("$$") && !trimmedLine.dropFirst(2).contains("$$") {
                // A line such as "$$E=mc^2$$ is famous" holds its whole formula.
                fencedBlock = (lineRange.location, "$$", quoteDepth)
            } else if let listItemMatch, listContentIndentation == nil {
                listContentIndentation = listItemMatch.range.length
            }
            previousLineEndsParagraph = isHeading || isThematicBreak
            previousLineIsBlank = false
        }
        if let block = fencedBlock { ranges.append(NSRange(location: block.start, length: text.length - block.start)) }
        if let block = indentedBlock { ranges.append(NSRange(location: block.start, length: block.end - block.start)) }
        return ranges
    }

    /// Leading indentation in columns, with a tab reaching the next multiple of four.
    private static func indentationWidth(of line: String) -> Int {
        var width = 0
        for character in line {
            if character == " " { width += 1 } else if character == "\t" { width += 4 - width % 4 } else { break }
        }
        return width
    }

    /// The backticks or tildes that open a code fence, at least three of the same kind.
    /// A backtick fence's info string cannot contain a backtick, so a line such as
    /// "```inline```" is a code span in a paragraph, not a fence.
    private static func openingFence(of trimmedLine: String) -> String? {
        guard let fenceCharacter = trimmedLine.first, fenceCharacter == "`" || fenceCharacter == "~" else { return nil }
        let fence = String(trimmedLine.prefix { character in character == fenceCharacter })
        guard fence.count >= 3 else { return nil }
        if fenceCharacter == "`" && trimmedLine.dropFirst(fence.count).contains("`") { return nil }
        return fence
    }

    /// A fence closes only with the same character, at least as many times, and nothing else.
    private static func isClosingFence(_ trimmedLine: String, openingFence: String) -> Bool {
        guard let fenceCharacter = openingFence.first else { return false }
        return trimmedLine.count >= openingFence.count && trimmedLine.allSatisfy { character in character == fenceCharacter }
    }
}
