import Foundation

/// A block of a note that `[[Note#^id]]` can link to: a paragraph, a list item, or a
/// whole list, table, quote, callout, or code block.
public struct NoteBlock: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// `list` is a whole list, which has a block only when an `^id` names it.
        case paragraph, listItem, list, table, quote, code, math
    }

    public let kind: Kind
    /// The block's text in the note, without an `^id` of its own.
    public let range: NSRange
    public let text: String
    /// The block's `^id`, if it has one.
    public let identifier: String?
    /// The range of the `^id` marker (with its leading space or its own line), if any.
    public let identifierRange: NSRange?

    /// Lists, tables, quotes, callouts, code, and math take their `^id` on a line of their
    /// own after the block; other blocks take it at the end of their last line.
    public var takesIdentifierOnOwnLine: Bool { kind != .paragraph && kind != .listItem }
}

public enum NoteBlocks {
    private static let trailingIdentifierPattern = try? NSRegularExpression(pattern: "(?:^|[ \\t])\\^([A-Za-z0-9-]+)[ \\t]*$")
    private static let identifierLinePattern = try? NSRegularExpression(pattern: "^[ \\t]*\\^([A-Za-z0-9-]+)[ \\t]*$")
    /// `***`, `---`, `___`, or `- - -`: a thematic break, which is not a block.
    private static let thematicBreakPattern = try? NSRegularExpression(pattern: "^ {0,3}([-*_])(?:[ \\t]*\\1){2,}[ \\t]*$")
    /// The line under a setext heading's text.
    private static let setextUnderlinePattern = try? NSRegularExpression(pattern: "^ {0,3}(?:=+|-+)[ \\t]*$")
    /// Indentation that makes a line indented code outside a list.
    private static let indentedCodeColumns = 4

