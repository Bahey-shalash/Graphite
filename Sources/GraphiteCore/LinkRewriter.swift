import Foundation

/// Every link written in a note: those in the body, and Wikilinks and Markdown links
/// written as property values in the frontmatter, which Obsidian also updates on rename.
///
/// Two kinds of link are reported with a range wider than the link itself, so a rewrite
/// of the reported text stays valid:
/// - A frontmatter link that is the only link in a quoted YAML value is reported with its
///   quotes (`'[[Note]]'`); its target is read without YAML's escapes.
/// - A reference-style link (`[text][ref]`) keeps its own entry, whose text has no
///   destination to rewrite, and its definition (`[ref]: Note.md`) is reported as a link too.
public enum NoteLinkScanner {
    private static let wikiLinkPattern = try? NSRegularExpression(pattern: "(!?)\\[\\[([^\\]\\n]+)\\]\\]")
    /// A line that may hold a link reference definition, up to its opening bracket, in the
    /// body or in a block quote.
    private static let definitionStartPattern = try? NSRegularExpression(pattern: "^(?:[ \\t]*>)*[ ]{0,3}\\[", options: [.anchorsMatchLines])

    public static func links(in text: String) throws -> [NoteLink] {
        let semantics = try MarkdownSemantics.parse(text)
        let source = text as NSString
        let frontmatterLength = FrontmatterLocator.length(in: source)
        let bodyLinks = semantics.links + referenceDefinitions(usedBy: semantics.links, in: source, bodyStart: frontmatterLength)
        guard frontmatterLength > 0 else { return bodyLinks.sorted { leftLink, rightLink in leftLink.location < rightLink.location } }
        return (frontmatterLinks(in: source, frontmatterLength: frontmatterLength) + bodyLinks)
            .sorted { leftLink, rightLink in leftLink.location < rightLink.location }
    }

    // MARK: Frontmatter

    private struct FrontmatterLinkMatch {
        let range: NSRange
        let isEmbed: Bool
        let isWiki: Bool
        /// The Wikilink's content between the brackets, or the Markdown link's label.
        let content: String
        /// The Markdown link's destination as written; empty for a Wikilink.
        let destination: String
    }

    private static func frontmatterLinks(in source: NSString, frontmatterLength: Int) -> [NoteLink] {
        let frontmatterRange = NSRange(location: 0, length: frontmatterLength)
        var matches: [FrontmatterLinkMatch] = []
        var wikiLinkRanges: [NSRange] = []
        for match in wikiLinkPattern?.matches(in: source as String, range: frontmatterRange) ?? [] {
            wikiLinkRanges.append(match.range)
            matches.append(FrontmatterLinkMatch(range: match.range, isEmbed: match.range(at: 1).length > 0, isWiki: true,
                                                content: source.substring(with: match.range(at: 2)), destination: ""))
        }
        matches += frontmatterMarkdownLinks(in: source, range: frontmatterRange, excluding: wikiLinkRanges)
        matches.sort { leftMatch, rightMatch in leftMatch.range.location < rightMatch.range.location }
        // Both lists are in text order, so each link's quoted value is found in one pass.
        let quotedValues = YAMLQuotedValue.values(in: source, range: frontmatterRange)
        var valueIndex = 0
        let enclosingValues: [YAMLQuotedValue?] = matches.map { match in
            while valueIndex < quotedValues.count, NSMaxRange(quotedValues[valueIndex].range) <= match.range.location { valueIndex += 1 }
            guard valueIndex < quotedValues.count else { return nil }
            let value = quotedValues[valueIndex]
            return value.range.location <= match.range.location && NSMaxRange(match.range) <= NSMaxRange(value.range) ? value : nil
        }
        var linkCountByValueLocation: [Int: Int] = [:]
        for value in enclosingValues.compactMap({ value in value }) { linkCountByValueLocation[value.range.location, default: 0] += 1 }
        var links: [NoteLink] = []
        for (match, quotedValue) in zip(matches, enclosingValues) {
            // A link that is the only one in a quoted value is reported with the quotes, so
            // the rewrite can escape a new name for them (`'[[Newton''s laws]]'`). Several
            // links in one quoted value keep their own ranges; a new name with that quote
            // would then need escaping the rewrite cannot see, a rare case left as it is.
            let isOnlyLinkInValue = quotedValue.map { value in linkCountByValueLocation[value.range.location] == 1 } ?? false
            let reportedRange = isOnlyLinkInValue ? (quotedValue?.range ?? match.range) : match.range
            let unescape = { (text: String) in quotedValue.map { value in value.unescaped(text) } ?? text }
            if match.isWiki {
                let (target, label) = WikiLinkResolver.targetAndLabel(of: unescape(match.content))
                guard !target.isEmpty else { continue }
                links.append(NoteLink(target: target, label: label, isEmbed: match.isEmbed, isWiki: true,
                                      location: reportedRange.location, length: reportedRange.length))
            } else {
                var destination = unescape(match.destination)
                if destination.hasPrefix("<") && destination.hasSuffix(">") { destination = String(destination.dropFirst().dropLast()) }
                links.append(NoteLink(target: destination, label: unescape(match.content), isEmbed: match.isEmbed, isWiki: false,
                                      location: reportedRange.location, length: reportedRange.length))
            }
        }
        return links
    }

