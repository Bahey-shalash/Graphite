import Foundation

public enum FrontmatterLocator {
    private static let pattern = FrontmatterLocatorPattern.pattern.compiled()

    /// UTF-16 length of the leading YAML frontmatter block, or 0 when there is none.
    public static func length(in text: NSString) -> Int {
        pattern.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length))?.range.length ?? 0
    }
}

/// The constant patterns of `FrontmatterLocator`; `StaticPatternTests` compiles every case.
enum FrontmatterLocatorPattern: String, StaticPatternSet {
    case pattern = #"\A---\r?\n(?:[\s\S]*?\r?\n)?(?:---|\.\.\.)[ \t]*(?:\r?\n|$)"#
}
