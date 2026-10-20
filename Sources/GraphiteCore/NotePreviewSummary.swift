import Foundation

/// The start of a note as its library tile shows it: what reading view would show first,
/// never the Markdown source. Made from a bounded prefix of the file, so a long note costs
/// no more than a short one.
public struct NotePreviewSummary: Equatable, Sendable {
    /// One block of the note's start. Text is inline-styled (bold, italic, code,
    /// strikethrough) as reading view styles it; links show their label only.
    public enum Block: Equatable, Sendable {
        case heading(level: Int, text: AttributedString)
        case paragraph(AttributedString)
        /// `marker` is "•" or the item's number with its dot; `depth` 0 for a top-level item.
        case listItem(marker: String, depth: Int, text: AttributedString)
        case task(isDone: Bool, depth: Int, text: AttributedString)
        case quote(AttributedString)
        /// A callout's header: its type as written (`tip`) and its title, or the type when untitled.
        case callout(type: String, title: AttributedString)
        /// The first lines of a fenced code block.
        case code(String)
        case rule
        /// Where the first embedded picture sits; its file is `firstPictureTarget`.
        case picture
    }

    /// How much of a note is read for its tile.
    public static let maximumPrefixBytes = 4096
    /// A tile shows no more blocks than this; a page holds fewer.
    public static let maximumBlockCount = 24
    /// A code block shows no more lines than this.
    static let maximumCodeLineCount = 6

    public let blocks: [Block]
    /// The first picture embedded in the note's start (`![[photo.png]]`, `![](photo.png)`),
    /// as written; the tile resolves it like a link.
    public let firstPictureTarget: String?

    public init(blocks: [Block], firstPictureTarget: String?) {
        self.blocks = blocks
        self.firstPictureTarget = firstPictureTarget
    }

    private static let pictureExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp"]

    /// The summary of a note's first bytes. `isWholeFile` is false when the text was cut at
    /// `maximumPrefixBytes`; a frontmatter block still open at the cut then hides everything.
    public static func summary(ofPrefix prefix: String, isWholeFile: Bool) -> NotePreviewSummary {
        let text = prefix as NSString
        let frontmatterLength = FrontmatterLocator.length(in: text)
        if frontmatterLength == 0, !isWholeFile, prefix.hasPrefix("---\n") || prefix.hasPrefix("---\r\n") {
            return NotePreviewSummary(blocks: [], firstPictureTarget: nil)
        }
        var sourceLines = text.substring(from: frontmatterLength).components(separatedBy: .newlines)
        // A line cut at the end of the prefix is not shown half.
        if !isWholeFile, sourceLines.count > 1 { sourceLines.removeLast() }
        var reader = BlockReader()
        for sourceLine in sourceLines where reader.blocks.count < maximumBlockCount {
            reader.read(sourceLine)
        }
        reader.finishCodeBlock()
        return NotePreviewSummary(blocks: Array(reader.blocks.prefix(maximumBlockCount)), firstPictureTarget: reader.firstPictureTarget)
    }

    /// Reads a note line by line into blocks, keeping track of fences and the first picture.
    private struct BlockReader {
        var blocks: [Block] = []
        var firstPictureTarget: String?
        private var codeLines: [String]?
        private var isInMath = false

        mutating func read(_ sourceLine: String) {
            let trimmed = sourceLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if codeLines == nil { codeLines = [] } else { finishCodeBlock() }
                return
            }
            if codeLines != nil {
                if codeLines?.count ?? 0 < NotePreviewSummary.maximumCodeLineCount { codeLines?.append(sourceLine) }
                return
            }
            if trimmed == "$$" { isInMath.toggle(); return }
            if isInMath || trimmed.isEmpty || trimmed.hasPrefix("%%") { return }
            if let target = NotePreviewSummary.embedTarget(of: trimmed) {
                let isPicture = NotePreviewSummary.pictureExtensions.contains((target as NSString).pathExtension.lowercased())
                if isPicture, firstPictureTarget == nil {
                    firstPictureTarget = target
                    blocks.append(.picture)
                }
                return
            }
            if let block = NotePreviewSummary.block(from: sourceLine) { blocks.append(block) }
        }