    /// Inline Markdown links in the frontmatter, each on one line, read with CommonMark's
    /// rules for the label and destination (balanced parentheses, escapes, code spans).
    private static func frontmatterMarkdownLinks(in source: NSString, range: NSRange, excluding wikiLinkRanges: [NSRange]) -> [FrontmatterLinkMatch] {
        var matches: [FrontmatterLinkMatch] = []
        var searchLocation = range.location
        while searchLocation < NSMaxRange(range) {
            let opening = source.range(of: "[", options: .literal, range: NSRange(location: searchLocation, length: NSMaxRange(range) - searchLocation))
            guard opening.location != NSNotFound else { break }
            searchLocation = opening.location + 1
            guard !wikiLinkRanges.contains(where: { wikiRange in NSLocationInRange(opening.location, wikiRange) }),
                  !MarkdownLinkSyntax.isEscaped(opening.location, in: source) else { continue }
            let lineEnd = NSMaxRange(source.lineRange(for: NSRange(location: opening.location, length: 0)))
            guard let link = MarkdownLinkSyntax.inlineLink(in: source, openingBracket: opening.location, limit: min(lineEnd, NSMaxRange(range))) else { continue }
            let isEmbed = opening.location > 0 && source.character(at: opening.location - 1) == MarkdownLinkSyntax.exclamationMark
            let linkRange = isEmbed ? NSRange(location: opening.location - 1, length: NSMaxRange(link.range) - opening.location + 1) : link.range
            matches.append(FrontmatterLinkMatch(range: linkRange, isEmbed: isEmbed, isWiki: false,
                                                content: source.substring(with: link.labelRange), destination: source.substring(with: link.destinationRange)))
            searchLocation = NSMaxRange(link.range)
        }
        return matches
    }

    // MARK: Reference definitions

    /// The definitions (`[ref]: Note.md`) that reference-style links in the body use. The
    /// parser reports such a link with the range of `[text][ref]` only, which holds no
    /// destination; the definition is where a rename has to change the path.
    private static func referenceDefinitions(usedBy bodyLinks: [NoteLink], in source: NSString, bodyStart: Int) -> [NoteLink] {
        var usedTargets: [String: Bool] = [:]
        for link in bodyLinks where !link.isWiki {
            let linkText = source.substring(with: link.range) as NSString
            // An autolink (`<https://…>`) has no label; an inline link has its destination.
            guard linkText.hasPrefix("[") || linkText.hasPrefix("!["),
                  MarkdownLinkSyntax.destinationRange(inLinkText: linkText) == nil else { continue }
            if usedTargets[link.target] == nil { usedTargets[link.target] = link.isEmbed }
        }
        guard !usedTargets.isEmpty, let definitionStartPattern else { return [] }
        let codeRanges = MarkdownCodeRanges.ranges(in: source)
        var definitions: [NoteLink] = []
        let body = NSRange(location: bodyStart, length: source.length - bodyStart)
        for match in definitionStartPattern.matches(in: source as String, range: body) {
            let opening = NSMaxRange(match.range) - 1
            guard !MarkdownCodeRanges.range(NSRange(location: opening, length: 1), isInside: codeRanges),
                  let definition = MarkdownLinkSyntax.definition(in: source, openingBracket: opening) else { continue }
            var destination = source.substring(with: definition.destinationRange)
            if destination.hasPrefix("<") && destination.hasSuffix(">") { destination = String(destination.dropFirst().dropLast()) }
            guard let isEmbed = usedTargets[destination] else { continue }
            let definitionRange = NSRange(location: opening, length: NSMaxRange(definition.destinationRange) - opening)
            definitions.append(NoteLink(target: destination, label: nil, isEmbed: isEmbed, isWiki: false,
                                        location: definitionRange.location, length: definitionRange.length))
        }
        return definitions
    }
}

