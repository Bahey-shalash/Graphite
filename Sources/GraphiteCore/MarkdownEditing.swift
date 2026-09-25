import Foundation

/// One replacement in note text, with where the selection goes afterwards.
public struct MarkdownTextEdit: Equatable, Sendable {
    /// The range of the original text that is replaced.
    public let range: NSRange
    public let replacement: String
    /// The selection after the edit, in the edited text.
    public let selectionAfter: NSRange

    public init(range: NSRange, replacement: String, selectionAfter: NSRange) {
        self.range = range; self.replacement = replacement; self.selectionAfter = selectionAfter
    }
}

/// Line-based editing commands, like Obsidian's editor commands. Each returns one edit
/// that keeps every character outside the touched lines unchanged.
public enum MarkdownEditing {
    private static let headingPrefix = try? NSRegularExpression(pattern: "^( {0,3})(#{1,6})(?:[ \\t]+|$)")

    /// Makes every selected line a heading of `level`, replacing any heading marks it has.
    /// When every line already is a heading of that level, the headings are removed, as
    /// Obsidian's "Toggle heading" does. Blank lines between selected paragraphs stay blank.
    public static func settingHeading(level: Int, in text: NSString, selection: NSRange) -> MarkdownTextEdit {
        let clampedLevel = min(max(level, 1), 6)
        let linesRange = lineRange(covering: selection, in: text)
        let lines = lineContents(in: text, range: linesRange)
        // A cursor on an empty line makes it a heading, but a blank line inside a selection
        // separates paragraphs and never becomes an empty heading.
        let skipsBlankLines = lines.count > 1
        func isSkipped(_ line: Line) -> Bool { skipsBlankLines && line.content.trimmingCharacters(in: .whitespaces).isEmpty }
        let headingLines = lines.filter { line in !isSkipped(line) }
        let removes = !headingLines.isEmpty && headingLines.allSatisfy { line in headingLevel(of: line.content) == clampedLevel }
        let marker = String(repeating: "#", count: clampedLevel) + " "
        var replacement = ""
        var selectionShift = 0
        for (lineIndex, line) in lines.enumerated() {
            if isSkipped(line) { replacement += line.content + line.ending; continue }
            let prefixLength = headingPrefixLength(of: line.content)
            let body = (line.content as NSString).substring(from: prefixLength)
            let newPrefix = removes ? "" : marker
            replacement += newPrefix + body + line.ending
            if lineIndex == 0 { selectionShift = (newPrefix as NSString).length - prefixLength }
        }
        let firstLineStart = linesRange.location
        let cursorLocation = max(firstLineStart, selection.location + selectionShift)
        let replacementLength = (replacement as NSString).length
        let selectionLength = selection.length == 0 ? 0 : max(0, replacementLength - (cursorLocation - firstLineStart) - trailingLineEndingLength(replacement))
        return MarkdownTextEdit(range: linesRange, replacement: replacement, selectionAfter: NSRange(location: cursorLocation, length: selectionLength))
    }

