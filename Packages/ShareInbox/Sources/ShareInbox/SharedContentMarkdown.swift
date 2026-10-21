import Foundation

/// The Markdown a shared item's text is made of, as Obsidian's share sheet writes it: shared
/// text as it came, a shared web page as a link titled with the page's title.
public enum SharedContentMarkdown {
    /// The longest title suggested from shared text, in characters.
    public static let maximumSuggestedTitleCharacters = 60

    /// `[Title](address)`. Brackets and backslashes in the title are escaped, and an address
    /// with parentheses or spaces is written in angle brackets so the link stays one link.
    public static func link(title: String?, address: URL) -> String {
        let addressText = address.absoluteString
        let trimmedTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmedTitle.isEmpty ? (address.host() ?? addressText) : trimmedTitle
        let escapedLabel = label.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "\n", with: " ")
        let needsAngleBrackets = addressText.contains { character in character == "(" || character == ")" || character == " " }
        return "[" + escapedLabel + "](" + (needsAngleBrackets ? "<" + addressText + ">" : addressText) + ")"
    }

    /// What tells two shared addresses of one page apart: Safari hands over the same page
    /// twice, once with a trailing slash, so the slash and the host's capitals do not count.
    public static func pageIdentity(of address: URL) -> String {
        var text = address.absoluteString
        if var components = URLComponents(url: address, resolvingAgainstBaseURL: false) {
            let lowercasedHost = components.host?.lowercased()
            components.host = lowercasedHost
            components.fragment = nil
            text = components.string ?? text
        }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    /// The parts of a share (texts, links) as one note text, a blank line between parts.
    public static func combinedText(_ parts: [String]) -> String {
        parts.map { part in part.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { part in !part.isEmpty }
            .joined(separator: "\n\n")
    }

    /// A title for the new note: the first candidate (a page's title, the text's first line,
    /// a file's name) that has a line of text, cut at a word to at most
    /// `maximumSuggestedTitleCharacters`. Nil when none has one.
    public static func suggestedTitle(from candidates: [String?]) -> String? {
        for candidate in candidates {
            let firstLine = (candidate ?? "").split(whereSeparator: \.isNewline).lazy
                .map { line in line.trimmingCharacters(in: .whitespaces) }
                .first { line in !line.isEmpty }
            guard let firstLine else { continue }
            return shortened(firstLine.trimmingCharacters(in: CharacterSet(charactersIn: "#>-*").union(.whitespaces)))
        }
        return nil
    }

    private static func shortened(_ line: String) -> String {
        guard line.count > maximumSuggestedTitleCharacters else { return line }
        let prefix = String(line.prefix(maximumSuggestedTitleCharacters))
        guard let lastSpace = prefix.lastIndex(of: " "), lastSpace > prefix.startIndex else { return prefix }
        return String(prefix[..<lastSpace])
    }
}