/// A quoted YAML scalar on one line of the frontmatter, such as `'[[Note]]'` or `"[[Note]]"`.
struct YAMLQuotedValue {
    /// The value with its quotes.
    let range: NSRange
    let isSingleQuoted: Bool

    private static let singleQuote: unichar = 0x27
    private static let doubleQuote: unichar = 0x22
    private static let backslash: unichar = 0x5C

    /// Quoted values that start where YAML starts a value (after `key:`, `-`, `[`, `,` or
    /// `{`) and end where a value ends, so an apostrophe inside plain text is not one.
    static func values(in source: NSString, range: NSRange) -> [YAMLQuotedValue] {
        var values: [YAMLQuotedValue] = []
        var lineStart = range.location
        while lineStart < NSMaxRange(range) {
            let lineRange = source.lineRange(for: NSRange(location: lineStart, length: 0))
            let lineEnd = min(NSMaxRange(lineRange), NSMaxRange(range))
            var index = lineStart
            var previousSignificant: unichar?
            while index < lineEnd {
                let character = source.character(at: index)
                if character == singleQuote || character == doubleQuote, startsValue(after: previousSignificant),
                   let closing = closingQuote(of: character, openedAt: index, in: source, lineEnd: lineEnd),
                   endsValue(at: closing + 1, in: source, lineEnd: lineEnd) {
                    values.append(YAMLQuotedValue(range: NSRange(location: index, length: closing + 1 - index), isSingleQuoted: character == singleQuote))
                    previousSignificant = character
                    index = closing + 1
                    continue
                }
                if character == 0x23 /* # */, previousSignificant == nil || isSpace(source.character(at: index - 1)) { break }
                if !isSpace(character) && character != 0x0A && character != 0x0D { previousSignificant = character }
                index += 1
            }
            lineStart = NSMaxRange(lineRange)
        }
        return values
    }

    /// `text` from inside the value, with YAML's escapes for this quote undone.
    func unescaped(_ text: String) -> String {
        isSingleQuoted
            ? text.replacingOccurrences(of: "''", with: "'")
            : text.replacingOccurrences(of: "\\\\", with: "\u{0}").replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\u{0}", with: "\\")
    }

    /// `text` escaped to sit inside a value quoted with `quote`.
    static func escaped(_ text: String, quote: unichar) -> String {
        quote == singleQuote
            ? text.replacingOccurrences(of: "'", with: "''")
            : text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// The quote character around a link's whole text, when it was reported as a quoted value.
    static func enclosingQuote(of linkText: NSString) -> unichar? {
        guard linkText.length >= 2 else { return nil }
        let first = linkText.character(at: 0), last = linkText.character(at: linkText.length - 1)
        guard first == last, first == singleQuote || first == doubleQuote else { return nil }
        return first
    }

    private static func startsValue(after previousSignificant: unichar?) -> Bool {
        guard let previousSignificant else { return true }
        // `:`, `-`, `?`, `[`, `,` and `{`.
        return [0x3A, 0x2D, 0x3F, 0x5B, 0x2C, 0x7B].contains(previousSignificant)
    }

    private static func closingQuote(of quote: unichar, openedAt start: Int, in source: NSString, lineEnd: Int) -> Int? {
        var index = start + 1
        while index < lineEnd {
            let character = source.character(at: index)
            if quote == doubleQuote && character == backslash { index += 2; continue }
            if character == quote {
                // Inside single quotes, `''` is an escaped quote.
                if quote == singleQuote, index + 1 < lineEnd, source.character(at: index + 1) == singleQuote { index += 2; continue }
                return index
            }
            index += 1
        }
        return nil
    }

    private static func endsValue(at location: Int, in source: NSString, lineEnd: Int) -> Bool {
        var index = location
        while index < lineEnd, isSpace(source.character(at: index)) { index += 1 }
        guard index < lineEnd else { return true }
        // A line ending, `,`, `]`, `}`, or a comment.
        return [0x0A, 0x0D, 0x2C, 0x5D, 0x7D, 0x23].contains(source.character(at: index))
    }

    private static func isSpace(_ character: unichar) -> Bool { character == 0x20 || character == 0x09 }
}

/// CommonMark's boundaries of a Markdown link's parts, read from its source text. The
/// rewrite must change exactly the destination the parser read: a destination may hold
/// balanced parentheses (`Pasted image (2).png`), and a label may hold an image, a code
/// span or an escaped bracket.
enum MarkdownLinkSyntax {
    static let exclamationMark: unichar = 0x21
    private static let backslash: unichar = 0x5C
    private static let backtick: unichar = 0x60
    private static let leftSquareBracket: unichar = 0x5B
    private static let rightSquareBracket: unichar = 0x5D
    private static let openingParenthesis: unichar = 0x28
    private static let closingParenthesis: unichar = 0x29
    private static let lessThan: unichar = 0x3C
    private static let greaterThan: unichar = 0x3E
    private static let colon: unichar = 0x3A
    private static let lineFeed: unichar = 0x0A
    private static let carriageReturn: unichar = 0x0D

