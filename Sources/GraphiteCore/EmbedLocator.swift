import Foundation

public enum EmbedLocator {
    private static let wikiEmbedPattern = try? NSRegularExpression(pattern: "!\\[\\[([^\\]\\n]+)\\]\\]")
    /// The parentheses hold a `<…>` destination and an optional title, or text with at
    /// most one balanced `(…)` in it, which is how a `(title)` is written.
    private static let markdownEmbedPattern = try? NSRegularExpression(pattern: "!\\[([^\\]\\n]*)\\]\\((<[^<>\\n]*>[^)\\n]*|[^()\\n]*(?:\\([^()\\n]*\\)[^()\\n]*)?)\\)")

    /// The embed whose source text contains `location` (or ends exactly there).
    public static func embed(at location: Int, in text: NSString) -> EmbedReference? {
        guard location >= 0, location <= text.length else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
        let line = text.substring(with: lineRange)
        let localLocation = location - lineRange.location
        func contains(_ range: NSRange) -> Bool { localLocation >= range.location && localLocation <= NSMaxRange(range) }
        let lineLength = (line as NSString).length
        if let match = wikiEmbedPattern?.matches(in: line, range: NSRange(location: 0, length: lineLength)).first(where: { match in contains(match.range) }) {
            let content = (line as NSString).substring(with: match.range(at: 1))
            let parts = content.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            // Only the `\` of a table's escaped `\|` goes: other backslashes are the name's.
            var target = parts[0]
            if parts.count > 1, target.hasSuffix("\\") { target.removeLast() }
            return EmbedReference(target: target, isWiki: true, displaySize: parts.count > 1 ? EmbedDisplaySize.parse(label: parts[1]) : nil,
                                  range: NSRange(location: lineRange.location + match.range.location, length: match.range.length))
        }
        if let match = markdownEmbedPattern?.matches(in: line, range: NSRange(location: 0, length: lineLength)).first(where: { match in contains(match.range) }) {
            let label = (line as NSString).substring(with: match.range(at: 1))
            let destination = linkDestination(in: (line as NSString).substring(with: match.range(at: 2)))
            guard !destination.isEmpty else { return nil }
            return EmbedReference(target: destination, isWiki: false, displaySize: EmbedDisplaySize.parse(label: label),
                                  range: NSRange(location: lineRange.location + match.range.location, length: match.range.length))
        }
        return nil
    }

    /// The destination of a Markdown image, by CommonMark's rules: the text inside `<…>`,
    /// or else the text up to the first whitespace. A `"title"`, `'title'` or `(title)`
    /// after it is not part of the destination, so `![a](a.png "Title")` embeds `a.png`.
    static func linkDestination(in parenthesizedText: String) -> String {
        let trimmedText = parenthesizedText.trimmingCharacters(in: .whitespaces)
        if trimmedText.hasPrefix("<"), let closingIndex = trimmedText.firstIndex(of: ">") {
            return String(trimmedText[trimmedText.index(after: trimmedText.startIndex)..<closingIndex])
        }
        return trimmedText.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
    }
}
