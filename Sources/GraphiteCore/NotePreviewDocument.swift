import Foundation
import Markdown

/// Whether a callout starts folded (`[!note]-`), unfolded (`[!note]+`), or cannot fold.
public enum CalloutFolding: Equatable, Sendable {
    case notFoldable, expanded, collapsed
}

/// One unit of a note's reading view. Headings are their own blocks so a link to a
/// heading can scroll to it; widgets (embeds, bases) sit between Markdown runs.
public indirect enum NotePreviewBlock: Equatable, Sendable {
    case markdown(String)
    case heading(level: Int, text: String, anchor: String)
    case callout(type: String, title: String, folding: CalloutFolding, body: [NotePreviewBlock])
    /// A line that is only an embed, such as `![[Lecture.pdf#page=3]]` or `![[video.mp4]]`.
    case embed(EmbedReference)
    /// The YAML of a ```` ```base ```` code block.
    case baseDefinition(String)
    /// A `$$…$$` block on lines of its own, source included; centered like Obsidian's.
    case displayMath(String)
    /// A fenced code block in a language a community plugin draws (`registerMarkdownCodeBlockProcessor`),
    /// such as ```` ```dataview ````: the language as the plugin registered it, and the
    /// code between the fences.
    case pluginCodeBlock(language: String, source: String)
    /// The text of a ```` ```mermaid ```` code block, which the reading view draws as a diagram.
    case mermaidDiagram(String)
}

public enum NotePreviewDocument {
    /// Callouts nested deeper than this stay quoted Markdown. Each level is split by a
    /// recursive call that walks the rest of the callout again, so without a limit a
    /// crafted note of thousands of levels would exhaust the stack of the thread building
    /// the reading view and take time that grows with the square of its size.
    static let maximumCalloutNestingDepth = 16

    /// A reading-view block with where its text is in the body it was split from.
    public struct LocatedBlock: Equatable, Sendable {
        public let block: NotePreviewBlock
        /// The UTF-16 offset in the body at which the block's first line starts, which
        /// keeps a note's place when it switches between reading and writing.
        public let startOffset: Int
        /// For a Markdown run, the UTF-16 offset in the body at which each of its lines
        /// starts, so a task on one of them can be found in the note. Empty for other blocks.
        public let lineStartOffsets: [Int]
        /// The blocks of a callout's body, located likewise. Empty for other blocks.
        public let body: [LocatedBlock]
        /// How many lines of the body the block spans, fences included; 1 for blocks other
        /// than a plugin's code block, which is the only one that needs it.
        public var lineCount = 1
    }

    /// Splits a note body (frontmatter already removed) into reading-view blocks.
    /// Obsidian `%%` comments are removed first, so a comment around a heading, embed or
    /// formula hides all of it, as in Obsidian.
    public static func blocks(from body: String) -> [NotePreviewBlock] {
        locatedBlocks(from: body).map(\.block)
    }

    /// The blocks of `blocks(from:)`, each with where its lines start in `body`.
    /// - Parameter pluginCodeBlockLanguages: Languages community plugins draw; a fenced
    ///   block in one of them becomes a block of its own instead of staying code.
    public static func locatedBlocks(from body: String, pluginCodeBlockLanguages: Set<String> = []) -> [LocatedBlock] {
        let commentRanges = ObsidianComments.commentRanges(in: body)
        let bodyOffsets = ReplacedTextOffsets(replacements: commentRanges.map { commentRange in (commentRange, 0) })
        var lines: [String] = []
        var lineStartOffsets: [Int] = []
        var lineStart = 0
        for line in ObsidianComments.removing(commentRanges, from: body).components(separatedBy: "\n") {
            // Only removals were made, so every remaining character has a place in the body.
            lineStartOffsets.append(bodyOffsets.originalOffset(of: lineStart) ?? lineStart)
            lineStart += line.utf16.count + 1
            lines.append(line.hasSuffix("\r") ? String(line.dropLast()) : line)
        }
        return blocks(fromLines: lines, lineStartOffsets: lineStartOffsets, calloutDepth: 0, pluginCodeBlockLanguages: pluginCodeBlockLanguages)
    }