    struct InlineLink {
        /// From the label's `[` through the closing `)`.
        let range: NSRange
        /// Inside the label's brackets.
        let labelRange: NSRange
        /// The destination as written, with its angle brackets if any.
        let destinationRange: NSRange
    }

    /// The destination of the link or link reference definition that `linkText` holds: its
    /// label followed by `(` or `:` and a valid destination. Nil for a reference-style link
    /// (`[text][ref]`), which has no destination of its own.
    ///
    /// A link's own text starts with its label (after `!`), and only that label is read, so an
    /// image inside the label of a reference-style link is never taken for the link. A link
    /// reported with its quoted YAML value may follow other text, so there every label is tried.
    static func destinationRange(inLinkText linkText: NSString) -> NSRange? {
        let readsEveryLabel = YAMLQuotedValue.enclosingQuote(of: linkText) != nil
        var searchLocation = 0
        while searchLocation < linkText.length {
            let opening = linkText.range(of: "[", options: .literal, range: NSRange(location: searchLocation, length: linkText.length - searchLocation))
            guard opening.location != NSNotFound else { return nil }
            searchLocation = opening.location + 1
            if let destination = destinationRange(afterLabelAt: opening.location, in: linkText) { return destination }
            if !readsEveryLabel { return nil }
        }
        return nil
    }

    private static func destinationRange(afterLabelAt openingBracket: Int, in linkText: NSString) -> NSRange? {
        guard !isEscaped(openingBracket, in: linkText),
              let labelEnd = labelEnd(in: linkText, openingBracket: openingBracket, limit: linkText.length),
              labelEnd + 1 < linkText.length else { return nil }
        let following = linkText.character(at: labelEnd + 1)
        guard following == openingParenthesis || following == colon else { return nil }
        return destinationRange(in: linkText, from: labelEnd + 2, limit: linkText.length)
    }

    /// The inline link `[label](destination "title")` whose label opens at `openingBracket`.
    static func inlineLink(in text: NSString, openingBracket: Int, limit: Int) -> InlineLink? {
        guard let labelEnd = labelEnd(in: text, openingBracket: openingBracket, limit: limit),
              labelEnd + 1 < limit, text.character(at: labelEnd + 1) == openingParenthesis,
              let destination = destinationRange(in: text, from: labelEnd + 2, limit: limit),
              let closing = closingParenthesis(after: NSMaxRange(destination), in: text, limit: limit) else { return nil }
        return InlineLink(range: NSRange(location: openingBracket, length: closing + 1 - openingBracket),
                          labelRange: NSRange(location: openingBracket + 1, length: labelEnd - openingBracket - 1),
                          destinationRange: destination)
    }

