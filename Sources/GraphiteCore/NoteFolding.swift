import Foundation

/// A part of a note that folds, as in Obsidian: a heading's section, up to the next
/// heading of the same or a higher level, or a list item's indented lines.
public struct FoldableRegion: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case heading(level: Int)
        case listItem
    }

    public let kind: Kind
    /// The heading or list item line, without its line break.
    public let headerRange: NSRange
    /// What folding hides: from the header's line break to the end of the last folded
    /// line's text, so the line after the section starts on its own line.
    public let hiddenRange: NSRange
    /// Where the first visible line after the section starts.
    public let endLocation: Int
    /// Survives edits elsewhere in the note: the kind, the header text, and which
    /// occurrence of that text it is.
    public let key: String
}

public enum NoteFolding {
    /// The regions that fold in `text`. A heading or list item with nothing under it does
    /// not fold. Headings in code blocks and frontmatter are not headings.
    public static func regions(in text: String) -> [FoldableRegion] {
        let source = text as NSString
        var lines: [(range: NSRange, contentsEnd: Int, content: String, isCode: Bool)] = []
        var tracker = CodeFenceTracker()
        var location = FrontmatterLocator.length(in: source)
        while location < source.length {
            var lineEnd = 0, contentsEnd = 0
            source.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let content = source.substring(with: NSRange(location: location, length: contentsEnd - location))
            let isCode = tracker.isCodeLine(content.trimmingCharacters(in: .whitespaces))
            lines.append((NSRange(location: location, length: lineEnd - location), contentsEnd, content, isCode))
            location = lineEnd
        }
        var regions: [FoldableRegion] = []
        var occurrences: [String: Int] = [:]
        func key(_ base: String) -> String {
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            return base + "|" + String(occurrence)
        }
        // Each line's heading level, found once: every section below reads the levels of the
        // lines after its heading. This runs on every keystroke, so long notes depend on it.
        var headingLevels: [Int?] = []
        // Whether a heading's next line is its setext underline, which belongs to the heading.
        var hasSetextUnderline: [Bool] = []
        headingLevels.reserveCapacity(lines.count)
        hasSetextUnderline.reserveCapacity(lines.count)
        for (index, line) in lines.enumerated() {
            if line.isCode {
                headingLevels.append(nil)
                hasSetextUnderline.append(false)
            } else if let level = headingLevel(ofLine: line.content) {
                headingLevels.append(level)
                hasSetextUnderline.append(false)
            } else {
                let nextLine = index + 1 < lines.count && !lines[index + 1].isCode ? lines[index + 1].content : nil
                let setextLevel = setextHeadingLevel(ofLine: line.content, nextLine: nextLine)
                headingLevels.append(setextLevel)
                hasSetextUnderline.append(setextLevel != nil)
            }
        }
        for (index, line) in lines.enumerated() where !line.isCode {
            if let level = headingLevels[index] {
                // The section runs to the next heading of the same or a higher level.
                var lastIndex = index
                var nextIndex = index + 1
                while nextIndex < lines.count {
                    if let nextLevel = headingLevels[nextIndex], nextLevel <= level { break }
                    lastIndex = nextIndex
                    nextIndex += 1
                }
                // Blank lines just before the next heading stay visible, as in Obsidian.
                while lastIndex > index, lines[lastIndex].content.trimmingCharacters(in: .whitespaces).isEmpty { lastIndex -= 1 }
                let headingKey = key("h\(level)|" + line.content.trimmingCharacters(in: .whitespaces))
                // A setext heading's underline is part of the heading, not of what folds under it.
                let firstBodyIndex = hasSetextUnderline[index] ? index + 2 : index + 1
                if let region = region(kind: .heading(level: level), header: line, last: lines[lastIndex], hasBody: lastIndex >= firstBodyIndex, key: headingKey) {
                    regions.append(region)
                }
            } else if isListItem(line.content) {
                let indent = indentWidth(of: line.content)
                var lastIndex = index
                var nextIndex = index + 1
                while nextIndex < lines.count {
                    let next = lines[nextIndex].content
                    if next.trimmingCharacters(in: .whitespaces).isEmpty {
                        nextIndex += 1
                        continue
                    }
                    guard indentWidth(of: next) > indent else { break }
                    lastIndex = nextIndex
                    nextIndex += 1
                }
                let itemKey = key("l|" + line.content.trimmingCharacters(in: .whitespaces))
                if let region = region(kind: .listItem, header: line, last: lines[lastIndex], hasBody: lastIndex > index, key: itemKey) {
                    regions.append(region)
                }
            }
        }
        return regions
    }

