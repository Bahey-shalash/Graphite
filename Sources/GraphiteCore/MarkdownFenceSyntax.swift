import Foundation

/// CommonMark code fences, read one line at a time: a run of three or more backticks or
/// tildes opens one, and only a line of the same character, at least as long, closes it.
/// Which lines a fence holds is the caller's walk (`CodeFenceTracker`, `ListItemContainers`).
public enum MarkdownFenceSyntax {
    /// The fence that `trimmedLine` opens, and the info text after it, or nil.
    public static func opening(_ trimmedLine: String) -> (fence: String, info: String)? {
        guard let fenceCharacter = trimmedLine.first, fenceCharacter == "`" || fenceCharacter == "~" else { return nil }
        let fence = String(trimmedLine.prefix { character in character == fenceCharacter })
        guard fence.count >= 3 else { return nil }
        let info = trimmedLine.dropFirst(fence.count).trimmingCharacters(in: .whitespaces)
        // A backtick fence's info text cannot contain a backtick.
        guard fenceCharacter == "~" || !info.contains("`") else { return nil }
        return (fence, info)
    }

    public static func closes(_ fence: String, _ trimmedLine: String) -> Bool {
        guard let fenceCharacter = fence.first else { return false }
        return trimmedLine.count >= fence.count && trimmedLine.allSatisfy { character in character == fenceCharacter }
    }

    /// Columns a fence may be indented past the content column of its container: the
    /// list item holding it, or column 0 outside lists. Indented further, a fence line
    /// is indented code or paragraph text.
    public static let maximumIndentation = 3

    /// The language of a fenced code block as Obsidian gives it to code block processors:
    /// the first word of the fence's info text, so ```` ```dataview table ```` is `dataview`.
    public static func language(ofInfo info: String) -> String {
        String(info.prefix { character in !character.isWhitespace })
    }
}
