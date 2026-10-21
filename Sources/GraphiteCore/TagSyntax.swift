import Foundation

/// Obsidian's tag rules: letters, numbers, `_`, `-`, `/` for nesting, and symbols such
/// as emoji, with at least one character that is not a number (`#2026-exam` is a tag,
/// `#1984` is not). A tag starts at a `#` that does not continue a word or a path.
public enum TagSyntax {
    /// Capture group 1 is the tag without its `#`.
    public static let pattern = TagSyntaxPattern.pattern.compiled()

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

/// The constant pattern of `TagSyntax`; `StaticPatternTests` compiles it.
enum TagSyntaxPattern: String, StaticPatternSet {
    /// A `#` that does not continue a word or a path, then tag characters, not all of them
    /// numbers. The tag character class is written out twice: letters, numbers, marks and
    /// symbols such as emoji, `_`, `/` and `-`, plus what emoji need: their joiners and
    /// variation selectors, the skin-tone modifiers (U+1F3FB to U+1F3FF, which are modifier
    /// symbols like `^`, so not the whole category) and the tag characters of subdivision
    /// flags (U+E0020 to U+E007F).
    case pattern = #"(?<![\p{L}\p{N}_/&#])#(?!\p{N}+(?![\p{L}\p{N}\p{M}\p{So}_/\-\x{200D}\x{FE0F}\x{1F3FB}-\x{1F3FF}\x{E0020}-\x{E007F}]))([\p{L}\p{N}\p{M}\p{So}_/\-\x{200D}\x{FE0F}\x{1F3FB}-\x{1F3FF}\x{E0020}-\x{E007F}]+)"#
}