    /// The level of the setext heading whose text is `content`, when `nextLine` underlines it:
    /// `MarkdownStyleScanner.setextHeadingLevel(ofLine:nextLine:)`, without its paragraph test
    /// for the many lines whose next line is no underline.
    private static func setextHeadingLevel(ofLine content: String, nextLine: String?) -> Int? {
        guard let nextLine, let firstCharacter = nextLine.utf8.first(where: { character in character != UInt8(ascii: " ") }),
              firstCharacter == UInt8(ascii: "=") || firstCharacter == UInt8(ascii: "-") else { return nil }
        return MarkdownStyleScanner.setextHeadingLevel(ofLine: content, nextLine: nextLine)
    }

    /// The fold key of every heading that folds, by the UTF-16 offset at which its line starts
    /// in `text`. The reading view looks its headings up here by where they are in the note,
    /// so a heading folded in one view is the same heading in the others, whatever the
    /// reading view makes of its text (a link, a highlight, closing hashes).
    public static func headingKeysByLineStart(in text: String) -> [Int: String] {
        var keysByLineStart: [Int: String] = [:]
        for region in regions(in: text) {
            guard case .heading = region.kind else { continue }
            keysByLineStart[region.headerRange.location] = region.key
        }
        return keysByLineStart
    }

    /// `MarkdownEditing.headingLevel(of:)`, without its pattern for the many lines whose first
    /// character after spaces is not `#` and so cannot be headings.
    private static func headingLevel(ofLine content: String) -> Int? {
        guard content.utf8.first(where: { character in character != UInt8(ascii: " ") }) == UInt8(ascii: "#") else { return nil }
        return MarkdownEditing.headingLevel(of: content)
    }

    /// Whether a line is a list item, quoted or not, as `MarkdownEditing.listLine(_:)` reads
    /// it: quote markers, indentation, then `-`, `*`, `+` or a number with `.` or `)`, followed
    /// by spaces or the line's end. Read character by character rather than with the pattern,
    /// because folding reads every line of the note on every keystroke.
    static func isListItem(_ content: String) -> Bool {
        let space = UInt8(ascii: " "), tab = UInt8(ascii: "\t")
        let characters = Array(content.utf8)
        var index = 0
        func skipSpaces(from start: Int) -> Int {
            var position = start
            while position < characters.count, characters[position] == space || characters[position] == tab { position += 1 }
            return position
        }
        // Quote markers: `>`, each after optional spaces and with one optional space after.
        while true {
            let markerPosition = skipSpaces(from: index)
            guard markerPosition < characters.count, characters[markerPosition] == UInt8(ascii: ">") else { break }
            index = markerPosition + 1
            if index < characters.count, characters[index] == space || characters[index] == tab { index += 1 }
        }
        index = skipSpaces(from: index)
        guard index < characters.count else { return false }
        let marker = characters[index]
        if marker == UInt8(ascii: "-") || marker == UInt8(ascii: "*") || marker == UInt8(ascii: "+") {
            index += 1
        } else {
            let digitsStart = index
            while index < characters.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(characters[index]) { index += 1 }
            let digitCount = index - digitsStart
            guard (1...9).contains(digitCount), index < characters.count,
                  characters[index] == UInt8(ascii: ".") || characters[index] == UInt8(ascii: ")") else { return false }
            index += 1
        }
        guard index == characters.count || characters[index] == space || characters[index] == tab else { return false }
        // `- - -` and `***` are thematic breaks, not items; the full reading settles those rare lines.
        if marker == UInt8(ascii: "-") || marker == UInt8(ascii: "*"), characters[index...].contains(marker) {
            return MarkdownEditing.listLine(content)?.isListItem == true
        }
        return true
    }

