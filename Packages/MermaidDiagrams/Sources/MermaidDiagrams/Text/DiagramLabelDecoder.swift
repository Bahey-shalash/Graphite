/// Turns the text written for a node, an edge or a group into the plain lines that are drawn: `<br>` and line breaks
/// end lines, other HTML tags are dropped, Mermaid's entity codes (`#quot;`, `#9829;`) and HTML's (`&lt;`) become
/// their characters, a Markdown string loses its emphasis markers, and runs of spaces become one.
enum DiagramLabelDecoder {
    /// How the text was written: plain or quoted, or as a Markdown string (`"`…`"`).
    enum Form {
        case plain
        case markdown
    }

    static func label(from rawText: String, form: Form) -> DiagramLabel {
        var lines: [String] = []
        for writtenLine in lineBreakSeparated(rawText) {
            var line = withoutTags(writtenLine)
            if form == .markdown { line = withoutEmphasisMarkers(line) }
            lines.append(collapsingSpaces(decodingEntities(line)))
        }
        return DiagramLabel(lines: lines)
    }

    /// The text split at `<br>`, `<br/>`, `<br />` (in any case) and at line breaks.
    private static func lineBreakSeparated(_ text: String) -> [String] {
        var lines: [String] = []
        var current = ""
        var scalars = Substring(text).unicodeScalars[...]
        while let scalar = scalars.first {
            if scalar == "\n" {
                lines.append(current)
                current = ""
                scalars = scalars.dropFirst()
            } else if scalar == "<", let length = lineBreakTagLength(in: scalars) {
                lines.append(current)
                current = ""
                scalars = scalars.dropFirst(length)
            } else {
                current.unicodeScalars.append(scalar)
                scalars = scalars.dropFirst()
            }
        }
        lines.append(current)
        return lines
    }

    /// The length of a `<br>` tag at the start of `scalars`, or nil when it is not one.
    private static func lineBreakTagLength(in scalars: Substring.UnicodeScalarView.SubSequence) -> Int? {
        let lowercased = String(String.UnicodeScalarView(scalars.prefix(6))).lowercased()
        for tag in ["<br>", "<br/>", "<br />"] where lowercased.hasPrefix(tag) { return tag.unicodeScalars.count }
        return nil
    }

    /// The line without HTML tags: a `<` followed by a letter or `/` up to the next `>`. A `<` that starts no tag, as in
    /// `a < b`, stays.
    private static func withoutTags(_ line: String) -> String {
        guard line.contains("<") else { return line }
        var result = String.UnicodeScalarView()
        var scalars = line.unicodeScalars[...]
        while let scalar = scalars.first {
            if scalar == "<", let next = scalars.dropFirst().first, next == "/" || next.properties.isAlphabetic,
               let closing = scalars.firstIndex(of: ">") {
                scalars = scalars[scalars.index(after: closing)...]
                continue
            }
            result.append(scalar)
            scalars = scalars.dropFirst()
        }
        return String(result)
    }

    /// The line without `*` and without the `_` that open or close emphasis; an underscore between two letters or
    /// digits, as in `snake_case`, is text.
    private static func withoutEmphasisMarkers(_ line: String) -> String {
        let characters = Array(line)
        var result = ""
        for (index, character) in characters.enumerated() {
            if character == "*" { continue }
            if character == "_" {
                let isBetweenWordCharacters = index > 0 && index + 1 < characters.count
                    && isWordCharacter(characters[index - 1]) && isWordCharacter(characters[index + 1])
                if !isBetweenWordCharacters { continue }
            }
            result.append(character)
        }
        return result
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    private static func collapsingSpaces(_ line: String) -> String {
        line.split(whereSeparator: { character in character == " " || character == "\t" }).joined(separator: " ")
    }

    /// The line with each entity code replaced by its character: `#name;` and `#123;` (Mermaid's), `&name;`, `&#123;`
    /// and `&#x7B;` (HTML's). An unknown name, or a number that is no character, stays as written.
    static func decodingEntities(_ line: String) -> String {
        guard line.contains(";") else { return line }
        var result = String.UnicodeScalarView()
        var scalars = line.unicodeScalars[...]
        while let scalar = scalars.first {
            if scalar == "#" || scalar == "&", let (decoded, length) = entity(at: scalars) {
                result.append(decoded)
                scalars = scalars.dropFirst(length)
                continue
            }
            result.append(scalar)
            scalars = scalars.dropFirst()
        }
        return String(result)
    }

    /// The character an entity code at the start of `scalars` stands for, and the code's length.
    private static func entity(at scalars: Substring.UnicodeScalarView.SubSequence) -> (Unicode.Scalar, Int)? {
        let maximumCodeLength = 12
        guard let semicolon = scalars.prefix(maximumCodeLength).firstIndex(of: ";") else { return nil }
        let body = String(String.UnicodeScalarView(scalars[scalars.index(after: scalars.startIndex)..<semicolon]))
        let length = scalars.distance(from: scalars.startIndex, to: semicolon) + 1
        let decoded: Unicode.Scalar?
        if scalars.first == "&" {
            decoded = body.hasPrefix("#") ? numberedCharacter(body.dropFirst()) : namedEntities[body]
        } else {
            decoded = numberedCharacter(Substring(body)) ?? namedEntities[body]
        }
        return decoded.map { character in (character, length) }
    }

    /// The character a decimal number, or a hexadecimal one after `x`, stands for.
    private static func numberedCharacter(_ digits: Substring) -> Unicode.Scalar? {
        if let first = digits.first, first == "x" || first == "X" {
            return UInt32(digits.dropFirst(), radix: 16).flatMap(Unicode.Scalar.init)
        }
        return UInt32(digits).flatMap(Unicode.Scalar.init)
    }

    /// The named entities diagrams use: Mermaid's examples and the common HTML ones.
    private static let namedEntities: [String: Unicode.Scalar] = [
        "quot": "\"", "amp": "&", "lt": "<", "gt": ">", "apos": "'", "nbsp": "\u{00A0}", "copy": "©", "reg": "®",
        "deg": "°", "hellip": "…", "mdash": "—", "ndash": "–", "times": "×", "divide": "÷", "plusmn": "±",
        "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "harr": "↔", "hearts": "♥", "check": "✓", "infin": "∞",
        "ne": "≠", "le": "≤", "ge": "≥", "middot": "·", "bull": "•", "laquo": "«", "raquo": "»", "euro": "€",
    ]
}
