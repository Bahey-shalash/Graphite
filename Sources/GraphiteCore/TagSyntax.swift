import Foundation

/// Obsidian's tag rules: letters, numbers, `_`, `-`, `/` for nesting, and symbols such
/// as emoji, with at least one character that is not a number (`#2026-exam` is a tag,
/// `#1984` is not). A tag starts at a `#` that does not continue a word or a path.
public enum TagSyntax {
    /// Emoji need their joiners and variation selectors, the skin-tone modifiers
    /// (U+1F3FB to U+1F3FF, which are modifier symbols like `^`, so not the whole
    /// category) and the tag characters of subdivision flags (U+E0020 to U+E007F).
    private static let tagCharacter = "[\\p{L}\\p{N}\\p{M}\\p{So}_/\\-\\x{200D}\\x{FE0F}\\x{1F3FB}-\\x{1F3FF}\\x{E0020}-\\x{E007F}]"
    /// Capture group 1 is the tag without its `#`.
    public static let pattern: NSRegularExpression = {
        // A fixed pattern, covered by tests, so compilation cannot fail at run time.
        try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_/&#])#(?!\\p{N}+(?!\(tagCharacter)))(\(tagCharacter)+)")
    }()

    /// Whether `name` (without `#`) is a whole valid tag.
    public static func isValidTag(_ name: String) -> Bool {
        let text = "#" + name
        guard let match = pattern.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return false }
        return match.range.length == (text as NSString).length
    }

    /// Whether a tag search for `searchedTag` finds `tag`: the tag itself or any tag nested under it.
    public static func tag(_ tag: String, isWithin searchedTag: String) -> Bool {
        let tagKey = tag.lowercased(), searchedKey = searchedTag.lowercased()
        return tagKey == searchedKey || tagKey.hasPrefix(searchedKey + "/")
    }
}