    /// The blocks of `text`, in order. Frontmatter, headings, and thematic breaks are not blocks.
    public static func blocks(in text: String) -> [NoteBlock] {
        let source = text as NSString
        var lines: [(range: NSRange, content: String)] = []
        var location = FrontmatterLocator.length(in: source)
        while location < source.length {
            var lineEnd = 0, contentsEnd = 0
            source.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let contentRange = NSRange(location: location, length: contentsEnd - location)
            lines.append((contentRange, source.substring(with: contentRange)))
            location = lineEnd
        }
        func isBlank(_ lineIndex: Int) -> Bool { lines[lineIndex].content.trimmingCharacters(in: .whitespaces).isEmpty }
        var blocks: [NoteBlock] = []
        var lineIndex = 0
        // Indented lines after a list item belong to the item rather than being indented code.
        var isInsideList = false
        var listStartLineIndex = 0
        while lineIndex < lines.count {
            let line = lines[lineIndex].content
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty { lineIndex += 1; continue }
            let startsIndented = line.first == " " || line.first == "\t"
            if isIdentifierLine(trimmedLine) { lineIndex += 1; continue }
            if !isInsideList && indentationColumns(of: line) >= indentedCodeColumns {
                // Indented code: a trailing `^word` in it is code, not an identifier.
                var endIndex = lineIndex
                var scanIndex = lineIndex + 1
                while scanIndex < lines.count, isBlank(scanIndex) || indentationColumns(of: lines[scanIndex].content) >= indentedCodeColumns {
                    if !isBlank(scanIndex) { endIndex = scanIndex }
                    scanIndex += 1
                }
                blocks.append(finishedBlock(.code, lines: lines, from: lineIndex, through: &endIndex, source: source))
                lineIndex = endIndex + 1
                continue
            }
            if MarkdownEditing.headingLevel(of: line) != nil || matches(thematicBreakPattern, line) {
                if !startsIndented { isInsideList = false }
                lineIndex += 1
                continue
            }
            var endIndex = lineIndex
            let kind: NoteBlock.Kind
            if let (fence, _) = CodeFence.opening(trimmedLine) {
                kind = .code
                endIndex += 1
                while endIndex < lines.count, !CodeFence.closes(fence, lines[endIndex].content.trimmingCharacters(in: .whitespaces)) { endIndex += 1 }
                endIndex = min(endIndex, lines.count - 1)
            } else if opensDisplayMath(trimmedLine) {
                kind = .math
                let closesOnSameLine = trimmedLine.count > 2 && trimmedLine.hasSuffix("$$") && trimmedLine != "$$"
                if !closesOnSameLine {
                    endIndex += 1
                    while endIndex < lines.count, !lines[endIndex].content.trimmingCharacters(in: .whitespaces).hasSuffix("$$") { endIndex += 1 }
                    endIndex = min(endIndex, lines.count - 1)
                }
            } else if trimmedLine.hasPrefix(">") {
                kind = .quote
                // A text line right under quoted text continues it lazily, so the quote (and an
                // `^id` added after it) extends past that line.
                while endIndex + 1 < lines.count {
                    let next = lines[endIndex + 1].content
                    let continuesQuotedText = !lines[endIndex].content.drop { character in character == ">" || character == " " || character == "\t" }.isEmpty
                    guard next.trimmingCharacters(in: .whitespaces).hasPrefix(">") || continuesQuotedText && continuesTextLazily(next) else { break }
                    endIndex += 1
                }
            } else if trimmedLine.hasPrefix("|") {
                kind = .table
                // As in GFM, a text line right under a table is one more row.
                while endIndex + 1 < lines.count {
                    let next = lines[endIndex + 1].content
                    guard next.trimmingCharacters(in: .whitespaces).hasPrefix("|") || continuesTextLazily(next) else { break }
                    endIndex += 1
                }
            } else if MarkdownEditing.listLine(line)?.isListItem == true {
                kind = .listItem
                if !isInsideList { listStartLineIndex = lineIndex }
                // Continuation lines indented under the item belong to it. A fenced code block
                // or display math under the item is a block of its own, so its content (which
                // can hold blank lines and `^word` text) never becomes part of the item's text.
                while endIndex + 1 < lines.count {
                    let next = lines[endIndex + 1].content
                    let trimmedNext = next.trimmingCharacters(in: .whitespaces)
                    guard !trimmedNext.isEmpty, next.first == " " || next.first == "\t", MarkdownEditing.listLine(next)?.isListItem != true,
                          CodeFence.opening(trimmedNext) == nil, !opensDisplayMath(trimmedNext) else { break }
                    endIndex += 1
                }
            } else {
                var isSetextHeading = false
                while endIndex + 1 < lines.count {
                    let next = lines[endIndex + 1].content
                    let trimmedNext = next.trimmingCharacters(in: .whitespaces)
                    // `Text` over `---` or `===` is a heading, which is not a block; adding an
                    // `^id` after the underline would turn it back into text.
                    if matches(setextUnderlinePattern, next) { isSetextHeading = true; endIndex += 1; break }
                    guard !trimmedNext.isEmpty, MarkdownEditing.headingLevel(of: next) == nil, CodeFence.opening(trimmedNext) == nil,
                          !matches(thematicBreakPattern, next), MarkdownEditing.listLine(next) == nil, !trimmedNext.hasPrefix("|"),
                          !opensDisplayMath(trimmedNext), !isIdentifierLine(trimmedNext) else { break }
                    endIndex += 1
                }
                if isSetextHeading {
                    if !startsIndented { isInsideList = false }
                    lineIndex = endIndex + 1
                    continue
                }
                kind = .paragraph
            }
            if kind == .listItem { isInsideList = true } else if !startsIndented { isInsideList = false }
            let itemEndIndex = endIndex
            let block = finishedBlock(kind, lines: lines, from: lineIndex, through: &endIndex, source: source)
            blocks.append(block)
            // Obsidian's documented form for a whole list: its `^id` on a line of its own,
            // after a blank line.
            if kind == .listItem, block.identifier == nil, let identifierLineIndex = identifierLineAfterBlankLines(following: itemEndIndex, in: lines) {
                let firstRange = lines[listStartLineIndex].range, lastRange = lines[itemEndIndex].range
                let listRange = NSRange(location: firstRange.location, length: NSMaxRange(lastRange) - firstRange.location)
                blocks.append(NoteBlock(kind: .list, range: listRange, text: source.substring(with: listRange),
                                        identifier: identifierOnOwnLine(lines[identifierLineIndex].content), identifierRange: lines[identifierLineIndex].range))
                endIndex = identifierLineIndex
                isInsideList = false
            }
            lineIndex = endIndex + 1
        }
        return blocks
    }