        mutating func finishCodeBlock() {
            guard let lines = codeLines else { return }
            codeLines = nil
            if !lines.isEmpty { blocks.append(.code(lines.joined(separator: "\n"))) }
        }
    }

    private static func block(from sourceLine: String) -> Block? {
        let indentation = sourceLine.prefix { character in character == " " || character == "\t" }
        // A tab or four spaces nest an item one level deeper.
        let depth = indentation.reduce(0) { width, character in width + (character == "\t" ? 4 : 1) } / 4
        var content = Substring(sourceLine.dropFirst(indentation.count))
        if content.hasPrefix(">") {
            while content.hasPrefix(">") { content = content.dropFirst().drop { character in character == " " } }
            if content.hasPrefix("[!"), let close = content.firstIndex(of: "]") {
                let type = String(content[content.index(content.startIndex, offsetBy: 2)..<close])
                let title = content[content.index(after: close)...].drop { character in character == "-" || character == "+" || character == " " }
                return .callout(type: type, title: inlineText(title.isEmpty ? Substring(type.capitalized) : title))
            }
            return content.isEmpty ? nil : .quote(inlineText(content))
        }
        let headingMarks = content.prefix { character in character == "#" }
        if (1...6).contains(headingMarks.count), content.dropFirst(headingMarks.count).first == " " {
            return .heading(level: headingMarks.count, text: inlineText(content.dropFirst(headingMarks.count + 1)))
        }
        for (marker, isDone) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true), ("* [ ] ", false), ("* [x] ", true)] where content.hasPrefix(marker) {
            return .task(isDone: isDone, depth: depth, text: inlineText(content.dropFirst(marker.count)))
        }
        if content.hasPrefix("- ") || content.hasPrefix("* ") || content.hasPrefix("+ ") {
            return .listItem(marker: "•", depth: depth, text: inlineText(content.dropFirst(2)))
        }
        if let dot = content.firstIndex(where: { character in character == "." || character == ")" }), !content[..<dot].isEmpty,
           content[..<dot].allSatisfy(\.isNumber), content[content.index(after: dot)...].first == " " {
            return .listItem(marker: content[..<dot] + ".", depth: depth, text: inlineText(content[content.index(dot, offsetBy: 2)...]))
        }
        if content.count >= 3, content.allSatisfy({ character in character == "-" || character == "*" || character == "_" || character == " " }) {
            return .rule
        }
        let text = inlineText(content)
        return text.characters.isEmpty ? nil : .paragraph(text)
    }

    /// The target of a line that is only an embed, as written.
    private static func embedTarget(of trimmed: String) -> String? {
        if trimmed.hasPrefix("![["), trimmed.hasSuffix("]]") {
            let inner = trimmed.dropFirst(3).dropLast(2)
            return String(inner.split(separator: "|", maxSplits: 1).first ?? inner).trimmingCharacters(in: .whitespaces)
        }
        if trimmed.hasPrefix("!["), trimmed.hasSuffix(")"), let open = trimmed.range(of: "](") {
            let destination = trimmed[open.upperBound..<trimmed.index(before: trimmed.endIndex)]
            let target = destination.split(separator: " ", maxSplits: 1).first.map(String.init) ?? String(destination)
            return target.removingPercentEncoding ?? target
        }
        return nil
    }

    /// Reading view's text of one line: emphasis, code and strikethrough as styles; Wikilinks
    /// and Markdown links as their labels; inline embeds, highlights' marks and comments gone.
    static func inlineText<Text: StringProtocol>(_ source: Text) -> AttributedString {
        let markdown = obsidianSyntaxRemoved(from: String(source))
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        let parsed = try? AttributedString(markdown: markdown, options: options) // Unparsable Markdown shows as written.
        var text = parsed ?? AttributedString(markdown)
        // A tile is tapped as a whole; a link inside it must not take the tap.
        for run in text.runs where run.link != nil { text[run.range].link = nil }
        return text
    }

    /// The Obsidian syntax CommonMark does not know, turned into what reading view shows.
    private static func obsidianSyntaxRemoved(from source: String) -> String {
        var output = ""
        var index = source.startIndex
        while index < source.endIndex {
            let rest = source[index...]
            if rest.hasPrefix("![["), let close = rest.range(of: "]]") {
                index = close.upperBound
                continue
            }
            if rest.hasPrefix("[["), let close = rest.range(of: "]]") {
                let inner = rest[rest.index(index, offsetBy: 2)..<close.lowerBound]
                let parts = inner.split(separator: "|", maxSplits: 1)
                let label = parts.count == 2 ? parts[1] : inner.split(separator: "#").first ?? inner
                output += label.replacingOccurrences(of: "*", with: "\\*").replacingOccurrences(of: "_", with: "\\_")
                index = close.upperBound
                continue
            }
            if rest.hasPrefix("%%"), let close = rest.dropFirst(2).range(of: "%%") {
                index = close.upperBound
                continue
            }
            if rest.hasPrefix("==") {
                index = source.index(index, offsetBy: 2)
                continue
            }
            output.append(source[index])
            index = source.index(after: index)
        }
        return output.trimmingCharacters(in: .whitespaces)
    }
}
