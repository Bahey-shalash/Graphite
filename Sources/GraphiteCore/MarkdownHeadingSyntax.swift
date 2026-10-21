import Foundation

/// ATX and setext headings, read one line at a time. Whether a line is in code, math or
/// frontmatter is the caller's block walk; these functions classify the line as written.
public enum MarkdownHeadingSyntax {
    private static let atxMarker = MarkdownHeadingSyntaxPattern.atxMarker.compiled()
    private static let titledAtxHeading = MarkdownHeadingSyntaxPattern.titledAtxHeading.compiled()

    /// The heading level of a line, or nil when it is not an ATX heading. A `#` run alone on
    /// its line is an empty heading, as in CommonMark.
    public static func level(of line: String) -> Int? {
        let source = line as NSString
        return atxMarker(in: source, range: NSRange(location: 0, length: source.length))?.hashes.length
    }

    /// The UTF-16 length of a line's ATX marker: its indentation, `#` run and the spaces
    /// after it; 0 when the line is no ATX heading.
    static func markerLength(of line: String) -> Int {
        let source = line as NSString
        return atxMarker(in: source, range: NSRange(location: 0, length: source.length)).map { marker in NSMaxRange(marker.spacing) } ?? 0
    }

    /// `level(of:)` for the part `range` of `line`, which holds no line ending, read without
    /// copying it: the ranges of the `#` run and of the spaces after it, which are empty when
    /// the run ends the line; nil when the part is no ATX heading.
    static func atxMarker(in line: NSString, range: NSRange) -> (hashes: NSRange, spacing: NSRange)? {
        guard let match = atxMarker.firstMatch(in: line as String, range: range) else { return nil }
        let hashes = match.range(at: 2)
        return (hashes, NSRange(location: NSMaxRange(hashes), length: NSMaxRange(match.range) - NSMaxRange(hashes)))
    }

    /// An ATX heading that has text, with its level and its text without the closing
    /// sequence, as the outline and the reading view list headings. As in CommonMark,
    /// trailing `#`s are a closing sequence only after a space, so `## Learning C#` keeps
    /// its `#`. A trailing carriage return is not part of the text.
    static func titledHeading(in line: String) -> (level: Int, text: String)? {
        guard line.utf8.contains(UInt8(ascii: "#")) else { return nil }
        let cleanLine = line.hasSuffix("\r") ? String(line.dropLast()) : line
        guard let match = titledAtxHeading.firstMatch(in: cleanLine, range: NSRange(location: 0, length: (cleanLine as NSString).length)) else { return nil }
        let source = cleanLine as NSString
        return (source.substring(with: match.range(at: 1)).count, source.substring(with: match.range(at: 2)))
    }

    /// The level of the setext heading that `line` is the text of when `nextLine` underlines
    /// it, or nil. The one rule for setext headings: the editor's styling
    /// (`MarkdownStyleScanner.spans`), the outline, heading links, section embeds and reading
    /// blocks (`NotePreviewDocument`), folding (`NoteFolding`) and Live Preview's rules
    /// (`LivePreviewBlockScanner`) read it here; the first and folding look at the next
    /// line's `setextUnderlineLevel` first, so most lines skip the paragraph test.
    static func setextHeadingLevel(ofLine line: String, nextLine: String?) -> Int? {
        guard let nextLine, let level = setextUnderlineLevel(nextLine), isParagraphText(line) else { return nil }
        return level
    }

    /// The level of a setext heading `line` underlines (`===` is 1, `---` is 2), or nil.
    static func setextUnderlineLevel(_ line: String) -> Int? {
        guard let firstVisible = line.first(where: { character in character != " " }), firstVisible == "=" || firstVisible == "-",
              line.prefix(while: { character in character == " " }).count < 4 else { return nil }
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let marker = trimmedLine.first, marker == "=" || marker == "-", trimmedLine.allSatisfy({ character in character == marker }) else { return nil }
        return marker == "=" ? 1 : 2
    }

    /// Whether `line`, outside code, math and frontmatter, is ordinary paragraph text,
    /// which a following `---` or `===` turns into a setext heading. After a heading, a
    /// list item, a quote or another block, `---` is a horizontal rule instead.
    static func isParagraphText(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix(">"), !trimmedLine.hasPrefix("$$"), !trimmedLine.hasSuffix("$$"),
              line.prefix(while: { character in character == " " }).count < 4 else { return false }
        let isFenceSyntax = MarkdownFenceSyntax.opening(trimmedLine) != nil
            || (trimmedLine.count >= 3 && trimmedLine.allSatisfy { character in character == "`" || character == "~" })
        let isBlockSyntax = isFenceSyntax || setextUnderlineLevel(trimmedLine) != nil || level(of: trimmedLine) != nil
            || MarkdownListSyntax.isThematicBreak(trimmedLine) || MarkdownListSyntax.isListItem(trimmedLine)
        return !isBlockSyntax
    }
}

/// The constant patterns of `MarkdownHeadingSyntax`; `StaticPatternTests` compiles every case.
enum MarkdownHeadingSyntaxPattern: String, StaticPatternSet {
    case atxMarker = #"^( {0,3})(#{1,6})(?:[ \t]+|$)"#
    case titledAtxHeading = #"^ {0,3}(#{1,6})[ \t]+(.+?)(?:[ \t]+#+)?[ \t]*$"#
}
