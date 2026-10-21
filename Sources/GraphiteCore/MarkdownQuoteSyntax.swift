import Foundation

/// Block quote markers and callout headers, read one line at a time.
public enum MarkdownQuoteSyntax {
    private static let calloutHeaderPattern = MarkdownQuoteSyntaxPattern.calloutHeader.compiled()

    /// The line after up to `maximumDepth` `>` quote markers, as CommonMark reads them: each
    /// with up to three spaces before it and one optional space or tab after it. Returns how
    /// many there were and the rest of the line as written.
    static func markersRemoved(from line: String, maximumDepth: Int = .max) -> (depth: Int, content: String) {
        let (depth, content) = markersRemoved(from: Substring(line), maximumDepth: maximumDepth)
        return (depth, String(content))
    }

    /// `markersRemoved(from:maximumDepth:)` without copying the line, for walks that read
    /// every line of a note.
    static func markersRemoved(from line: Substring, maximumDepth: Int = .max) -> (depth: Int, content: Substring) {
        // Most lines start with neither a space nor a marker.
        guard let firstByte = line.utf8.first, firstByte == UInt8(ascii: " ") || firstByte == UInt8(ascii: ">") else { return (0, line) }
        var remaining = line
        var depth = 0
        while depth < maximumDepth {
            let indentation = remaining.prefix { character in character == " " }
            guard indentation.count <= 3, remaining.dropFirst(indentation.count).first == ">" else { break }
            remaining = remaining.dropFirst(indentation.count + 1)
            if remaining.first == " " || remaining.first == "\t" { remaining = remaining.dropFirst() }
            depth += 1
        }
        return (depth, remaining)
    }

    /// Up to `maximumDepth` leading quote markers and the trimmed text after them, as the
    /// editor's block walk reads a line for fences and `$$`: the line is trimmed first, so
    /// a marker may follow any indentation, and every space after a marker is skipped.
    static func markersAndTrimmedContent(of line: String, maximumDepth: Int) -> (depth: Int, content: String) {
        var remainder = Substring(line.trimmingCharacters(in: .whitespacesAndNewlines))
        var depth = 0
        while depth < maximumDepth && remainder.hasPrefix(">") {
            remainder = remainder.dropFirst().drop { character in character == " " }
            depth += 1
        }
        return (depth, String(remainder))
    }

    /// The callout that `line` opens (`> [!type]` with an optional `-` or `+` and title): its
    /// type lowercased, its title (the type, capitalized, when none is written) and whether
    /// it starts folded.
    static func calloutHeader(in line: String) -> (type: String, title: String, folding: CalloutFolding)? {
        guard let match = calloutHeaderPattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return nil }
        let source = line as NSString
        let type = source.substring(with: match.range(at: 1)).lowercased()
        let foldMarker = source.substring(with: match.range(at: 2))
        let writtenTitle = source.substring(with: match.range(at: 3))
        let title = writtenTitle.isEmpty ? type.prefix(1).uppercased() + type.dropFirst() : writtenTitle
        return (type, title, foldMarker == "-" ? .collapsed : foldMarker == "+" ? .expanded : .notFoldable)
    }

    /// Whether `line` opens a callout, without reading its type and title.
    static func isCalloutHeader(_ line: String) -> Bool {
        calloutHeaderPattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }
}

/// The constant patterns of `MarkdownQuoteSyntax`; `StaticPatternTests` compiles every case.
enum MarkdownQuoteSyntaxPattern: String, StaticPatternSet {
    case calloutHeader = #"^>[ \t]?\[!([A-Za-z0-9_-]+)\]([+-]?)[ \t]*(.*)$"#
}