    /// The block spanning the lines from `firstIndex` through `endIndex`, with its `^id`.
    /// `endIndex` moves past an `^id` line that belongs to the block.
    private static func finishedBlock(_ kind: NoteBlock.Kind, lines: [(range: NSRange, content: String)], from firstIndex: Int, through endIndex: inout Int, source: NSString) -> NoteBlock {
        let firstRange = lines[firstIndex].range, lastRange = lines[endIndex].range
        var blockRange = NSRange(location: firstRange.location, length: NSMaxRange(lastRange) - firstRange.location)
        var identifier: String?
        var identifierRange: NSRange?
        let lastLine = lines[endIndex].content
        if kind == .paragraph || kind == .listItem,
           let match = trailingIdentifierPattern?.firstMatch(in: lastLine, range: NSRange(location: 0, length: (lastLine as NSString).length)) {
            identifier = (lastLine as NSString).substring(with: match.range(at: 1))
            let markerRange = NSRange(location: lastRange.location + match.range.location, length: match.range.length)
            identifierRange = markerRange
            blockRange.length = markerRange.location - blockRange.location
        } else if endIndex + 1 < lines.count, let lineIdentifier = identifierOnOwnLine(lines[endIndex + 1].content) {
            identifier = lineIdentifier
            identifierRange = lines[endIndex + 1].range
            endIndex += 1
        } else if kind != .paragraph && kind != .listItem, let identifierLineIndex = identifierLineAfterBlankLines(following: endIndex, in: lines) {
            // Obsidian's documented form for tables, quotes, and callouts: the `^id` on a
            // line of its own with a blank line before it.
            identifier = identifierOnOwnLine(lines[identifierLineIndex].content)
            identifierRange = lines[identifierLineIndex].range
            endIndex = identifierLineIndex
        }
        return NoteBlock(kind: kind, range: blockRange, text: source.substring(with: blockRange), identifier: identifier, identifierRange: identifierRange)
    }

    /// The index of an `^id` line that follows `lineIndex` after one or more blank lines.
    private static func identifierLineAfterBlankLines(following lineIndex: Int, in lines: [(range: NSRange, content: String)]) -> Int? {
        var candidateIndex = lineIndex + 1
        while candidateIndex < lines.count, lines[candidateIndex].content.trimmingCharacters(in: .whitespaces).isEmpty { candidateIndex += 1 }
        guard candidateIndex > lineIndex + 1, candidateIndex < lines.count, identifierOnOwnLine(lines[candidateIndex].content) != nil else { return nil }
        return candidateIndex
    }