    /// The regions after an edit, moved rather than found again, or nil when they must be
    /// found again. Typing in a long note edits one line of plain text at a time, and such an
    /// edit changes no region: it only moves the ones after it and lengthens or shortens the
    /// ones around it. Anything else (a line break, a heading, a list item, a code fence, a
    /// blank line or a change of indentation, before or after the edit) is found again.
    /// `regions` must describe `before`; `replacedRange` is in `before`.
    public static func regions(_ regions: [FoldableRegion], across editedRange: NSRange, replacementLength: Int,
                               before: NSString, after: NSString) -> [FoldableRegion]? {
        guard NSMaxRange(editedRange) <= before.length, editedRange.location + replacementLength <= after.length else { return nil }
        // The text storage can report more than the typing changed (a whole line restyled with
        // the character typed); only the characters that differ count.
        var replacedRange = editedRange, insertedLength = replacementLength
        while replacedRange.length > 0, insertedLength > 0,
              before.character(at: replacedRange.location) == after.character(at: replacedRange.location) {
            replacedRange.location += 1; replacedRange.length -= 1; insertedLength -= 1
        }
        while replacedRange.length > 0, insertedLength > 0,
              before.character(at: NSMaxRange(replacedRange) - 1) == after.character(at: replacedRange.location + insertedLength - 1) {
            replacedRange.length -= 1; insertedLength -= 1
        }
        let replacementLength = insertedLength
        let insertedRange = NSRange(location: replacedRange.location, length: replacementLength)
        guard before.substring(with: replacedRange).rangeOfCharacter(from: .newlines) == nil,
              after.substring(with: insertedRange).rangeOfCharacter(from: .newlines) == nil else { return nil }
        func lineText(_ text: NSString, containing range: NSRange) -> String {
            var start = 0, contentsEnd = 0
            text.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: range)
            return text.substring(with: NSRange(location: start, length: contentsEnd - start))
        }
        let lineBefore = lineText(before, containing: replacedRange), lineAfter = lineText(after, containing: insertedRange)
        guard isPlainText(lineBefore), isPlainText(lineAfter), indentWidth(of: lineBefore) == indentWidth(of: lineAfter) else { return nil }
        // A line that underlines the one above it (`===`), or is underlined by the one below,
        // is part of a setext heading, so editing it can change a region or its key.
        func nextLineText(_ text: NSString, after range: NSRange) -> String? {
            var lineEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: nil, for: range)
            guard lineEnd < text.length else { return nil }
            return lineText(text, containing: NSRange(location: lineEnd, length: 0))
        }
        guard MarkdownStyleScanner.setextUnderlineLevel(lineBefore) == nil, MarkdownStyleScanner.setextUnderlineLevel(lineAfter) == nil,
              nextLineText(before, after: replacedRange).flatMap(MarkdownStyleScanner.setextUnderlineLevel) == nil,
              nextLineText(after, after: insertedRange).flatMap(MarkdownStyleScanner.setextUnderlineLevel) == nil else { return nil }
        let change = replacementLength - replacedRange.length
        let editStart = replacedRange.location, editEnd = NSMaxRange(replacedRange)
        // A line's start at the edit stays; a line's text end at the edit moves with the typing.
        func movedStart(_ location: Int) -> Int { location <= editStart ? location : location + change }
        func movedEnd(_ location: Int) -> Int { location >= editEnd ? location + change : location }
        return regions.map { region in
            let headerStart = movedStart(region.headerRange.location), hiddenStart = movedEnd(region.hiddenRange.location)
            return FoldableRegion(kind: region.kind,
                                  headerRange: NSRange(location: headerStart, length: movedEnd(NSMaxRange(region.headerRange)) - headerStart),
                                  hiddenRange: NSRange(location: hiddenStart, length: movedEnd(NSMaxRange(region.hiddenRange)) - hiddenStart),
                                  endLocation: movedStart(region.endLocation), key: region.key)
        }
    }

    /// A line that starts no region and ends none early: not blank, not a heading, list item,
    /// code fence or frontmatter fence (`---`, or `...`, which closes frontmatter too).
    private static func isPlainText(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first != "#", first != "`", first != "~", !trimmed.hasPrefix("---"), !trimmed.hasPrefix("...") else { return false }
        return !isListItem(line)
    }

    /// The regions that are folded, given the folded keys. A region inside a folded region
    /// is hidden already and left out.
    public static func foldedRegions(in regions: [FoldableRegion], foldedKeys: Set<String>) -> [FoldableRegion] {
        var folded: [FoldableRegion] = []
        for region in regions where foldedKeys.contains(region.key) {
            if let outer = folded.last, NSLocationInRange(region.headerRange.location, outer.hiddenRange) { continue }
            folded.append(region)
        }
        return folded
    }

    /// The region whose header line contains `location`, the innermost when several do.
    public static func region(atLine location: Int, in regions: [FoldableRegion], text: NSString) -> FoldableRegion? {
        guard location <= text.length else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: min(location, text.length), length: 0))
        return regions.last { region in region.headerRange.location == lineRange.location }
    }

    /// Return at the end of a folded line, as Obsidian handles it: a new line after the
    /// folded section, a sibling item for a list item (a task stays a task), rather than a
    /// line inside what is hidden.
    public static func newLineAfterFoldedSection(_ region: FoldableRegion, in text: String) -> MarkdownTextEdit {
        let source = text as NSString
        var insertion = "\n"
        if region.kind == .listItem, let listLine = MarkdownEditing.listLine(source.substring(with: region.headerRange)), listLine.isListItem {
            var marker = listLine.marker
            if let number = listLine.orderedNumber, let delimiter = marker.last { marker = String(number + 1) + String(delimiter) }
            insertion += listLine.quotePrefix + listLine.indentation + marker + (listLine.spacing.isEmpty ? " " : listLine.spacing)
                + (listLine.taskStatus != nil ? "[ ] " : "")
        }
        let location = NSMaxRange(region.hiddenRange)
        return MarkdownTextEdit(range: NSRange(location: location, length: 0), replacement: insertion,
                                selectionAfter: NSRange(location: location + (insertion as NSString).length, length: 0))
    }

    /// The folded regions that hide `location`, so showing it means unfolding them.
    public static func regions(hiding location: Int, in folded: [FoldableRegion]) -> [FoldableRegion] {
        folded.filter { region in location > region.hiddenRange.location && location < region.endLocation }
    }

    // MARK: Private

    private static func region(kind: FoldableRegion.Kind, header: (range: NSRange, contentsEnd: Int, content: String, isCode: Bool),
                               last: (range: NSRange, contentsEnd: Int, content: String, isCode: Bool), hasBody: Bool, key: String) -> FoldableRegion? {
        guard hasBody else { return nil }
        let hiddenStart = header.contentsEnd
        let hiddenEnd = last.contentsEnd
        guard hiddenEnd > hiddenStart else { return nil }
        return FoldableRegion(kind: kind, headerRange: NSRange(location: header.range.location, length: header.contentsEnd - header.range.location),
                              hiddenRange: NSRange(location: hiddenStart, length: hiddenEnd - hiddenStart),
                              endLocation: NSMaxRange(last.range), key: key)
    }

    /// Leading whitespace, with a tab counted as four spaces.
    private static func indentWidth(of line: String) -> Int {
        var width = 0
        for character in line {
            if character == " " { width += 1 } else if character == "\t" { width += 4 } else { break }
        }
        return width
    }
}
