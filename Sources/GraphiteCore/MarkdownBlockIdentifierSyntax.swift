import Foundation

/// Obsidian block identifiers, read one line at a time: `^id` at the end of a paragraph's
/// or list item's last line, after a space or tab, or alone on a line of its own after the
/// other blocks. An identifier is letters, digits and `-`.
enum MarkdownBlockIdentifierSyntax {
    private static let trailingIdentifierPattern = MarkdownBlockIdentifierSyntaxPattern.trailingIdentifier.compiled()
    private static let identifierLinePattern = MarkdownBlockIdentifierSyntaxPattern.identifierLine.compiled()

    /// The `^id` that ends `line`: the identifier, and the UTF-16 range of its marker in the
    /// line, the space or tab before it and any after it included.
    static func trailingIdentifier(in line: String) -> (identifier: String, markerRange: NSRange)? {
        let source = line as NSString
        guard let match = trailingIdentifierPattern.firstMatch(in: line, range: NSRange(location: 0, length: source.length)) else { return nil }
        return (source.substring(with: match.range(at: 1)), match.range)
    }

    /// The identifier of a line that holds only `^id`, indented or not; nil for any other line.
    static func identifierOnOwnLine(_ line: String) -> String? {
        guard let match = identifierLinePattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return nil }
        return (line as NSString).substring(with: match.range(at: 1))
    }
}

/// The constant patterns of `MarkdownBlockIdentifierSyntax`; `StaticPatternTests` compiles every case.
enum MarkdownBlockIdentifierSyntaxPattern: String, StaticPatternSet {
    case trailingIdentifier = #"(?:^|[ \t])\^([A-Za-z0-9-]+)[ \t]*$"#
    case identifierLine = #"^[ \t]*\^([A-Za-z0-9-]+)[ \t]*$"#
}
