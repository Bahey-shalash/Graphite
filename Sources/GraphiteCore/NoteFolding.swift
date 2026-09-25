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
        for (index, line) in lines.enumerated() where !line.isCode {
            if let level = MarkdownEditing.headingLevel(of: line.content) {
                // The section runs to the next heading of the same or a higher level.
                var lastIndex = index
                var nextIndex = index + 1
                while nextIndex < lines.count {
                    if !lines[nextIndex].isCode, let nextLevel = MarkdownEditing.headingLevel(of: lines[nextIndex].content), nextLevel <= level { break }
                    lastIndex = nextIndex
                    nextIndex += 1
                }
                // Blank lines just before the next heading stay visible, as in Obsidian.
                while lastIndex > index, lines[lastIndex].content.trimmingCharacters(in: .whitespaces).isEmpty { lastIndex -= 1 }
                let headingKey = key("h\(level)|" + line.content.trimmingCharacters(in: .whitespaces))
                if let region = region(kind: .heading(level: level), header: line, last: lines[lastIndex], hasBody: lastIndex > index, key: headingKey) {
                    regions.append(region)
                }
            } else if let listLine = MarkdownEditing.listLine(line.content), listLine.isListItem {
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
