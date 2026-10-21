import Foundation
import Markdown

/// A plugin's change to the open note, as one edit for Graphite's editor. The plugin
/// worked on a copy of the note and sends back the whole text it ended with; the edit
/// replaces only the part that differs, so the editor's undo, folds and scroll position
/// see a small change rather than a new note.
public enum CommunityPluginEditorChange {
    /// The smallest edit that turns `originalText` into `changedText`, with the selection
    /// the plugin left (UTF-16 offsets into `changedText`, as JavaScript and `NSString`
    /// count). Nil when the text is unchanged.
    public static func edit(from originalText: String, to changedText: String, selectionAnchor: Int, selectionHead: Int) -> MarkdownTextEdit? {
        let original = originalText as NSString
        let changed = changedText as NSString
        guard !original.isEqual(to: changedText) else { return nil }
        let shorterLength = min(original.length, changed.length)
        var prefixLength = 0
        while prefixLength < shorterLength, original.character(at: prefixLength) == changed.character(at: prefixLength) { prefixLength += 1 }
        // Never split a surrogate pair: the edit would cut a character in half.
        if prefixLength > 0, UTF16.isLeadSurrogate(original.character(at: prefixLength - 1)) { prefixLength -= 1 }
        var suffixLength = 0
        while suffixLength < shorterLength - prefixLength,
              original.character(at: original.length - 1 - suffixLength) == changed.character(at: changed.length - 1 - suffixLength) {
            suffixLength += 1
        }
        if suffixLength > 0, UTF16.isTrailSurrogate(original.character(at: original.length - suffixLength)) { suffixLength -= 1 }
        let replacedRange = NSRange(location: prefixLength, length: original.length - prefixLength - suffixLength)
        let replacement = changed.substring(with: NSRange(location: prefixLength, length: changed.length - prefixLength - suffixLength))
        let selectionStart = min(max(min(selectionAnchor, selectionHead), 0), changed.length)
        let selectionEnd = min(max(max(selectionAnchor, selectionHead), 0), changed.length)
        return MarkdownTextEdit(range: replacedRange, replacement: replacement, selectionAfter: NSRange(location: selectionStart, length: selectionEnd - selectionStart))
    }
}

/// HTML for a plugin's `MarkdownRenderer.render`, from swift-markdown's CommonMark reader,
/// with Obsidian's own syntax as Obsidian renders it: the frontmatter left out (Obsidian
/// hides it), `==highlights==` marked, and `> [!type]` callouts as Obsidian's callout
/// elements. The runtime turns wikilinks into internal links afterwards. Plugin views
/// receive it (Excalidraw draws an embedded note from it), never notes.
public enum CommunityPluginMarkdownRendering {
    /// Markdown longer than this is not rendered for a plugin in one call.
    public static let maximumMarkdownLength = 4 * 1_048_576

    public static func html(for markdown: String) throws -> String {
        guard (markdown as NSString).length <= maximumMarkdownLength else {
            throw GraphiteError.oversized("This Markdown is too long for a plugin to render at once.")
        }
        let source = markdown as NSString
        let body = source.substring(from: FrontmatterLocator.length(in: source))
        return calloutsMarked(in: HTMLFormatter.format(highlightsMarked(in: body)))
    }

    /// `==text==` as `<mark>`, outside fenced code and code spans.
    static func highlightsMarked(in markdown: String) -> String {
        var isInFence = false
        var fenceMarker = ""
        return markdown.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isInFence {
                if trimmed.hasPrefix(fenceMarker) { isInFence = false }
                return line
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                isInFence = true
                fenceMarker = String(trimmed.prefix(3))
                return line
            }
            guard line.contains("==") else { return line }
            // Code spans keep their text: only the parts between them are marked.
            let parts = line.components(separatedBy: "`")
            return parts.enumerated().map { index, part in
                index % 2 == 1 ? part : part.replacingOccurrences(of: "==([^=\\s](?:[^=]*[^=\\s])?)==", with: "<mark>$1</mark>", options: .regularExpression)
            }.joined(separator: "`")
        }.joined(separator: "\n")
    }

    private static let calloutOpening = CommunityPluginMarkdownRenderingPattern.calloutOpening.compiled()

    /// Quotes that open with `[!type]` as Obsidian's callouts, nested ones too.
    static func calloutsMarked(in html: String) -> String {
        guard html.contains("[!") else { return html }
        var output = ""
        var calloutStack: [Bool] = []
        var remaining = Substring(html)
        while let tagRange = nextQuoteTag(in: remaining) {
            output += remaining[..<tagRange.0.lowerBound]
            if tagRange.1 {
                let rest = String(remaining[tagRange.0.lowerBound...])
                let restRange = NSRange(location: 0, length: (rest as NSString).length)
                if let match = calloutOpening.firstMatch(in: rest, range: restRange) {
                    let type = (rest as NSString).substring(with: match.range(at: 1)).lowercased()
                    let folding = (rest as NSString).substring(with: match.range(at: 2))
                    var title = (rest as NSString).substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
                    if title.isEmpty { title = type.prefix(1).uppercased() + type.dropFirst() }
                    let foldClass = folding.isEmpty ? "" : " is-collapsible" + (folding == "-" ? " is-collapsed" : "")
                    output += "<div data-callout-metadata=\"\" data-callout-fold=\"\(folding)\" data-callout=\"\(type)\" class=\"callout\(foldClass)\">"
                        + "<div class=\"callout-title\"><div class=\"callout-icon\"></div><div class=\"callout-title-inner\">\(title)</div></div>"
                        + "<div class=\"callout-content\">" + (match.range(at: 4).location == NSNotFound ? "<p>" : "")
                    remaining = remaining[remaining.index(tagRange.0.lowerBound, offsetBy: (rest as NSString).substring(with: match.range).count)...]
                    calloutStack.append(true)
                    continue
                }
                output += "<blockquote>"
                calloutStack.append(false)
            } else {
                output += calloutStack.popLast() == true ? "</div></div>" : "</blockquote>"
            }
            remaining = remaining[tagRange.0.upperBound...]
        }
        output += remaining
        return output
    }

    /// The next `<blockquote>` or `</blockquote>`, and whether it opens a quote.
    private static func nextQuoteTag(in text: Substring) -> (Range<Substring.Index>, Bool)? {
        let opening = text.range(of: "<blockquote>")
        let closing = text.range(of: "</blockquote>")
        switch (opening, closing) {
        case (let opening?, let closing?): return opening.lowerBound < closing.lowerBound ? (opening, true) : (closing, false)
        case (let opening?, nil): return (opening, true)
        case (nil, let closing?): return (closing, false)
        case (nil, nil): return nil
        }
    }
}

/// The constant patterns of `CommunityPluginMarkdownRendering`; `StaticPatternTests` compiles every case.
enum CommunityPluginMarkdownRenderingPattern: String, StaticPatternSet {
    case calloutOpening = #"^<blockquote>\s*<p>\[!([A-Za-z0-9_-]+)\]([+-]?)[ \t]*([^\n<]*)(?:\n|(</p>))"#
}
