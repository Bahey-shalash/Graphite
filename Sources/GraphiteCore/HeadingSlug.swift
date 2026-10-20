import Foundation

/// The slugs GitHub and most Markdown editors give headings, which tables of contents
/// written outside Obsidian link to (`[Setup](#2-setup)`). Obsidian links a heading by its
/// text (`NotePreviewDocument.anchor(forHeading:)`); a slug is tried when no heading's
/// anchor matches.
public enum HeadingSlug {
    /// The heading's slug: lowercase, punctuation other than `-` and `_` dropped and each
    /// space a hyphen, so `2. Setup — How It Works` is `2-setup--how-it-works`.
    public static func slug(forHeading text: String) -> String {
        var slug = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .letterNumber, .otherNumber, .connectorPunctuation:
                slug.append(scalar)
            case .spaceSeparator where scalar == " ":
                slug.append("-")
            default:
                if scalar == "-" { slug.append(scalar) }
            }
        }
        return String(slug)
    }

    /// The position in `headingAnchors` (the note's heading anchors in order) of the heading
    /// whose slug `fragment` is. Repeated headings are numbered `-1`, `-2` as GitHub numbers them.
    public static func position(ofSlug fragment: String, amongHeadingAnchors headingAnchors: [String]) -> Int? {
        let wantedSlug = fragment.lowercased()
        guard !wantedSlug.isEmpty, !wantedSlug.contains(where: \.isWhitespace) else { return nil }
        var repeatCountsBySlug: [String: Int] = [:]
        for (position, headingAnchor) in headingAnchors.enumerated() {
            let baseSlug = slug(forHeading: headingAnchor)
            var headingSlug = baseSlug
            while repeatCountsBySlug[headingSlug] != nil {
                let repeatCount = repeatCountsBySlug[baseSlug, default: 0] + 1
                repeatCountsBySlug[baseSlug] = repeatCount
                headingSlug = baseSlug + "-" + String(repeatCount)
            }
            repeatCountsBySlug[headingSlug] = 0
            if headingSlug == wantedSlug { return position }
        }
        return nil
    }
}