    private static func identifierOnOwnLine(_ line: String) -> String? {
        guard let match = identifierLinePattern?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return nil }
        return (line as NSString).substring(with: match.range(at: 1))
    }

    private static func isIdentifierLine(_ trimmedLine: String) -> Bool {
        identifierOnOwnLine(trimmedLine) != nil
    }

    private static func matches(_ pattern: NSRegularExpression?, _ line: String) -> Bool {
        pattern?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    /// Whether `line` continues the text above it (a lazy continuation line) rather than
    /// ending the block with a blank line or starting a block of its own.
    private static func continuesTextLazily(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        return !trimmedLine.isEmpty && !trimmedLine.hasPrefix(">") && !trimmedLine.hasPrefix("|")
            && MarkdownEditing.headingLevel(of: line) == nil && CodeFence.opening(trimmedLine) == nil
            && !matches(thematicBreakPattern, line) && MarkdownEditing.listLine(line) == nil
            && !opensDisplayMath(trimmedLine) && !isIdentifierLine(trimmedLine)
    }

    /// Whether a line starting with `$$` opens display math. `$$a$$ and text` is inline
    /// math at the start of a paragraph; its `$$` pair closes on the same line.
    private static func opensDisplayMath(_ trimmedLine: String) -> Bool {
        guard trimmedLine.hasPrefix("$$") else { return false }
        let afterOpening = trimmedLine.dropFirst(2)
        guard let closing = afterOpening.range(of: "$$") else { return true }
        return closing.upperBound == afterOpening.endIndex
    }

    /// Leading indentation in columns, a tab reaching the next multiple of four as in CommonMark.
    private static func indentationColumns(of line: String) -> Int {
        var columns = 0
        for character in line {
            if character == " " { columns += 1 } else if character == "\t" { columns += 4 - columns % 4 } else { break }
        }
        return columns
    }

    /// The block with this `^id`, compared without case as Obsidian does.
    public static func block(withIdentifier identifier: String, in text: String) -> NoteBlock? {
        blocks(in: text).first { block in block.identifier?.caseInsensitiveCompare(identifier) == .orderedSame }
    }

    /// The part of a note an embed's subpath names: a block (`^id`), a heading's section,
    /// or the whole body when there is no subpath. Nil when the subpath names no block or
    /// heading of the note, which Obsidian reports instead of showing the whole note.
    public static func embeddedPart(of body: String, subpath: String?) -> String? {
        guard let subpath, !subpath.isEmpty else { return body }
        if subpath.hasPrefix("^") {
            return block(withIdentifier: String(subpath.dropFirst()), in: body)?.text
        }
        return NotePreviewDocument.sectionIfPresent(of: body, headingAnchor: NotePreviewDocument.anchor(forHeading: subpath))
    }

    /// What reading view and Live Preview show for an embed whose subpath names nothing,
    /// in Obsidian's words.
    public static func missingSectionMessage(subpath: String, noteName: String) -> String {
        "Unable to find section #\(subpath) in \(noteName)"
    }

    /// A new identifier in Obsidian's style: six random lowercase letters and digits,
    /// not used by another block of the note.
    public static func newIdentifier(avoiding existing: Set<String>) -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        while true {
            let identifier = String((0..<6).map { _ in characters.randomElement() ?? "a" })
            if !existing.contains(identifier) { return identifier }
        }
    }

    /// The edit that gives `block`, a block of `text`, the identifier `identifier`.
    public static func addingIdentifier(_ identifier: String, to block: NoteBlock, in text: String) -> MarkdownTextEdit {
        let source = text as NSString
        let location = min(NSMaxRange(block.range), source.length)
        let insertion: String
        if !block.takesIdentifierOnOwnLine {
            insertion = " ^" + identifier
        } else {
            let lineEnding = lineEnding(at: location, in: source)
            // The marker line keeps the block's indentation, so a block inside a list item stays in it.
            let blockStart = min(block.range.location, source.length)
            let firstLine = source.substring(with: source.lineRange(for: NSRange(location: blockStart, length: 0)))
            let indentation = String(firstLine.prefix { character in character == " " || character == "\t" })
            switch block.kind {
            case .code, .math:
                // A fence or `$$` closes the block, so the marker can follow directly.
                insertion = lineEnding + indentation + "^" + identifier
            default:
                // Obsidian's form, with a blank line before and after: a line right under a
                // table becomes a row, and one under a quote continues the quote.
                let nextLineStart = NSMaxRange(source.lineRange(for: NSRange(location: location, length: 0)))
                let nextLineIsBlank = nextLineStart >= source.length
                    || source.substring(with: source.lineRange(for: NSRange(location: nextLineStart, length: 0))).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                insertion = lineEnding + lineEnding + indentation + "^" + identifier + (nextLineIsBlank ? "" : lineEnding)
            }
        }
        return MarkdownTextEdit(range: NSRange(location: location, length: 0), replacement: insertion,
                                selectionAfter: NSRange(location: location + insertion.utf16.count, length: 0))
    }

    /// The line ending after `location`, or the note's first one at its end, so a new line
    /// keeps a CR LF note's line endings.
    private static func lineEnding(at location: Int, in source: NSString) -> String {
        if location < source.length {
            if source.character(at: location) == 0x0D, location + 1 < source.length, source.character(at: location + 1) == 0x0A { return "\r\n" }
            if source.character(at: location) == 0x0A { return "\n" }
        }
        let firstLineFeed = source.range(of: "\n")
        guard firstLineFeed.location != NSNotFound, firstLineFeed.location > 0 else { return "\n" }
        return source.character(at: firstLineFeed.location - 1) == 0x0D ? "\r\n" : "\n"
    }
}