    /// The link reference definition `[label]: destination` whose label opens at `openingBracket`.
    static func definition(in text: NSString, openingBracket: Int) -> (labelRange: NSRange, destinationRange: NSRange)? {
        // A label is at most 999 characters long.
        let labelLimit = min(text.length, openingBracket + 1_001)
        guard let labelEnd = labelEnd(in: text, openingBracket: openingBracket, limit: labelLimit),
              labelEnd > openingBracket + 1, labelEnd + 1 < text.length, text.character(at: labelEnd + 1) == colon,
              let destination = destinationRange(in: text, from: labelEnd + 2, limit: text.length) else { return nil }
        return (NSRange(location: openingBracket + 1, length: labelEnd - openingBracket - 1), destination)
    }

    /// Whether the character at `location` is escaped by an odd number of backslashes.
    static func isEscaped(_ location: Int, in text: NSString) -> Bool {
        var index = location, count = 0
        while index > 0 && text.character(at: index - 1) == backslash { count += 1; index -= 1 }
        return count % 2 == 1
    }

    /// The `]` closing the label opened at `openingBracket`. Brackets nest, a backslash
    /// escapes the next character, and code spans are skipped whole, as CommonMark reads them.
    private static func labelEnd(in text: NSString, openingBracket: Int, limit: Int) -> Int? {
        var depth = 1
        var index = openingBracket + 1
        while index < limit {
            let character = text.character(at: index)
            switch character {
            case backslash:
                index += 2
                continue
            case backtick:
                let runLength = backtickRunLength(at: index, in: text, limit: limit)
                index = codeSpanEnd(openingRunAt: index, runLength: runLength, in: text, limit: limit) ?? index + runLength
                continue
            case leftSquareBracket:
                depth += 1
            case rightSquareBracket:
                depth -= 1
                if depth == 0 { return index }
            default:
                break
            }
            index += 1
        }
        return nil
    }

    static func backtickRunLength(at location: Int, in text: NSString, limit: Int) -> Int {
        var end = location
        while end < limit && text.character(at: end) == backtick { end += 1 }
        return end - location
    }

    /// The end of the code span opened by a run of `runLength` backticks: after the next run
    /// of exactly that length, or nil when there is none and the backticks are literal.
    static func codeSpanEnd(openingRunAt location: Int, runLength: Int, in text: NSString, limit: Int) -> Int? {
        var index = location + runLength
        while index < limit {
            guard text.character(at: index) == backtick else { index += 1; continue }
            let closingLength = backtickRunLength(at: index, in: text, limit: limit)
            if closingLength == runLength { return index + closingLength }
            index += closingLength
        }
        return nil
    }

    /// The destination starting after optional spaces and at most one line ending: `<…>`,
    /// or a run without spaces or control characters in which parentheses are balanced.
    private static func destinationRange(in text: NSString, from start: Int, limit: Int) -> NSRange? {
        var index = skippingSpaces(from: start, in: text, limit: limit)
        if index < limit, text.character(at: index) == carriageReturn { index += 1 }
        if index < limit, text.character(at: index) == lineFeed { index = skippingSpaces(from: index + 1, in: text, limit: limit) }
        guard index < limit else { return nil }
        if text.character(at: index) == lessThan {
            var end = index + 1
            while end < limit {
                let character = text.character(at: end)
                if character == backslash { end += 2; continue }
                if character == greaterThan { return NSRange(location: index, length: end + 1 - index) }
                if character == lessThan || character == lineFeed || character == carriageReturn { return nil }
                end += 1
            }
            return nil
        }
        var depth = 0
        var end = index
        while end < limit {
            let character = text.character(at: end)
            if character == backslash, end + 1 < limit, isASCIIPunctuation(text.character(at: end + 1)) { end += 2; continue }
            if character <= 0x20 || character == 0x7F { break }
            if character == openingParenthesis { depth += 1 }
            if character == closingParenthesis {
                if depth == 0 { break }
                depth -= 1
            }
            end += 1
        }
        guard depth == 0, end > index else { return nil }
        return NSRange(location: index, length: end - index)
    }

    /// The `)` ending an inline link after its destination and optional title.
    private static func closingParenthesis(after destinationEnd: Int, in text: NSString, limit: Int) -> Int? {
        var index = skippingSpaces(from: destinationEnd, in: text, limit: limit)
        guard index < limit else { return nil }
        let character = text.character(at: index)
        if character == closingParenthesis { return index }
        let titleClosing: unichar
        switch character {
        case 0x22: titleClosing = 0x22
        case 0x27: titleClosing = 0x27
        case openingParenthesis: titleClosing = closingParenthesis
        default: return nil
        }
        guard index > destinationEnd else { return nil }
        index += 1
        while index < limit {
            let titleCharacter = text.character(at: index)
            if titleCharacter == backslash { index += 2; continue }
            if titleCharacter == titleClosing { break }
            index += 1
        }
        index = skippingSpaces(from: index + 1, in: text, limit: limit)
        return index < limit && text.character(at: index) == closingParenthesis ? index : nil
    }