    private static func blocks(fromLines lines: [String], lineStartOffsets: [Int], calloutDepth: Int, pluginCodeBlockLanguages: Set<String>) -> [LocatedBlock] {
        let mathLines = DisplayMathLines(lines)
        var blocks: [LocatedBlock] = []
        var pendingMarkdown: [String] = []
        var pendingLineStartOffsets: [Int] = []
        func append(_ block: NotePreviewBlock, startingAtLine lineIndex: Int) {
            blocks.append(LocatedBlock(block: block, startOffset: lineStartOffsets[lineIndex], lineStartOffsets: [], body: []))
        }
        func appendMarkdown(_ lineIndices: ClosedRange<Int>) {
            pendingMarkdown.append(contentsOf: lines[lineIndices])
            pendingLineStartOffsets.append(contentsOf: lineStartOffsets[lineIndices])
        }
        func flushMarkdown() {
            let markdown = pendingMarkdown.joined(separator: "\n")
            if !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(LocatedBlock(block: .markdown(markdown), startOffset: pendingLineStartOffsets.first ?? 0, lineStartOffsets: pendingLineStartOffsets, body: []))
            }
            pendingMarkdown.removeAll()
            pendingLineStartOffsets.removeAll()
        }
        var listItems = ListItemContainers()
        var lineIndex = 0
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            // Fenced code passes through untouched; a base fence becomes a base view, a mermaid
            // fence a diagram unless a community plugin draws `mermaid`.
            if let (fence, info, _) = listItems.fenceOpening(of: line) {
                let language = info.lowercased()
                var closingIndex = lineIndex + 1
                while closingIndex < lines.count, !MarkdownFenceSyntax.closes(fence, lines[closingIndex].trimmingCharacters(in: .whitespaces)) {
                    closingIndex += 1
                }
                let lastFenceLineIndex = min(closingIndex, lines.count - 1)
                let code = lines[lineIndex...lastFenceLineIndex].dropFirst().dropLast(closingIndex < lines.count ? 1 : 0).joined(separator: "\n")
                // Matched as written, as Obsidian matches a processor's language.
                let pluginLanguage = MarkdownFenceSyntax.language(ofInfo: info)
                if language == "base" {
                    flushMarkdown()
                    append(.baseDefinition(code), startingAtLine: lineIndex)
                } else if !pluginLanguage.isEmpty, pluginCodeBlockLanguages.contains(pluginLanguage) {
                    flushMarkdown()
                    blocks.append(LocatedBlock(block: .pluginCodeBlock(language: pluginLanguage, source: code), startOffset: lineStartOffsets[lineIndex],
                                               lineStartOffsets: [], body: [], lineCount: lastFenceLineIndex - lineIndex + 1))
                } else if language == "mermaid" {
                    flushMarkdown()
                    append(.mermaidDiagram(code), startingAtLine: lineIndex)
                } else {
                    appendMarkdown(lineIndex...lastFenceLineIndex)
                }
                lineIndex = closingIndex + 1
                continue
            }
            // Display math is a block of its own, so `#` or `>` inside it means nothing.
            if trimmedLine.hasPrefix("$$") {
                let opening = mathLines.opening(at: lineIndex)
                if let opening, opening.isAtLineStart {
                    flushMarkdown()
                    let lastIndex = opening.closingLineIndex ?? lines.count - 1
                    append(.displayMath(lines[lineIndex...lastIndex].joined(separator: "\n")), startingAtLine: lineIndex)
                    lineIndex = lastIndex + 1
                    continue
                }
                // A closed `$$…$$` alone on its line is display math too. With text after
                // it (`$$E=mc^2$$ is famous`) it is inline math in a paragraph.
                if opening == nil, trimmedLine.hasSuffix("$$") {
                    flushMarkdown()
                    append(.displayMath(line), startingAtLine: lineIndex)
                    lineIndex += 1
                    continue
                }
            }
            if let heading = MarkdownHeadingSyntax.titledHeading(in: line) {
                flushMarkdown()
                append(.heading(level: heading.level, text: heading.text, anchor: anchor(forHeading: heading.text)), startingAtLine: lineIndex)
                lineIndex += 1
                continue
            }
            // A setext heading is its text line and its underline, which the block swallows.
            if let setextLevel = MarkdownHeadingSyntax.setextHeadingLevel(ofLine: line, nextLine: lineIndex + 1 < lines.count ? lines[lineIndex + 1] : nil) {
                flushMarkdown()
                let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
                append(.heading(level: setextLevel, text: text, anchor: anchor(forHeading: text)), startingAtLine: lineIndex)
                lineIndex += 2
                continue
            }
            if calloutDepth < maximumCalloutNestingDepth, let callout = MarkdownQuoteSyntax.calloutHeader(in: line) {
                flushMarkdown()
                var bodyLines: [String] = []
                var bodyLineStartOffsets: [Int] = []
                var bodyIndex = lineIndex + 1
                while bodyIndex < lines.count && lines[bodyIndex].hasPrefix(">") {
                    let quoteMarkerLength = lines[bodyIndex].dropFirst().hasPrefix(" ") ? 2 : 1
                    bodyLines.append(String(lines[bodyIndex].dropFirst(quoteMarkerLength)))
                    bodyLineStartOffsets.append(lineStartOffsets[bodyIndex] + quoteMarkerLength)
                    bodyIndex += 1
                }
                let body = Self.blocks(fromLines: bodyLines, lineStartOffsets: bodyLineStartOffsets, calloutDepth: calloutDepth + 1,
                                       pluginCodeBlockLanguages: pluginCodeBlockLanguages)
                blocks.append(LocatedBlock(block: .callout(type: callout.type, title: callout.title, folding: callout.folding, body: body.map(\.block)),
                                           startOffset: lineStartOffsets[lineIndex], lineStartOffsets: [], body: body))
                lineIndex = bodyIndex
                continue
            }
            // A web image (`![](https://…)`) is not a vault file. It stays Markdown, which the
            // renderer draws from the web as it does an inline one.
            if let embed = EmbedLocator.standaloneEmbed(onLine: line), !embed.isRemoteImage {
                flushMarkdown()
                append(.embed(embed), startingAtLine: lineIndex)
                lineIndex += 1
                continue
            }
            // A formula opened after other text (`- $$` in a list item, `Energy is $$`)
            // stays in its paragraph, closing line included, so that line does not start
            // a formula of its own.
            if let opening = mathLines.opening(at: lineIndex), let closingLineIndex = opening.closingLineIndex {
                appendMarkdown(lineIndex...closingLineIndex)
                lineIndex = closingLineIndex + 1
                continue
            }
            appendMarkdown(lineIndex...lineIndex)
            lineIndex += 1
        }
        flushMarkdown()
        return blocks
    }

    /// Obsidian matches heading links by heading text; the anchor normalizes spacing and
    /// case so `[[#Some  Heading]]` and `## some heading` meet.
    public static func anchor(forHeading text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Larger notes are shown as a link instead of being embedded in another note.
    public static let maximumEmbeddedNoteBytes = 1_048_576

    /// The part of a note from a heading up to the next heading of the same or higher
    /// level, as `![[Note#Heading]]` embeds it, with the UTF-16 offset in `body` at which it
    /// starts; nil when the note has no such heading. The anchor may be Obsidian's heading
    /// path, `parent#child`, which names the first `child` heading inside the `parent` section.
    public static func locatedSectionIfPresent(of body: String, headingAnchor: String) -> (text: String, location: Int)? {
        let lines = body.components(separatedBy: "\n")
        let headings = headingLines(in: lines, of: body)
        guard let targetPosition = headingPosition(matching: headingAnchor, in: headings) else { return nil }
        let target = headings[targetPosition]
        let endLineIndex = headings[(targetPosition + 1)...].first { heading in heading.level <= target.level }?.lineIndex ?? lines.count
        let location = lines[..<target.lineIndex].reduce(0) { length, line in length + line.utf16.count + 1 }
        return (lines[target.lineIndex..<endLineIndex].joined(separator: "\n"), location)
    }

    /// Headings of a note body in order, for the outline. Headings in code or in `%%`
    /// comments are not headings.
    public static func outline(of body: String) -> [(level: Int, text: String, anchor: String)] {
        headingLines(in: body.components(separatedBy: "\n"), of: body).map { heading in (heading.level, heading.text, heading.anchor) }
    }

    /// Where the line of the `occurrence`th heading (from zero) with `anchor` starts in `body`
    /// (frontmatter already removed), counting headings as the outline lists them. An anchor
    /// no heading has may be a heading's GitHub slug, as tables of contents link.
    public static func headingLineLocation(ofHeadingWithAnchor anchor: String, occurrence: Int = 0, in body: String) -> Int? {
        let lines = body.components(separatedBy: "\n")
        let headings = headingLines(in: lines, of: body)
        let matchingHeadings = headings.filter { heading in heading.anchor == anchor }
        let target: HeadingLine
        if matchingHeadings.indices.contains(occurrence) {
            target = matchingHeadings[occurrence]
        } else if matchingHeadings.isEmpty, occurrence == 0,
                  let slugPosition = HeadingSlug.position(ofSlug: anchor, amongHeadingAnchors: headings.map(\.anchor)) {
            target = headings[slugPosition]
        } else {
            return nil
        }
        return lines[..<target.lineIndex].reduce(0) { length, line in length + line.utf16.count + 1 }
    }

    private struct HeadingLine {
        let lineIndex: Int
        let level: Int
        let text: String
        let anchor: String
    }

    /// Every heading with its line, found in one pass that follows code fences and
    /// comments across lines, as the outline and sections both need.
    private static func headingLines(in lines: [String], of body: String) -> [HeadingLine] {
        let commentRanges = ObsidianComments.commentRanges(in: body)
        var fenceTracker = CodeFenceTracker()
        var headings: [HeadingLine] = []
        var nextLineStart = 0
        var commentIndex = 0
        for (lineIndex, line) in lines.enumerated() {
            var visibleLine = line
            // Offsets matter only while a comment lies ahead; most notes have none.
            if commentIndex < commentRanges.count {
                let lineRange = NSRange(location: nextLineStart, length: line.utf16.count)
                nextLineStart = NSMaxRange(lineRange) + 1
                while commentIndex < commentRanges.count, NSMaxRange(commentRanges[commentIndex]) <= lineRange.location { commentIndex += 1 }
                if commentIndex < commentRanges.count, commentRanges[commentIndex].location <= lineRange.location { continue }
                // `## Title %%note%%` is the heading "Title", as reading view shows it.
                let commentsOnLine = commentRanges[commentIndex...].prefix { commentRange in commentRange.location < NSMaxRange(lineRange) }
                if !commentsOnLine.isEmpty {
                    let uncommentedLine = NSMutableString(string: line)
                    for commentRange in commentsOnLine.reversed() {
                        let rangeOnLine = NSIntersectionRange(commentRange, lineRange)
                        uncommentedLine.deleteCharacters(in: NSRange(location: rangeOnLine.location - lineRange.location, length: rangeOnLine.length))
                    }
                    visibleLine = uncommentedLine as String
                }
            }
            guard !fenceTracker.isCodeLine(untrimmedLine: line) else { continue }
            if let heading = MarkdownHeadingSyntax.titledHeading(in: visibleLine) {
                headings.append(HeadingLine(lineIndex: lineIndex, level: heading.level, text: heading.text, anchor: anchor(forHeading: heading.text)))
            } else if let setextLevel = MarkdownHeadingSyntax.setextHeadingLevel(ofLine: visibleLine,
                                                                                 nextLine: lineIndex + 1 < lines.count ? lines[lineIndex + 1] : nil) {
                let text = visibleLine.trimmingCharacters(in: .whitespacesAndNewlines)
                headings.append(HeadingLine(lineIndex: lineIndex, level: setextLevel, text: text, anchor: anchor(forHeading: text)))
            }
        }
        return headings
    }

    private static func headingPosition(matching headingAnchor: String, in headings: [HeadingLine]) -> Int? {
        if let exactPosition = headings.firstIndex(where: { heading in heading.anchor == headingAnchor }) { return exactPosition }
        if let slugPosition = HeadingSlug.position(ofSlug: headingAnchor, amongHeadingAnchors: headings.map(\.anchor)) { return slugPosition }
        // A heading's own text may contain `#` (`C#`), so the path form is tried second.
        let pathAnchors = headingAnchor.components(separatedBy: "#").map(anchor(forHeading:)).filter { pathAnchor in !pathAnchor.isEmpty }
        guard pathAnchors.count > 1 else { return nil }
        var searchRange = headings.startIndex..<headings.endIndex
        var matchedPosition: Int?
        for pathAnchor in pathAnchors {
            guard let position = headings[searchRange].firstIndex(where: { heading in heading.anchor == pathAnchor }) else { return nil }
            matchedPosition = position
            let level = headings[position].level
            let sectionEnd = headings[(position + 1)..<searchRange.upperBound].firstIndex { heading in heading.level <= level } ?? searchRange.upperBound
            searchRange = (position + 1)..<sectionEnd
        }
        return matchedPosition
    }
}