    /// The heading level of a line, or nil when it is not an ATX heading.
    public static func headingLevel(of line: String) -> Int? {
        guard let match = headingPrefix?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return nil }
        return match.range(at: 2).length
    }

    private static func headingPrefixLength(of line: String) -> Int {
        headingPrefix?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))?.range.length ?? 0
    }

    // MARK: Lists

    /// A line's list or quote markup: `> ` quote markers, indentation, the bullet or
    /// number, and a task checkbox. Every part is the text exactly as the line has it.
    public struct ListLine: Equatable, Sendable {
        public let quotePrefix: String
        public let indentation: String
        /// `-`, `*`, `+`, or a number with `.` or `)`; empty for a quote line alone.
        public let marker: String
        /// The whitespace after the marker; empty when the marker ends the line, as in a
        /// `-` typed alone.
        public let spacing: String
        /// The character inside `[ ]`, when the item is a task.
        public let taskStatus: Character?
        /// The checkbox as written: `[x] `, or `[ ]` when it ends the line; empty when the
        /// item is not a task.
        public let checkbox: String
        /// Everything before the item's text, in UTF-16 units.
        public var prefixLength: Int { (quotePrefix + indentation + marker + spacing + checkbox).utf16.count }
        public var isListItem: Bool { !marker.isEmpty }
        public var orderedNumber: Int? { Int(marker.dropLast()) }
    }

    // `[0-9]`, not `\d`: ICU's `\d` matches every script's decimal digits, and CommonMark
    // numbers a list only with ASCII digits.
    private static let listLinePattern = try? NSRegularExpression(pattern: "^((?:[ \\t]*>[ \\t]?)*)([ \\t]*)(?:([-*+]|[0-9]{1,9}[.)])([ \\t]+|$)(?:(\\[(.)\\])( |$))?)?")
    /// A thematic break such as `- - -` or `* * *`, which CommonMark reads before a list item.
    private static let thematicBreakPattern = try? NSRegularExpression(pattern: "^[ \\t]*([-*_])(?:[ \\t]*\\1){2,}[ \\t]*$")

    /// The list or quote markup of `line` (without its line ending), or nil for plain text.
    public static func listLine(_ line: String) -> ListLine? {
        let text = line as NSString
        guard let match = listLinePattern?.firstMatch(in: line, range: NSRange(location: 0, length: text.length)) else { return nil }
        func group(_ index: Int) -> String { match.range(at: index).location == NSNotFound ? "" : text.substring(with: match.range(at: index)) }
        let quotePrefix = group(1)
        var marker = group(3)
        // Only a `-` or `*` followed by the same character can start a thematic break, so the
        // second pattern runs for those lines alone.
        let textStart = NSMaxRange(match.range(at: 4))
        if marker == "-" || marker == "*", match.range(at: 4).location != NSNotFound, textStart < text.length,
           text.character(at: textStart) == (marker as NSString).character(at: 0),
           isThematicBreak(text.substring(from: quotePrefix.utf16.count)) {
            marker = ""
        }
        guard !marker.isEmpty || !quotePrefix.isEmpty else { return nil }
        guard !marker.isEmpty else {
            return ListLine(quotePrefix: quotePrefix, indentation: "", marker: "", spacing: "", taskStatus: nil, checkbox: "")
        }
        let taskStatus = match.range(at: 6).location == NSNotFound ? nil : group(6).first
        return ListLine(quotePrefix: quotePrefix, indentation: group(2), marker: marker, spacing: group(4),
                        taskStatus: taskStatus, checkbox: taskStatus == nil ? "" : group(5) + group(7))
    }

    /// Whether `line` (without its line ending or quote markers) is a thematic break such as
    /// `- - -`, `***` or `___`.
    public static func isThematicBreak(_ line: String) -> Bool {
        thematicBreakPattern?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    /// Return in a list, a task list, or a quote, as Obsidian's smart lists do: the next
    /// line gets the same markup (the next number, an open checkbox), and the numbered
    /// items that follow are renumbered. On an empty item the markup is removed instead, or
    /// the item moves out one level when it is nested. Nil when Return should just insert
    /// a line break, as it does in code blocks and frontmatter, where markup is text.
    ///
    /// `tabSize` is how many spaces one level is when the vault indents with tabs.
    public static func continuingList(in text: NSString, selection: NSRange, indentUnit: String, tabSize: Int = 4) -> MarkdownTextEdit? {
        guard selection.location <= text.length else { return nil }
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: selection.location, length: 0))
        let line = text.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
        guard let listLine = listLine(line), NSMaxRange(selection) <= contentsEnd else { return nil }
        // A marker with nothing after it, such as a `-` just typed, is not continued: Return
        // there is an ordinary line break until a space follows the marker.
        guard !listLine.isListItem || !listLine.spacing.isEmpty else { return nil }
        let cursorInLine = selection.location - lineStart
        guard cursorInLine >= listLine.prefixLength else { return nil }
        guard !isInCodeOrFrontmatter(lineStart: lineStart, in: text) else { return nil }
        let itemText = (line as NSString).substring(from: min(listLine.prefixLength, (line as NSString).length))
        let isEmptyItem = itemText.trimmingCharacters(in: .whitespaces).isEmpty && NSMaxRange(selection) == contentsEnd
        if isEmptyItem {
            let lineContentRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
            if listLine.isListItem, !listLine.indentation.isEmpty {
                let outdentedIndentation = removingOneLevel(from: listLine.indentation, indentUnit: indentUnit, tabSize: tabSize)
                var marker = listLine.marker
                var itemAbove: ListLine?
                // A numbered item that moves out continues the numbering of the level it joins.
                if listLine.orderedNumber != nil, let delimiter = listLine.marker.last,
                   let parentNumber = orderedNumber(ofItemAbove: lineStart, quotePrefix: listLine.quotePrefix,
                                                    indentationWidth: indentationWidth(outdentedIndentation, tabSize: tabSize), in: text, tabSize: tabSize) {
                    marker = String(parentNumber + 1) + String(delimiter)
                    itemAbove = ListLine(quotePrefix: listLine.quotePrefix, indentation: outdentedIndentation, marker: String(parentNumber) + String(delimiter),
                                         spacing: listLine.spacing, taskStatus: nil, checkbox: "")
                }
                let outdented = listLine.quotePrefix + outdentedIndentation + marker + listLine.spacing
                    + (listLine.taskStatus.map { _ in "[ ] " } ?? "")
                let selectionAfter = NSRange(location: lineStart + outdented.utf16.count, length: 0)
                // The items that follow at the level the item joins count on after it.
                guard let itemAbove, let renumbering = renumberingItems(after: lineEnd, following: itemAbove, in: text, tabSize: tabSize) else {
                    return MarkdownTextEdit(range: lineContentRange, replacement: outdented, selectionAfter: selectionAfter)
                }
                let lineEnding = text.substring(with: NSRange(location: contentsEnd, length: lineEnd - contentsEnd))
                return MarkdownTextEdit(range: NSRange(location: lineStart, length: renumbering.end - lineStart),
                                        replacement: outdented + lineEnding + renumbering.replacement, selectionAfter: selectionAfter)
            }
            // A list item leaves its quote in place; a quote line alone ends the quote.
            let remaining = listLine.isListItem ? listLine.quotePrefix : ""
            return MarkdownTextEdit(range: lineContentRange, replacement: remaining, selectionAfter: NSRange(location: lineStart + remaining.utf16.count, length: 0))
        }
        var nextMarker = listLine.marker
        if let number = listLine.orderedNumber, let delimiter = listLine.marker.last { nextMarker = String(number + 1) + String(delimiter) }
        let lineBreak = lineBreakForNewLine(lineStart: lineStart, lineEnd: lineEnd, contentsEnd: contentsEnd, in: text)
        let continuation = lineBreak + listLine.quotePrefix + listLine.indentation + nextMarker + listLine.spacing + (listLine.taskStatus.map { _ in "[ ] " } ?? "")
        let selectionAfter = NSRange(location: selection.location + continuation.utf16.count, length: 0)
        guard let renumbering = renumberingItems(after: lineEnd, following: listLine, in: text, tabSize: tabSize) else {
            return MarkdownTextEdit(range: selection, replacement: continuation, selectionAfter: selectionAfter)
        }
        // One edit reaches from the cursor to the last renumbered item, so the new item and
        // the renumbering undo together.
        let restOfLine = text.substring(with: NSRange(location: NSMaxRange(selection), length: lineEnd - NSMaxRange(selection)))
        return MarkdownTextEdit(range: NSRange(location: selection.location, length: renumbering.end - selection.location),
                                replacement: continuation + restOfLine + renumbering.replacement, selectionAfter: selectionAfter)
    }

    /// The line break a new line after this one gets: the line's own, or the one the line
    /// above has when this is the note's last line, so a CRLF note stays CRLF.
    private static func lineBreakForNewLine(lineStart: Int, lineEnd: Int, contentsEnd: Int, in text: NSString) -> String {
        var ending = text.substring(with: NSRange(location: contentsEnd, length: lineEnd - contentsEnd))
        if ending.isEmpty, lineStart > 0 {
            let previousLine = lineContents(in: text, range: text.lineRange(for: NSRange(location: lineStart - 1, length: 0)))
            ending = previousLine.first?.ending ?? ""
        }
        // Unicode line and paragraph separators end a line for NSString, but a new list item
        // is a Markdown line, so it gets an ordinary line break.
        return ending == "\r\n" || ending == "\r" ? ending : "\n"
    }

    /// Whether the line at `lineStart` is inside fenced code or the note's frontmatter.
    private static func isInCodeOrFrontmatter(lineStart: Int, in text: NSString) -> Bool {
        var location = 0
        if let frontmatterEnd = frontmatterEnd(in: text) {
            if lineStart < frontmatterEnd { return true }
            location = frontmatterEnd
        }
        var fenceTracker = CodeFenceTracker()
        while location < lineStart {
            var lineEnd = 0, contentsEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            defer { location = lineEnd }
            // Only a line starting with a fence character can open or close a fence, so the
            // others are skipped without making a string of each line.
            guard let firstCharacter = firstNonWhitespaceUnit(from: location, to: contentsEnd, in: text),
                  firstCharacter == unichar(UInt8(ascii: "`")) || firstCharacter == unichar(UInt8(ascii: "~")) else { continue }
            _ = fenceTracker.isCodeLine(text.substring(with: NSRange(location: location, length: contentsEnd - location)).trimmingCharacters(in: .whitespaces))
        }
        return fenceTracker.isInsideFence
    }

    /// Where the note's frontmatter ends, just past its closing line, or nil when the note
    /// has none. A `---` first line without a closing line is a thematic break.
    private static func frontmatterEnd(in text: NSString) -> Int? {
        var location = 0
        var isFirstLine = true
        while location < text.length {
            var lineEnd = 0, contentsEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            defer { location = lineEnd; isFirstLine = false }
            // Only a line starting with `-` or `.` can open or close frontmatter.
            guard let firstCharacter = firstNonWhitespaceUnit(from: location, to: contentsEnd, in: text),
                  firstCharacter == unichar(UInt8(ascii: "-")) || firstCharacter == unichar(UInt8(ascii: ".")) else {
                if isFirstLine { return nil }
                continue
            }
            let trimmedLine = text.substring(with: NSRange(location: location, length: contentsEnd - location)).trimmingCharacters(in: .whitespaces)
            if isFirstLine {
                guard trimmedLine == "---" else { return nil }
            } else if trimmedLine == "---" || trimmedLine == "..." {
                return lineEnd
            }
        }
        return nil
    }

    private static func firstNonWhitespaceUnit(from start: Int, to end: Int, in text: NSString) -> unichar? {
        var location = start
        while location < end {
            let unit = text.character(at: location)
            if unit != 32 && unit != 9 { return unit }
            location += 1
        }
        return nil
    }

    /// How wide `indentation` is in columns, with a tab as wide as `tabSize` spaces.
    private static func indentationWidth(_ indentation: String, tabSize: Int) -> Int {
        indentation.utf16.reduce(0) { width, unit in width + (unit == 9 ? max(tabSize, 1) : 1) }
    }

    /// The number of the closest numbered item above `lineStart` at `indentationWidth`, or
    /// nil when the item there is a bullet or the list ends first.
    private static func orderedNumber(ofItemAbove lineStart: Int, quotePrefix: String, indentationWidth targetWidth: Int,
                                      in text: NSString, tabSize: Int) -> Int? {
        let quoteDepth = quotePrefix.filter { character in character == ">" }.count
        var location = lineStart
        while location > 0 {
            let previousRange = text.lineRange(for: NSRange(location: location - 1, length: 0))
            location = previousRange.location
            guard let previousLine = lineContents(in: text, range: previousRange).first?.content,
                  !previousLine.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let parsed = listLine(previousLine)
            guard (parsed?.quotePrefix ?? "").filter({ character in character == ">" }).count == quoteDepth else { return nil }
            guard let parsed, parsed.isListItem else {
                // Text indented past the level belongs to an item above; anything else ends the list.
                let leadingWhitespace = String(previousLine.dropFirst(parsed?.quotePrefix.count ?? 0).prefix { character in character == " " || character == "\t" })
                if indentationWidth(leadingWhitespace, tabSize: tabSize) > targetWidth { continue }
                return nil
            }
            let width = indentationWidth(parsed.indentation, tabSize: tabSize)
            if width > targetWidth { continue }
            return width == targetWidth ? parsed.orderedNumber : nil
        }
        return nil
    }

    /// After Return adds item n + 1, the numbered items that follow in the same list are
    /// renumbered while they count up one by one, as Obsidian's smart lists do. Numbering
    /// that is not sequential, such as every item written `1.`, is left alone. Returns the
    /// new text from `start` to `end`, or nil when nothing changes.
    private static func renumberingItems(after start: Int, following item: ListLine, in text: NSString, tabSize: Int) -> (end: Int, replacement: String)? {
        guard var previousNumber = item.orderedNumber, let delimiter = item.marker.last else { return nil }
        let targetWidth = indentationWidth(item.indentation, tabSize: tabSize)
        let quoteDepth = item.quotePrefix.filter { character in character == ">" }.count
        var replacement = "", unchangedSinceLastItem = ""
        var end: Int?
        var location = start
        while location < text.length {
            var lineEnd = 0, contentsEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let line = text.substring(with: NSRange(location: location, length: contentsEnd - location))
            let wholeLine = text.substring(with: NSRange(location: location, length: lineEnd - location))
            defer { location = lineEnd }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { unchangedSinceLastItem += wholeLine; continue }
            let parsed = listLine(line)
            guard (parsed?.quotePrefix ?? "").filter({ character in character == ">" }).count == quoteDepth else { break }
            guard let parsed, parsed.isListItem else {
                // A continuation line of an item stays in the list; a paragraph ends it.
                let leadingWhitespace = String(line.dropFirst(parsed?.quotePrefix.count ?? 0).prefix { character in character == " " || character == "\t" })
                guard indentationWidth(leadingWhitespace, tabSize: tabSize) > targetWidth else { break }
                unchangedSinceLastItem += wholeLine
                continue
            }
            let width = indentationWidth(parsed.indentation, tabSize: tabSize)
            if width > targetWidth { unchangedSinceLastItem += wholeLine; continue }
            guard width == targetWidth, let number = parsed.orderedNumber, parsed.marker.last == delimiter, number == previousNumber + 1 else { break }
            let markerStart = (parsed.quotePrefix + parsed.indentation).utf16.count
            let renumberedLine = (wholeLine as NSString).replacingCharacters(in: NSRange(location: markerStart, length: parsed.marker.utf16.count),
                                                                             with: String(number + 1) + String(delimiter))
            replacement += unchangedSinceLastItem + renumberedLine
            unchangedSinceLastItem = ""
            end = lineEnd
            previousNumber = number
        }
        return end.map { end in (end, replacement) }
    }

    /// Moves the selected lines one level in (Tab), keeping the selection on the same text.
    public static func indenting(in text: NSString, selection: NSRange, indentUnit: String) -> MarkdownTextEdit {
        transformingLines(in: text, selection: selection) { line in
            guard !line.isEmpty else { return nil }
            let quotePrefixLength = listLine(line)?.quotePrefix.utf16.count ?? 0
            return LineChange(range: NSRange(location: quotePrefixLength, length: 0), replacement: indentUnit)
        }
    }

    /// Moves the selected lines one level out (Shift-Tab). `tabSize` is how many spaces one
    /// level is when the vault indents with tabs.
    public static func outdenting(in text: NSString, selection: NSRange, indentUnit: String, tabSize: Int = 4) -> MarkdownTextEdit {
        transformingLines(in: text, selection: selection) { line in
            let quotePrefixLength = listLine(line)?.quotePrefix.utf16.count ?? 0
            let whitespaceEnd = leadingWhitespaceEnd(in: line, after: quotePrefixLength)
            let leadingWhitespace = (line as NSString).substring(with: NSRange(location: quotePrefixLength, length: whitespaceEnd - quotePrefixLength))
            let remainingLength = removingOneLevel(from: leadingWhitespace, indentUnit: indentUnit, tabSize: tabSize).utf16.count
            guard remainingLength < leadingWhitespace.utf16.count else { return nil }
            return LineChange(range: NSRange(location: quotePrefixLength + remainingLength, length: leadingWhitespace.utf16.count - remainingLength), replacement: "")
        }
    }

    /// `indentation` is spaces and tabs only, so its Characters and UTF-16 units agree.
    private static func removingOneLevel(from indentation: String, indentUnit: String, tabSize: Int) -> String {
        if indentation.hasSuffix("\t") { return String(indentation.dropLast()) }
        // In a vault that indents with tabs, a level written in spaces is one tab wide.
        let spaceCount = max(indentUnit == "\t" ? tabSize : indentUnit.count, 1)
        let trailingSpaces = indentation.reversed().prefix { character in character == " " }.count
        return String(indentation.dropLast(min(trailingSpaces, spaceCount)))
    }

    /// Obsidian's "Toggle checkbox status" (⌘L): plain text becomes a task, a list item
    /// gets a checkbox, and a task is checked or unchecked.
    public static func togglingTask(in text: NSString, selection: NSRange) -> MarkdownTextEdit {
        let lines = lineContents(in: text, range: lineRange(covering: selection, in: text))
        let makesDone = lines.contains { line in listLine(line.content)?.taskStatus == " " }
        return transformingLines(in: text, selection: selection) { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty || lines.count == 1 else { return nil }
            let parsed = listLine(line)
            if let parsed, let status = parsed.taskStatus {
                let newStatus = makesDone ? "x" : (status == " " ? "x" : " ")
                let statusOffset = (parsed.quotePrefix + parsed.indentation + parsed.marker + parsed.spacing).utf16.count + 1
                // A custom status can be an emoji, two UTF-16 units wide.
                return LineChange(range: NSRange(location: statusOffset, length: String(status).utf16.count), replacement: newStatus)
            }
            if let parsed, parsed.isListItem {
                let insertionOffset = (parsed.quotePrefix + parsed.indentation + parsed.marker + parsed.spacing).utf16.count
                // A marker that ends the line has no space after it yet.
                return LineChange(range: NSRange(location: insertionOffset, length: 0), replacement: parsed.spacing.isEmpty ? " [ ] " : "[ ] ")
            }
            let insertionOffset = leadingWhitespaceEnd(in: line, after: parsed?.quotePrefix.utf16.count ?? 0)
            return LineChange(range: NSRange(location: insertionOffset, length: 0), replacement: "- [ ] ")
        }
    }

    /// Turns the selected lines into a bulleted or numbered list, or back into plain text
    /// when they already are one.
    public static func togglingList(numbered: Bool, in text: NSString, selection: NSRange) -> MarkdownTextEdit {
        let lines = lineContents(in: text, range: lineRange(covering: selection, in: text))
        let nonEmptyLines = lines.filter { line in !line.content.trimmingCharacters(in: .whitespaces).isEmpty }
        let removes = !nonEmptyLines.isEmpty && nonEmptyLines.allSatisfy { line in
            guard let parsed = listLine(line.content), parsed.isListItem else { return false }
            return (parsed.orderedNumber != nil) == numbered
        }
        var number = 0
        return transformingLines(in: text, selection: selection) { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty || lines.count == 1 else { return nil }
            let parsed = listLine(line)
            let markerStart = leadingWhitespaceEnd(in: line, after: parsed?.quotePrefix.utf16.count ?? 0)
            let markerLength = parsed.map { parsed in parsed.isListItem ? (parsed.marker + parsed.spacing).utf16.count : 0 } ?? 0
            let markerRange = NSRange(location: markerStart, length: markerLength)
            if removes { return LineChange(range: markerRange, replacement: "") }
            number += 1
            return LineChange(range: markerRange, replacement: numbered ? "\(number). " : "- ")
        }
    }

    /// The UTF-16 offset in `line` just past the spaces and tabs that start at `start`.
    private static func leadingWhitespaceEnd(in line: String, after start: Int) -> Int {
        let lineText = line as NSString
        var location = min(start, lineText.length)
        while location < lineText.length, lineText.character(at: location) == 32 || lineText.character(at: location) == 9 { location += 1 }
        return location
    }

    /// Obsidian's "Move line up" and "Move line down": the selected lines swap with the
    /// line above or below. Nil at the start or end of the note. Line breaks are measured
    /// as NSString finds them (CRLF, LF, CR and the Unicode separators), so when the note's
    /// last line takes part, the line break moves with the lines and each keeps its kind.
    public static func movingLines(up: Bool, in text: NSString, selection: NSRange) -> MarkdownTextEdit? {
        let blockRange = lineRange(covering: selection, in: text)
        let blockEnding = lineContents(in: text, range: blockRange).last?.ending ?? ""
        let block = text.substring(with: blockRange)
        if up {
            guard blockRange.location > 0 else { return nil }
            let previousRange = text.lineRange(for: NSRange(location: blockRange.location - 1, length: 0))
            guard let previous = lineContents(in: text, range: previousRange).first else { return nil }
            // The note's last line has no line break: it takes the one the line above had.
            let replacement = blockEnding.isEmpty ? block + previous.ending + previous.content : block + previous.content + previous.ending
            let combined = NSRange(location: previousRange.location, length: NSMaxRange(blockRange) - previousRange.location)
            return MarkdownTextEdit(range: combined, replacement: replacement,
                                    selectionAfter: NSRange(location: selection.location - previousRange.length, length: selection.length))
        }
        guard NSMaxRange(blockRange) < text.length else { return nil }
        let nextRange = text.lineRange(for: NSRange(location: NSMaxRange(blockRange), length: 0))
        guard let next = lineContents(in: text, range: nextRange).first else { return nil }
        let blockContent = (block as NSString).substring(to: (block as NSString).length - blockEnding.utf16.count)
        // When the line below is the note's last, the block's line break goes between them
        // and the block becomes the last line, so a selection that took in that break ends
        // at the block's text instead.
        let movedLine = next.ending.isEmpty ? next.content + blockEnding : next.content + next.ending
        let movedBlock = next.ending.isEmpty ? blockContent : block
        let replacement = movedLine + movedBlock
        let blockEnd = blockRange.location + replacement.utf16.count
        // A position between the CR and LF of a moved line break has no place in the block.
        let location = min(selection.location + movedLine.utf16.count, blockEnd)
        let combined = NSRange(location: blockRange.location, length: NSMaxRange(nextRange) - blockRange.location)
        return MarkdownTextEdit(range: combined, replacement: replacement,
                                selectionAfter: NSRange(location: location, length: max(0, min(selection.length, blockEnd - location))))
    }

    // MARK: Inline markup

    /// Bold, italic, highlight and the like: wraps the selection, or the word at the cursor,
    /// in `marker`, or removes the marker when it is already there. With nothing to wrap,
    /// the markers are inserted with the cursor between them.
    public static func togglingWrap(_ marker: String, closingMarker: String? = nil, in text: NSString, selection: NSRange) -> MarkdownTextEdit {
        let closing = closingMarker ?? marker
        let openingLength = marker.utf16.count, closingLength = closing.utf16.count
        var range = selection
        if range.length == 0 { range = wordRange(at: range.location, in: text) ?? range }
        let selectedText = text.substring(with: range)
        if let markerUnit = repeatedUnit(of: marker), closing == marker {
            if let unwrapped = removingRepeatedMarker(markerUnit, length: openingLength, around: range, selection: selection, in: text) { return unwrapped }
        } else {
            // Markers just outside the selection.
            if range.location >= openingLength, NSMaxRange(range) + closingLength <= text.length,
               text.substring(with: NSRange(location: range.location - openingLength, length: openingLength)) == marker,
               text.substring(with: NSRange(location: NSMaxRange(range), length: closingLength)) == closing {
                let outer = NSRange(location: range.location - openingLength, length: range.length + openingLength + closingLength)
                return MarkdownTextEdit(range: outer, replacement: selectedText,
                                        selectionAfter: NSRange(location: selection.location - openingLength, length: selection.length))
            }
            // Markers inside the selection.
            if selectedText.hasPrefix(marker), selectedText.hasSuffix(closing), selectedText.utf16.count >= openingLength + closingLength {
                let inner = String(decoding: Array(selectedText.utf16)[openingLength..<(selectedText.utf16.count - closingLength)], as: UTF16.self)
                return MarkdownTextEdit(range: range, replacement: inner, selectionAfter: NSRange(location: range.location, length: inner.utf16.count))
            }
        }
        let wrapped = marker + selectedText + closing
        let cursorAfter = selection.length == 0 && range.length == 0
            ? NSRange(location: range.location + openingLength, length: 0)
            : NSRange(location: selection.location + openingLength, length: selection.length)
        return MarkdownTextEdit(range: range, replacement: wrapped, selectionAfter: cursorAfter)
    }

    /// The UTF-16 unit a marker such as `*`, `**` or `==` repeats, or nil for other markers.
    private static func repeatedUnit(of marker: String) -> unichar? {
        guard let firstUnit = marker.utf16.first, marker.utf16.allSatisfy({ unit in unit == firstUnit }) else { return nil }
        return firstUnit
    }

    /// Removes a marker made of one repeated character when it surrounds the text at
    /// `range`, or returns nil when it does not. The whole run of that character on each
    /// side decides: `*` is not around `**word**`, which is bold, but it is around
    /// `***word***`, where emphasis runs of three are italic inside bold.
    private static func removingRepeatedMarker(_ markerUnit: unichar, length markerLength: Int, around range: NSRange, selection: NSRange, in text: NSString) -> MarkdownTextEdit? {
        // The text inside the markers: the selection without marker characters at its edges.
        var contentStart = range.location, contentEnd = NSMaxRange(range)
        while contentStart < contentEnd, text.character(at: contentStart) == markerUnit { contentStart += 1 }
        while contentEnd > contentStart, text.character(at: contentEnd - 1) == markerUnit { contentEnd -= 1 }
        // A selection of marker characters alone, such as an empty `****`, is split in half.
        if range.length > 0, contentStart == contentEnd {
            contentStart = range.location + range.length / 2
            contentEnd = contentStart
        }
        var runStart = contentStart, runEnd = contentEnd
        while runStart > 0, text.character(at: runStart - 1) == markerUnit { runStart -= 1 }
        while runEnd < text.length, text.character(at: runEnd) == markerUnit { runEnd += 1 }
        let leftRun = contentStart - runStart, rightRun = runEnd - contentEnd
        let isEmphasis = markerUnit == 42 || markerUnit == 95  // `*` or `_`
        let isPresent = (leftRun == markerLength && rightRun == markerLength)
            || (isEmphasis && markerLength < 3 && leftRun == 3 && rightRun == 3)
        guard isPresent else { return nil }
        let content = text.substring(with: NSRange(location: contentStart, length: contentEnd - contentStart))
        let selectionAfter = selection.length == 0
            ? NSRange(location: min(max(selection.location, contentStart), contentEnd) - markerLength, length: 0)
            : NSRange(location: contentStart - markerLength, length: contentEnd - contentStart)
        return MarkdownTextEdit(range: NSRange(location: contentStart - markerLength, length: contentEnd - contentStart + 2 * markerLength),
                                replacement: content, selectionAfter: selectionAfter)
    }

    /// The word around `location`: letters, digits, and joining marks.
    static func wordRange(at location: Int, in text: NSString) -> NSRange? {
        func isWordCharacter(_ index: Int) -> Bool {
            guard index >= 0, index < text.length, let scalar = Unicode.Scalar(text.character(at: index)) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "'"
        }
        guard isWordCharacter(location - 1) || isWordCharacter(location) else { return nil }
        var start = location, end = location
        while isWordCharacter(start - 1) { start -= 1 }
        while isWordCharacter(end) { end += 1 }
        // A cursor between words, or at a word's edge next to punctuation, has no word.
        guard end > start, start < location || end > location else { return nil }
        return NSRange(location: start, length: end - start)
    }

    // MARK: Pairs

    /// Brackets and quotes typed in pairs, as Obsidian's "Auto pair brackets" does.
    public static let bracketPairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "`": "`"]
    /// Markdown markers that wrap a selection, as Obsidian's "Auto pair Markdown syntax" does.
    public static let markdownWrapMarkers: Set<String> = ["*", "_", "~", "=", "`", "$"]

    /// What typing `typed` should do instead of inserting it, or nil to insert it as usual.
    public static func pairing(typed: String, in text: NSString, selection: NSRange, pairsBrackets: Bool, pairsMarkdown: Bool) -> MarkdownTextEdit? {
        guard typed.utf16.count == 1 else { return nil }
        let next = selection.length == 0 && selection.location < text.length ? text.substring(with: NSRange(location: selection.location, length: 1)) : ""
        let previous = selection.location > 0 ? text.substring(with: NSRange(location: selection.location - 1, length: 1)) : ""
        if selection.length > 0 {
            let wraps = (pairsBrackets && bracketPairs[typed] != nil) || (pairsMarkdown && markdownWrapMarkers.contains(typed))
            guard wraps else { return nil }
            let closing = bracketPairs[typed] ?? typed
            let selected = text.substring(with: selection)
            return MarkdownTextEdit(range: selection, replacement: typed + selected + closing,
                                    selectionAfter: NSRange(location: selection.location + 1, length: selection.length))
        }
        guard pairsBrackets else { return nil }
        // Typing a closing character right in front of the same one steps over it.
        if [")", "]", "}", "\"", "`"].contains(typed), next == typed {
            return MarkdownTextEdit(range: NSRange(location: selection.location, length: 0), replacement: "", selectionAfter: NSRange(location: selection.location + 1, length: 0))
        }
        guard let closing = bracketPairs[typed] else { return nil }
        let previousScalar = previous.unicodeScalars.first, nextScalar = next.unicodeScalars.first
        // Quotes and backticks pair only at the start of a word, so "it's" stays as typed and
        // three backticks make a code fence.
        if typed == "\"" || typed == "`" {
            if let previousScalar, CharacterSet.alphanumerics.contains(previousScalar) || previous == typed { return nil }
        }
        // In front of a word, an opening bracket is typed alone.
        if let nextScalar, CharacterSet.alphanumerics.contains(nextScalar) { return nil }
        return MarkdownTextEdit(range: selection, replacement: typed + closing, selectionAfter: NSRange(location: selection.location + 1, length: 0))
    }

    /// Backspace between an empty pair, such as `(|)` or `[[|]]`, removes both halves.
    public static func deletingPair(in text: NSString, selection: NSRange) -> MarkdownTextEdit? {
        guard selection.length == 0, selection.location > 0, selection.location < text.length else { return nil }
        let previous = text.substring(with: NSRange(location: selection.location - 1, length: 1))
        let next = text.substring(with: NSRange(location: selection.location, length: 1))
        guard bracketPairs[previous] == next else { return nil }
        return MarkdownTextEdit(range: NSRange(location: selection.location - 1, length: 2), replacement: "", selectionAfter: NSRange(location: selection.location - 1, length: 0))
    }

    // MARK: Line transforms

    /// One replacement inside a line, in UTF-16 offsets of the line without its line ending.
    private struct LineChange {
        let range: NSRange
        let replacement: String
    }

    /// Applies `change` to each line the selection touches; nil leaves a line as it is. The
    /// selection stays on the same text: a position before the changed part of its line
    /// does not move, one after it moves with the text, and one inside replaced markup goes
    /// to the end of the new markup.
    private static func transformingLines(in text: NSString, selection: NSRange, _ change: (String) -> LineChange?) -> MarkdownTextEdit {
        let linesRange = lineRange(covering: selection, in: text)
        let lines = lineContents(in: text, range: linesRange)
        let selectionStart = min(max(selection.location, linesRange.location), NSMaxRange(linesRange))
        let selectionEnd = min(max(NSMaxRange(selection), selectionStart), NSMaxRange(linesRange))
        var replacement = ""
        var oldLineStart = linesRange.location, newLineStart = linesRange.location
        var newSelectionStart = selectionStart, newSelectionEnd = selectionEnd
        for (lineIndex, line) in lines.enumerated() {
            let lineChange = change(line.content)
            let newContent = lineChange.map { lineChange in (line.content as NSString).replacingCharacters(in: lineChange.range, with: lineChange.replacement) } ?? line.content
            let contentLength = line.content.utf16.count
            let oldLineEnd = oldLineStart + contentLength + line.ending.utf16.count
            let isLastLine = lineIndex == lines.count - 1
            func mapped(_ position: Int) -> Int? {
                guard position >= oldLineStart, position < oldLineEnd || isLastLine else { return nil }
                return newLineStart + mappedColumn(position - oldLineStart, through: lineChange, contentLength: contentLength)
            }
            if let mappedStart = mapped(selectionStart) { newSelectionStart = mappedStart }
            if let mappedEnd = mapped(selectionEnd) { newSelectionEnd = mappedEnd }
            replacement += newContent + line.ending
            oldLineStart = oldLineEnd
            newLineStart += newContent.utf16.count + line.ending.utf16.count
        }
        let length = selection.length == 0 ? 0 : max(0, newSelectionEnd - newSelectionStart)
        return MarkdownTextEdit(range: linesRange, replacement: replacement, selectionAfter: NSRange(location: newSelectionStart, length: length))
    }

    /// Where a column of a line lands after `change`.
    private static func mappedColumn(_ column: Int, through change: LineChange?, contentLength: Int) -> Int {
        guard let change else { return column }
        let lengthChange = change.replacement.utf16.count - change.range.length
        // Past the line's text, in its line ending.
        if column > contentLength { return column + lengthChange }
        if column < change.range.location { return column }
        // At the start of replaced markup the position stays in front of it; an insertion
        // there pushes it along, so a cursor before a word stays before that word.
        if column == change.range.location, change.range.length > 0 { return column }
        if column < NSMaxRange(change.range) { return change.range.location + change.replacement.utf16.count }
        return column + lengthChange
    }

    // MARK: Lines

    struct Line {
        let content: String
        let ending: String
    }

    /// The whole lines that `range` touches, line endings included.
    static func lineRange(covering range: NSRange, in text: NSString) -> NSRange {
        let location = min(max(range.location, 0), text.length)
        let length = min(range.length, text.length - location)
        var lines = text.lineRange(for: NSRange(location: location, length: length))
        // A selection ending just after a line break does not include the next line.
        if length > 0, NSMaxRange(lines) > location + length, location + length > lines.location,
           isLineBreakUnit(text.character(at: location + length - 1)) {
            lines = text.lineRange(for: NSRange(location: location, length: length - 1))
        }
        return lines
    }

    static func lineContents(in text: NSString, range: NSRange) -> [Line] {
        var lines: [Line] = []
        var location = range.location
        while location < NSMaxRange(range) {
            var lineEnd = 0, contentsEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            lines.append(Line(content: text.substring(with: NSRange(location: location, length: contentsEnd - location)),
                              ending: text.substring(with: NSRange(location: contentsEnd, length: lineEnd - contentsEnd))))
            location = lineEnd
        }
        if lines.isEmpty { lines.append(Line(content: "", ending: "")) }
        return lines
    }

    /// The UTF-16 units that end a line for NSString: LF, CR (alone or before LF), next
    /// line, and the Unicode line and paragraph separators.
    private static func isLineBreakUnit(_ unit: unichar) -> Bool {
        unit == 10 || unit == 13 || unit == 0x85 || unit == 0x2028 || unit == 0x2029
    }

    private static func trailingLineEndingLength(_ text: String) -> Int {
        let units = Array(text.utf16.suffix(2))
        guard let last = units.last, isLineBreakUnit(last) else { return 0 }
        return last == 10 && units.count == 2 && units[0] == 13 ? 2 : 1
    }
}