    private static func skippingSpaces(from start: Int, in text: NSString, limit: Int) -> Int {
        var index = start
        while index < limit, text.character(at: index) == 0x20 || text.character(at: index) == 0x09 { index += 1 }
        return index
    }

    private static func isASCIIPunctuation(_ character: unichar) -> Bool {
        (0x21...0x2F).contains(character) || (0x3A...0x40).contains(character) || (0x5B...0x60).contains(character) || (0x7B...0x7E).contains(character)
    }
}

/// Rewrites links after a file moves, in the style they were written in: a bare name stays
/// a bare name, a vault path stays a vault path, and a relative path is recomputed.
public enum LinkRewriter {
    private static let unreservedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/")
    /// Characters beyond ASCII that a destination may hold unencoded: CommonMark only
    /// excludes spaces and control characters, and Obsidian writes such names literally.
    private static let literalNonASCIICharacters = CharacterSet(charactersIn: "\u{80}"..."\u{10FFFF}")
        .subtracting(.whitespacesAndNewlines).subtracting(.controlCharacters).subtracting(.illegalCharacters)

    /// How a link's path was written.
    enum PathStyle: Equatable {
        /// `[[Note]]` or `[x](Note.md)`: a name found anywhere in the vault.
        case name
        /// `[[Folder/Note]]` or `[x](Folder/Note.md)`: a path from the vault's root.
        case vaultPath
        /// `[[../Note]]`, `[[./Note]]`, or a path that reached the target from the linking
        /// note's folder: a path from that folder.
        case relative(hasDotPrefix: Bool)
    }

    /// The path part (no `#subpath`) of a link to `target`, written the way `writtenPath`
    /// (already percent-decoded) was written to reach `previousTarget` from `previousSource`.
    ///
    /// - Parameters:
    ///   - source: Where the linking note is now.
    ///   - isNameUnique: Whether `target`'s file name is unique in the vault, so a bare name still finds it.
    public static func pathPart(linkingTo target: VaultPath, from source: VaultPath, writtenPath: String, isWiki: Bool,
                                previousTarget: VaultPath, previousSource: VaultPath, isNameUnique: Bool) -> String {
        let writtenExtension = (writtenPath as NSString).pathExtension.lowercased()
        let includesExtension = !writtenExtension.isEmpty && writtenExtension == previousTarget.fileExtension
        func finished(_ path: String) -> String {
            guard !includesExtension, DocumentKind(path: target) == .markdown else { return path }
            return (path as NSString).deletingPathExtension
        }
        switch style(of: writtenPath, isWiki: isWiki, previousTarget: previousTarget, previousSource: previousSource) {
        case .name:
            if let unchangedName = unchangedName(writtenPath, target: target, previousTarget: previousTarget, isNameUnique: isNameUnique) { return unchangedName }
            return isNameUnique ? finished(target.name) : finished(target.rawValue)
        case .vaultPath:
            return finished(target.rawValue)
        case .relative(let hasDotPrefix):
            let relativePath = finished(target.relativePath(from: source.parent))
            return hasDotPrefix && !relativePath.hasPrefix("../") ? "./" + relativePath : relativePath
        }
    }

    /// The written bare name, kept exactly (capitalization and Unicode form included), when
    /// it still finds the target: an alias, which lives in the target's properties and
    /// follows it anywhere, or the target's file name when the file kept its name and the
    /// name is still unique. A rename that changes only letter case changes the name, so
    /// the link takes the new spelling.
    private static func unchangedName(_ writtenPath: String, target: VaultPath, previousTarget: VaultPath, isNameUnique: Bool) -> String? {
        let writtenKey = comparisonKey(writtenPath)
        let previousNames = [previousTarget.name, (previousTarget.name as NSString).deletingPathExtension]
        guard previousNames.contains(where: { name in comparisonKey(name) == writtenKey }) else { return writtenPath }
        let hasKeptItsName = WikiLinkResolver.comparisonKey(target.name) == WikiLinkResolver.comparisonKey(previousTarget.name)
        return isNameUnique && hasKeptItsName ? writtenPath : nil
    }