extension NotePreviewDocument {
    /// A reference definition (`[label]: destination`), which links elsewhere in the run use.
    private static let referenceDefinitionPattern = NotePreviewDocumentPattern.referenceDefinitionPattern.compiled()

    /// The blocks with each run of Markdown divided into sections as Obsidian's reading view
    /// divides a note, one per top-level block (a paragraph, a list, a table, a quote, a code
    /// block), so community plugins' post-processors see and change one section at a time.
    /// Callout bodies are divided too. A run with reference definitions stays whole, since
    /// its links need them.
    public static func dividedIntoSections(_ blocks: [LocatedBlock]) -> [LocatedBlock] {
        blocks.flatMap { located -> [LocatedBlock] in
            switch located.block {
            case .markdown:
                return sections(of: located)
            case .callout(let type, let title, let folding, _):
                let body = dividedIntoSections(located.body)
                return [LocatedBlock(block: .callout(type: type, title: title, folding: folding, body: body.map(\.block)),
                                     startOffset: located.startOffset, lineStartOffsets: located.lineStartOffsets, body: body, lineCount: located.lineCount)]
            default:
                return [located]
            }
        }
    }

    private static func sections(of located: LocatedBlock) -> [LocatedBlock] {
        guard case .markdown(let markdown) = located.block else { return [located] }
        let lines = markdown.components(separatedBy: "\n")
        guard lines.count > 1, lines.count == located.lineStartOffsets.count,
              referenceDefinitionPattern.firstMatch(in: markdown, range: NSRange(location: 0, length: (markdown as NSString).length)) == nil else { return [located] }
        // A run nested too deeply to parse stays whole.
        guard let document = BoundedMarkdownParser.document(parsing: markdown) else { return [located] }
        var sections: [LocatedBlock] = []
        for child in document.children {
            guard let range = child.range else { return [located] }
            let firstLineIndex = range.lowerBound.line - 1
            // The range ends just after the block; at the start of a line, that line is not the block's.
            let lastLineIndex = range.upperBound.column == 1 ? range.upperBound.line - 2 : range.upperBound.line - 1
            guard lines.indices.contains(firstLineIndex), lines.indices.contains(lastLineIndex), firstLineIndex <= lastLineIndex else { return [located] }
            if let previous = sections.last, let previousLast = previous.lineStartOffsets.last,
               let previousLastIndex = located.lineStartOffsets.firstIndex(of: previousLast), previousLastIndex >= firstLineIndex {
                return [located]
            }
            sections.append(LocatedBlock(block: .markdown(lines[firstLineIndex...lastLineIndex].joined(separator: "\n")),
                                         startOffset: located.lineStartOffsets[firstLineIndex],
                                         lineStartOffsets: Array(located.lineStartOffsets[firstLineIndex...lastLineIndex]), body: [],
                                         lineCount: lastLineIndex - firstLineIndex + 1))
        }
        return sections.isEmpty ? [located] : sections
    }
}

/// The constant patterns of `NotePreviewDocument`; `StaticPatternTests` compiles every case.
enum NotePreviewDocumentPattern: String, StaticPatternSet {
    case referenceDefinitionPattern = #"^ {0,3}\[[^\]]+\]:"#

    var options: NSRegularExpression.Options { [.anchorsMatchLines] }
}
