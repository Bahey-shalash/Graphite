import Foundation
import Markdown
import Yams

public struct NoteLink: Codable, Hashable, Sendable {
    public let target: String
    public let label: String?
    public let isEmbed: Bool
    public let isWiki: Bool
    public let location: Int
    /// 0 for a Markdown link whose source text could not be located exactly (see
    /// MarkdownSemantics.parse); such a link is indexed but never rewritten.
    public let length: Int
    public var range: NSRange { NSRange(location: location, length: length) }
}

public struct NoteSemantics: Sendable {
    public let links: [NoteLink]
    public let headings: [String]
    public let tags: [String]
    public let aliases: [String]
    public let body: String
    public let frontmatter: String?

    /// Text that is not Markdown, such as a PDF's text boxes: searchable, with no links,
    /// headings, tags, aliases or properties of its own.
    public static func plainText(_ text: String) -> NoteSemantics {
        NoteSemantics(links: [], headings: [], tags: [], aliases: [], body: text, frontmatter: nil)
    }
}

public enum MarkdownSemantics {
    /// Captures the YAML between the delimiters; works for LF and CRLF files and for
    /// empty frontmatter.
    private static let frontmatterPattern = MarkdownSemanticsPattern.frontmatterPattern.compiled()
    /// Group 1 is the embed's `!`, group 2 the link's content.
    private static let wikilinkPattern = MarkdownSemanticsPattern.wikilinkPattern.compiled()