    private static func comparisonKey(_ name: String) -> String {
        WikiLinkResolver.comparisonKey(name).lowercased()
    }

    static func style(of writtenPath: String, isWiki: Bool, previousTarget: VaultPath, previousSource: VaultPath) -> PathStyle {
        // `./` is kept when it was written; `../` comes from the new relative path itself.
        let hasDotPrefix = writtenPath.hasPrefix("./")
        if hasDotPrefix || writtenPath.hasPrefix("../") { return .relative(hasDotPrefix: hasDotPrefix) }
        let besideNote = WikiLinkResolver.fileNameVariants(for: writtenPath).compactMap { variant in try? previousSource.parent.appending(variant) }
        let reachedBesideNote = besideNote.contains(previousTarget)
        // A Markdown link is read beside the note first, as Obsidian's relative format writes
        // it; one that reached its target from elsewhere was written in the shortest (a bare
        // name) or absolute (a vault path) format, which Graphite also writes.
        if !isWiki && reachedBesideNote { return .relative(hasDotPrefix: false) }
        guard writtenPath.contains("/") else { return .name }
        // A Wikilink path without a dot prefix is tried beside the note first, then from the root.
        if isWiki, !previousSource.parent.rawValue.isEmpty, reachedBesideNote { return .relative(hasDotPrefix: false) }
        return .vaultPath
    }

    /// The link's text with its path replaced; its `!`, `#subpath`, alias, label and title
    /// stay. A link reported inside its quoted YAML value (see `NoteLinkScanner`) keeps its
    /// quotes, and the new path is escaped for them.
    public static func replacingPath(inLinkText linkText: String, isWiki: Bool, newPathPart: String) -> String? {
        let text = linkText as NSString
        let enclosingQuote = YAMLQuotedValue.enclosingQuote(of: text)
        let escapedForValue = { (inserted: String) in enclosingQuote.map { quote in YAMLQuotedValue.escaped(inserted, quote: quote) } ?? inserted }
        if isWiki {
            let opening = text.range(of: "[[")
            let closing = text.range(of: "]]", options: .backwards)
            guard opening.location != NSNotFound, closing.location != NSNotFound, closing.location >= NSMaxRange(opening) else { return nil }
            let content = text.substring(with: NSRange(location: NSMaxRange(opening), length: closing.location - NSMaxRange(opening)))
            let aliasSeparator = content.firstIndex(of: "|")
            let targetText = aliasSeparator.map { separator in String(content[..<separator]) } ?? content
            let alias = aliasSeparator.map { separator in String(content[separator...]) } ?? ""
            let subpathSeparator = targetText.firstIndex(of: "#")
            var subpath = subpathSeparator.map { separator in String(targetText[separator...]) } ?? ""
            let pathText = subpathSeparator.map { separator in String(targetText[..<separator]) } ?? targetText
            // In a table, `[[Note\|alias]]` escapes the pipe; the backslash stays with the path.
            var trailingEscape = ""
            if subpath.isEmpty, pathText.hasSuffix("\\") { trailingEscape = "\\" }
            if subpath.hasSuffix("\\") && alias.hasPrefix("|") { subpath = String(subpath.dropLast()); trailingEscape = "\\" }
            return text.substring(to: opening.location) + "[[" + escapedForValue(newPathPart) + subpath + trailingEscape + alias + "]]"
                + text.substring(from: NSMaxRange(closing))
        }
        guard let destinationRange = MarkdownLinkSyntax.destinationRange(inLinkText: text) else { return nil }
        let destination = text.substring(with: destinationRange)
        let isAngleBracketed = destination.hasPrefix("<") && destination.hasSuffix(">")
        let bareDestination = isAngleBracketed ? String(destination.dropFirst().dropLast()) : destination
        let fragment = bareDestination.firstIndex(of: "#").map { separator in String(bareDestination[separator...]) } ?? ""
        // The fragment is kept exactly as written, already escaped for any enclosing quotes.
        let newDestination: String
        if isAngleBracketed {
            newDestination = "<" + escapedForValue(newPathPart) + fragment + ">"
        } else {
            // Letters beyond ASCII stay as they were written: literal (`Café.md`) or encoded.
            let writesNonASCIILiterally = bareDestination.unicodeScalars.contains { scalar in !scalar.isASCII }
            newDestination = escapedForValue(percentEncoded(newPathPart, keepingNonASCIILiterally: writesNonASCIILiterally)) + fragment
        }
        return text.replacingCharacters(in: destinationRange, with: newDestination)
    }

