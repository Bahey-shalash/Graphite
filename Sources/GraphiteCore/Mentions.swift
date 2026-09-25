import Foundation

/// Where a note is named in other notes: linked mentions (backlinks) with the line around
/// each link, and unlinked mentions, the note's name or an alias written as plain text,
/// which Obsidian offers to turn into links.
public enum Mentions {
    /// Links in `text` that a caller-supplied test says reach the note; the test gets each
    /// link that could name it (by its last path component), so resolution is rare.
    /// - Parameter names: The note's name without extension and its aliases.
    public static func linkCandidates(in text: String, names: [String]) throws -> [NoteLink] {
        let keys = Set(names.map { name in WikiLinkResolver.comparisonKey(name).lowercased() })
        return try NoteLinkScanner.links(in: text).filter { link in
            guard !link.isEmbed else { return false }
            var pathPart = WikiLinkResolver.pathPart(link.target)
            if !link.isWiki { pathPart = pathPart.removingPercentEncoding ?? pathPart }
            guard !pathPart.isEmpty, URL(string: pathPart)?.scheme == nil else { return false }
            let lastComponent = (pathPart as NSString).lastPathComponent
            let stem = lastComponent.lowercased().hasSuffix(".md") ? String(lastComponent.dropLast(3)) : lastComponent
            return keys.contains(WikiLinkResolver.comparisonKey(stem).lowercased())
        }
    }

    /// The places in `text` where one of `names` is written as whole words, ignoring case,
    /// outside links, embeds, code, math, comments, tags, web addresses and frontmatter.
    /// Longer names are preferred where names overlap ("Zebra note" over "Zebra").
    public static func unlinkedMentions(of names: [String], in text: String) -> [NSRange] {
        let source = text as NSString
        let searchedNames = names.map { name in name.trimmingCharacters(in: .whitespaces) }.filter { name in !name.isEmpty }
            .sorted { first, second in (first as NSString).length > (second as NSString).length }
        guard !searchedNames.isEmpty else { return [] }
        let excluded = excludedRanges(in: source)
        var mentions: [NSRange] = []
        for name in searchedNames {
            var searchRange = NSRange(location: 0, length: source.length)
            while searchRange.length > 0 {
                let found = source.range(of: name, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
                guard found.location != NSNotFound else { break }
                searchRange = NSRange(location: NSMaxRange(found), length: source.length - NSMaxRange(found))
                guard isWholeWords(found, in: source),
                      !excluded.contains(where: { range in NSIntersectionRange(range, found).length > 0 }),
                      !mentions.contains(where: { mention in NSIntersectionRange(mention, found).length > 0 }) else { continue }
                mentions.append(found)
            }
        }
        return mentions.sorted { first, second in first.location < second.location }
    }

    /// The edit that turns an unlinked mention into a link to the note, keeping the words
    /// as written: `[[Note]]` when they match the link text, else `[[Note|words]]`.
    /// - Parameters:
    ///   - linkTarget: The note as the vault's link format names it (without `.md` for Wikilinks).
    ///   - markdownDestination: The encoded destination for a Markdown link, with `.md`.
    public static func linkingEdit(mention range: NSRange, in text: String, linkTarget: String, usesWikilinks: Bool, markdownDestination: String) -> MarkdownTextEdit {
        let words = (text as NSString).substring(with: range)
        let link: String
        if usesWikilinks {
            link = words == linkTarget ? "[[\(linkTarget)]]" : "[[\(linkTarget)|\(words)]]"
        } else {
            let label = words.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            link = "[\(label)](\(markdownDestination))"
        }
        return MarkdownTextEdit(range: range, replacement: link, selectionAfter: NSRange(location: range.location + (link as NSString).length, length: 0))
    }

    // MARK: Private

    private static let excludedPatterns: [NSRegularExpression] = [
        // Wikilinks and embeds, Markdown links and images, inline math, comments, tags, web addresses.
        "!?\\[\\[[^\\]\\n]*\\]\\]", "!?\\[[^\\]\\n]*\\]\\([^)\\n]*\\)", "(?<!\\$)\\$[^$\\n]+\\$(?!\\$)", "%%[\\s\\S]*?%%",
        "(?<![\\p{L}\\p{N}_/&#])#[\\p{L}\\p{N}_/\\-]+", "[A-Za-z][A-Za-z0-9+.-]*://[^\\s)>\\]]+", "<[^>\\n]+>",
    ].compactMap { pattern in try? NSRegularExpression(pattern: pattern) }

    private static func excludedRanges(in source: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        let frontmatterLength = FrontmatterLocator.length(in: source)
        if frontmatterLength > 0 { ranges.append(NSRange(location: 0, length: frontmatterLength)) }
        ranges += MarkdownCodeRanges.ranges(in: source)
        let wholeText = NSRange(location: 0, length: source.length)
        for pattern in excludedPatterns {
            ranges += pattern.matches(in: source as String, range: wholeText).map(\.range)
        }
        // Fenced code and display math, line by line.
        var tracker = CodeFenceTracker()
        var isInsideMath = false
        var location = 0
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let line = source.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let isCode = tracker.isCodeLine(line)
            let togglesMath = !isCode && line.hasPrefix("$$")
            let closesOnSameLine = togglesMath && line.count > 2 && line.hasSuffix("$$")
            if isCode || isInsideMath || togglesMath { ranges.append(lineRange) }
            if togglesMath && !closesOnSameLine { isInsideMath.toggle() }
            location = NSMaxRange(lineRange)
        }
        return ranges
    }

    private static func isWholeWords(_ range: NSRange, in source: NSString) -> Bool {
        func isWordCharacter(at index: Int) -> Bool {
            guard index >= 0, index < source.length, let scalar = Unicode.Scalar(source.character(at: index)) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
        return !isWordCharacter(at: range.location - 1) && !isWordCharacter(at: NSMaxRange(range))
    }
}