    public static func parse(_ source: String) throws -> NoteSemantics {
        var body = source
        var frontmatter: String?
        var prefixCount = 0
        var aliases: [String] = []
        var tags: [String] = []
        // Frontmatter stays byte-for-byte in source. Yams reads properties only.
        let sourceString = source as NSString
        if let match = frontmatterPattern.firstMatch(in: source, range: NSRange(location: 0, length: sourceString.length)) {
            let yamlRange = match.range(at: 1)
            let yaml = yamlRange.location == NSNotFound ? "" : sourceString.substring(with: yamlRange)
            frontmatter = yaml; prefixCount = match.range.length
            body = sourceString.substring(from: prefixCount)
            // Invalid properties do not make the note body unsearchable. The
            // original YAML remains untouched for correction in the source editor.
            if let values = BoundedYAML.load(yaml) as? [String: Any] {
                aliases = stringList(values["aliases"] ?? values["alias"])
                // Obsidian also reads `tags: fiction, classic` (text) as separate tags.
                tags = stringList(values["tags"] ?? values["tag"])
                    .flatMap { tag in tag.split(whereSeparator: { character in character == "," || character.isWhitespace }).map(String.init) }
                    .map { tag in tag.hasPrefix("#") ? String(tag.dropFirst()) : tag }
                    .filter { tag in !tag.isEmpty }
            }
        }
        // A note nested too deeply for swift-markdown keeps its wikilinks and tags; it only
        // loses Markdown-syntax links, headings and code exclusions (see MarkdownNesting).
        let document = BoundedMarkdownParser.document(parsing: body)
        var links: [NoteLink] = []
        var headings: [String] = []
        var excluded: [NSRange] = []
        let bodyString = body as NSString
        // Ranges are converted after the walk: a link can end on a line whose columns
        // only a node the walk reaches later calibrates.
        var locationConverter = MarkdownSourceLocationConverter(body)
        var pendingRanges: [(role: SourceRangeRole, range: SourceRange, containerIndex: Int?)] = []
        var currentContainerIndex: Int?
        var stack: [(node: any Markup, followsLineBreak: Bool)] = document.map { document in [(document, false)] } ?? []
        while let (node, followsLineBreak) = stack.popLast() {
            if node is Paragraph || node is Heading {
                currentContainerIndex = locationConverter.addInlineContainer(node)
            } else if !(node is InlineMarkup) {
                currentContainerIndex = nil
            }
            let role: SourceRangeRole? = switch node {
            case is CodeBlock, is HTMLBlock: .codeBlock
            case is InlineCode: .inlineCode
            case is InlineHTML: .inlineHTML
            case let link as Link: link.destination.map { destination in .link(target: destination, label: link.plainText, isEmbed: false) }
            case let image as Markdown.Image: image.source.map { destination in .link(target: destination, label: image.plainText, isEmbed: true) }
            default: nil
            }
            if let range = node.range {
                if let currentContainerIndex, node is InlineMarkup {
                    locationConverter.recordInlineRange(range, of: role, startsLineText: followsLineBreak, inContainer: currentContainerIndex)
                }
                if let role { pendingRanges.append((role, range, currentContainerIndex)) }
            }
            if node is CodeBlock || node is InlineCode || node is HTMLBlock || node is InlineHTML { continue }
            if let heading = node as? Heading { headings.append(heading.plainText) }
            let children = Array(node.children)
            func isLineBreak(at childIndex: Int) -> Bool { childIndex >= 0 && (children[childIndex] is SoftBreak || children[childIndex] is LineBreak) }
            for (childIndex, child) in children.enumerated().reversed() {
                // A break right after another is a line holding only a backslash hard
                // break, so the node after it does not start the first break's line.
                stack.append((child, isLineBreak(at: childIndex - 1) && !isLineBreak(at: childIndex - 2)))
            }
        }
        locationConverter.resolveInlineLines()
        // A range that does not hold the syntax of its node was misplaced (see
        // MarkdownSourceLocationConverter). A rename rewrites Markdown links at their
        // ranges, so such a link keeps an empty range and is never rewritten, and code
        // in its paragraph is then found from the text instead.
        var unreliableContainerIndexes = Set<Int>()
        var markdownLinkRanges = Set<NSRange>()
        for pending in pendingRanges {
            let range = locationConverter.utf16Range(of: pending.range, role: pending.role, containerIndex: pending.containerIndex)
            let sourceText = bodyString.substring(with: range)
            switch pending.role {
            case .codeBlock:
                excluded.append(range)
            case .inlineCode, .inlineHTML:
                let delimiters = pending.role == .inlineCode ? ("`", "`") : ("<", ">")
                if sourceText.hasPrefix(delimiters.0) && sourceText.hasSuffix(delimiters.1) {
                    excluded.append(range)
                } else if let containerIndex = pending.containerIndex {
                    unreliableContainerIndexes.insert(containerIndex)
                }
            case .link(let target, let label, let isEmbed):
                if MarkdownLinkSource.isWritten(sourceText, destination: target, plainText: label, isImage: isEmbed), markdownLinkRanges.insert(range).inserted {
                    links.append(NoteLink(target: target, label: label, isEmbed: isEmbed, isWiki: false, location: prefixCount + range.location, length: range.length))
                    excluded.append(range)
                } else {
                    links.append(NoteLink(target: target, label: label, isEmbed: isEmbed, isWiki: false, location: prefixCount + range.location, length: 0))
                    if let containerIndex = pending.containerIndex { unreliableContainerIndexes.insert(containerIndex) }
                }
            }
        }
        for containerIndex in unreliableContainerIndexes {
            let containerRange = locationConverter.utf16Range(ofContainer: containerIndex)
            excluded += MarkdownCodeRanges.codeSpans(in: bodyString, range: containerRange).map(\.range)
        }
        func escaped(_ location: Int) -> Bool {
            var characterIndex = location, backslashCount = 0
            while characterIndex > 0 && bodyString.character(at: characterIndex - 1) == 92 { backslashCount += 1; characterIndex -= 1 }
            return backslashCount % 2 == 1
        }
        let codeAndMarkdownLinks = SortedRangeSet(excluded)
        for match in wikilinkPattern.matches(in: body, range: NSRange(location: 0, length: bodyString.length)) {
            var linkRange = match.range
            var isEmbed = match.range(at: 1).length > 0
            if escaped(linkRange.location) {
                // `\![[E]]` is a literal `!` before an ordinary link; `\[[E]]` is no link.
                guard isEmbed else { continue }
                isEmbed = false
                linkRange = NSRange(location: linkRange.location + 1, length: linkRange.length - 1)
            }
            guard !codeAndMarkdownLinks.intersects(linkRange) else { continue }
            let wikilinkContent = bodyString.substring(with: match.range(at: 2))
            let (target, label) = WikiLinkResolver.targetAndLabel(of: wikilinkContent)
            guard !target.isEmpty else { continue }
            links.append(NoteLink(target: target, label: label, isEmbed: isEmbed, isWiki: true, location: prefixCount + linkRange.location, length: linkRange.length))
        }
        // `[[#Heading]]` names a heading, not a tag.
        excluded += links.filter(\.isWiki).map { link in NSRange(location: link.location - prefixCount, length: link.length) }
        let codeAndLinks = SortedRangeSet(excluded)
        for match in TagSyntax.pattern.matches(in: body, range: NSRange(location: 0, length: bodyString.length)) where !codeAndLinks.intersects(match.range) && !escaped(match.range.location) {
            tags.append(bodyString.substring(with: match.range(at: 1)))
        }
        return NoteSemantics(links: links.sorted { leftLink, rightLink in leftLink.location < rightLink.location }, headings: headings, tags: Array(Set(tags)).sorted(), aliases: aliases, body: body, frontmatter: frontmatter)
    }
    /// Text items of a property; numbers and other scalars in a list count as text, so
    /// `tags: [fiction, 2024]` keeps both instead of dropping the list.
    private static func stringList(_ value: Any?) -> [String] {
        if let list = value as? [Any] { return list.compactMap(scalarText) }
        return scalarText(value).map { text in [text] } ?? []
    }

    private static func scalarText(_ value: Any?) -> String? {
        switch value {
        case let text as String: text
        case let number as Int: String(number)
        // `Int(exactly:)` rather than `Int(_:)`: a vault file can hold `1e300` or `.inf`,
        // which do not fit in Int and would trap during indexing on every launch.
        case let number as Double: Int(exactly: number).map { whole in String(whole) } ?? String(number)
        case let flag as Bool: String(flag)
        default: nil
        }
    }
}