    /// `path` with every character a bare destination cannot hold as written percent-encoded
    /// in UTF-8. Foundation's `addingPercentEncoding` always encodes characters beyond ASCII,
    /// so they are kept here one Unicode scalar at a time.
    private static func percentEncoded(_ path: String, keepingNonASCIILiterally: Bool) -> String {
        var encoded = ""
        for scalar in path.unicodeScalars {
            if unreservedCharacters.contains(scalar) || (keepingNonASCIILiterally && literalNonASCIICharacters.contains(scalar)) {
                encoded.unicodeScalars.append(scalar)
            } else {
                for byte in String(scalar).utf8 { encoded += String(format: "%%%02X", byte) }
            }
        }
        return encoded
    }

    /// The path part of a written link target, decoded as it is resolved.
    public static func writtenPath(of link: NoteLink) -> String {
        let path = WikiLinkResolver.pathPart(link.target)
        return link.isWiki ? path : (path.removingPercentEncoding ?? path)
    }

    /// Applies replacements, each for one link's whole text, to `text`.
    ///
    /// Link ranges can nest, as an image inside a link's label does (`[![logo](logo.png)](Note.md)`).
    /// Each replacement was built from the original text, so a nested one is applied inside
    /// the replacement of the link around it, at the same offset, and only when that part of
    /// the outer replacement is still the original text. A range that crosses another's end
    /// cannot be merged and is left out rather than spliced at a stale offset.
    public static func applying(_ replacements: [(range: NSRange, text: String)], to text: String) -> String {
        let original = text as NSString
        let ordered = replacements.map { replacement in LinkReplacement(range: replacement.range, text: replacement.text) }
            .filter { replacement in NSMaxRange(replacement.range) <= original.length }
            .sorted { leftReplacement, rightReplacement in
                leftReplacement.range.location != rightReplacement.range.location
                    ? leftReplacement.range.location < rightReplacement.range.location
                    : leftReplacement.range.length > rightReplacement.range.length
            }
        let output = NSMutableString(string: text)
        for group in LinkReplacementGroup.groups(from: ordered[...]).reversed() {
            output.replaceCharacters(in: group.range, with: group.mergedText(in: original))
        }
        return output as String
    }
}

private struct LinkReplacement {
    let range: NSRange
    let text: String
}

/// A replacement and the replacements of links nested inside its range.
private struct LinkReplacementGroup {
    let range: NSRange
    let text: String
    let nested: [LinkReplacementGroup]

    /// Groups replacements ordered by location, outer ranges before the ranges they contain.
    static func groups(from ordered: ArraySlice<LinkReplacement>) -> [LinkReplacementGroup] {
        var foundGroups: [LinkReplacementGroup] = []
        var index = ordered.startIndex
        while index < ordered.endIndex {
            let outer = ordered[index]
            index += 1
            var contained: [LinkReplacement] = []
            while index < ordered.endIndex, ordered[index].range.location < NSMaxRange(outer.range) {
                if NSMaxRange(ordered[index].range) <= NSMaxRange(outer.range) { contained.append(ordered[index]) }
                index += 1
            }
            foundGroups.append(LinkReplacementGroup(range: outer.range, text: outer.text, nested: groups(from: contained[...])))
        }
        return foundGroups
    }

    func mergedText(in original: NSString) -> String {
        let merged = NSMutableString(string: text)
        // Last first, so earlier offsets inside the outer text stay valid.
        for inner in nested.reversed() {
            let offsetRange = NSRange(location: inner.range.location - range.location, length: inner.range.length)
            guard NSMaxRange(offsetRange) <= merged.length,
                  merged.substring(with: offsetRange) == original.substring(with: inner.range) else { continue }
            merged.replaceCharacters(in: offsetRange, with: inner.mergedText(in: original))
        }
        return merged as String
    }
}
