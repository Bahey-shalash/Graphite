import Foundation

/// What Read Aloud leaves out because the person folded it away: hiding something is a choice
/// not to hear it. A folded callout (`> [!note]- Title`, or any callout the person collapsed)
/// is read as its title only; its body is skipped. A folded heading's section and a folded
/// list item's children are skipped. Expanding them in the view brings them back.
public enum ReadAloudFolding {
    /// The key under which a callout's live expansion is remembered: its type and written
    /// title, the same for the reading view and Live Preview.
    public static func calloutKey(type: String, title: String) -> String {
        type.lowercased() + "|" + title.trimmingCharacters(in: .whitespaces)
    }

    /// The source ranges to leave out of narration. `calloutExpansion` holds the person's
    /// own expansions by `calloutKey`; a callout not in it starts as its marker says.
    public static func hiddenRanges(in text: String, foldedKeys: Set<String>, calloutExpansion: [String: Bool]) -> [NSRange] {
        var hidden = NoteFolding.foldedRegions(in: NoteFolding.regions(in: text), foldedKeys: foldedKeys).map(\.hiddenRange)
        let source = text as NSString
        var lines: [(text: String, range: NSRange)] = []
        source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: [.byLines, .substringNotRequired]) { _, lineRange, enclosingRange, _ in
            lines.append((source.substring(with: lineRange), enclosingRange))
        }
        collapsedCalloutBodies(lines: lines.map { line in (line.text, line.range) }, depth: 0, expansion: calloutExpansion, into: &hidden)
        return hidden
    }

    /// Finds callouts in quoted lines, as the reading view does, and collects the bodies of
    /// collapsed ones; nested callouts of expanded ones are looked at in turn.
    private static func collapsedCalloutBodies(lines: [(text: String, range: NSRange)], depth: Int,
                                               expansion: [String: Bool], into hidden: inout [NSRange]) {
        guard depth < 8 else { return }
        var index = 0
        while index < lines.count {
            guard let header = MarkdownQuoteSyntax.calloutHeader(in: lines[index].text) else { index += 1; continue }
            var bodyLines: [(text: String, range: NSRange)] = []
            var bodyIndex = index + 1
            while bodyIndex < lines.count, lines[bodyIndex].text.hasPrefix(">") {
                let line = lines[bodyIndex]
                let markerLength = line.text.dropFirst().hasPrefix(" ") ? 2 : 1
                bodyLines.append((String(line.text.dropFirst(markerLength)), line.range))
                bodyIndex += 1
            }
            let key = calloutKey(type: header.type, title: header.title)
            let isExpanded = expansion[key] ?? (header.folding != .collapsed)
            if !isExpanded, let first = bodyLines.first, let last = bodyLines.last {
                hidden.append(NSUnionRange(first.range, last.range))
            } else if !bodyLines.isEmpty {
                collapsedCalloutBodies(lines: bodyLines, depth: depth + 1, expansion: expansion, into: &hidden)
            }
            index = bodyIndex
        }
    }
}