/// What a Markdown node's source range is used for.
enum SourceRangeRole: Equatable {
    /// A code or HTML block, where wikilinks and tags are text.
    case codeBlock
    /// Inline code or HTML, where wikilinks and tags are text too.
    case inlineCode, inlineHTML
    /// A Markdown link or image; its text is not searched for wikilinks or tags either.
    case link(target: String, label: String, isEmbed: Bool)
}

/// How a misplaced range is recognized: a Markdown link's source text has the shape of
/// a link, `[text](destination)`, `[text][label]`, `[text]` or `<destination>`.
private enum MarkdownLinkSource {
    private static let escapedPunctuation = MarkdownLinkSourcePattern.escapedPunctuation.compiled()
    /// A CommonMark entity or numeric character reference, such as `&amp;` or `&#38;`.
    private static let characterReference = MarkdownLinkSourcePattern.characterReference.compiled()
    private static let backslash = UInt16(UInt8(ascii: "\\"))
    private static let backtick = UInt16(UInt8(ascii: "`"))
    private static let openingBracket = UInt16(UInt8(ascii: "["))
    private static let closingBracket = UInt16(UInt8(ascii: "]"))
    private static let openingParenthesis = UInt16(UInt8(ascii: "("))
    private static let closingParenthesis = UInt16(UInt8(ascii: ")"))

    /// Whether `sourceText` is written as a link (or image) to `destination`.
    static func isWritten(_ sourceText: String, destination: String, plainText: String, isImage: Bool) -> Bool {
        let units = Array(sourceText.utf16)
        let textStart = isImage ? 1 : 0
        guard !isImage || sourceText.hasPrefix("!") else { return false }
        guard textStart < units.count, units[textStart] == openingBracket else {
            // An autolink, `<https://…>`, or a bare web address.
            return !isImage && ((sourceText.hasPrefix("<") && sourceText.hasSuffix(">")) || sourceText == plainText)
        }
        guard let textEnd = closingBracketIndex(in: units, openingAt: textStart) else { return false }
        let restStart = textEnd + 1
        // A shortcut reference, `[text]`.
        guard restStart < units.count else { return true }
        switch units[restStart] {
        case openingBracket:
            // A full or collapsed reference; its label holds no unescaped bracket.
            return closingBracketIndex(in: units, openingAt: restStart) == units.count - 1
        case openingParenthesis:
            guard units.last == closingParenthesis else { return false }
            let fullRange = NSRange(location: 0, length: units.count)
            let unescapedText = escapedPunctuation.stringByReplacingMatches(in: sourceText, range: fullRange, withTemplate: "$1")
            // The parser decodes character references (`Fish&amp;Chips.md`) in the destination.
            // They are not decoded here, so a link written with one is accepted by its shape.
            let hasCharacterReference = characterReference.firstMatch(in: sourceText, range: fullRange) != nil
            return sourceText.contains(destination) || unescapedText.contains(destination) || hasCharacterReference
        default:
            return false
        }
    }

    /// The index of the `]` matching the `[` at `openingIndex`, skipping escaped
    /// characters and code spans.
    private static func closingBracketIndex(in units: [UInt16], openingAt openingIndex: Int) -> Int? {
        var depth = 0
        var index = openingIndex
        while index < units.count {
            let unit = units[index]
            if unit == backslash {
                index += 2
                continue
            }
            if unit == backtick {
                var runEnd = index
                while runEnd < units.count && units[runEnd] == backtick { runEnd += 1 }
                index = closingBacktickRunEnd(in: units, from: runEnd, length: runEnd - index) ?? runEnd
                continue
            }
            if unit == openingBracket { depth += 1 }
            if unit == closingBracket {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    private static func closingBacktickRunEnd(in units: [UInt16], from start: Int, length: Int) -> Int? {
        var index = start
        while index < units.count {
            guard units[index] == backtick else {
                index += 1
                continue
            }
            var runEnd = index
            while runEnd < units.count && units[runEnd] == backtick { runEnd += 1 }
            if runEnd - index == length { return runEnd }
            index = runEnd
        }
        return nil
    }
}

/// The constant patterns of `MarkdownSemantics`; `StaticPatternTests` compiles every case.
enum MarkdownSemanticsPattern: String, StaticPatternSet {
    case frontmatterPattern = #"\A---\r?\n(?:([\s\S]*?)\r?\n)?(?:---|\.\.\.)[ \t]*(?:\r?\n|$)"#
    case wikilinkPattern = #"(!?)\[\[([^\]\n]+)\]\]"#
}

/// The constant patterns of `MarkdownLinkSource`; `StaticPatternTests` compiles every case.
enum MarkdownLinkSourcePattern: String, StaticPatternSet {
    case escapedPunctuation = #"\\([!-/:-@\[-`{-~])"#
    case characterReference = "&(?:#[0-9]{1,7}|#[xX][0-9A-Fa-f]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});"
}
