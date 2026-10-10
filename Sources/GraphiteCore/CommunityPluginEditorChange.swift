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

/// HTML for a plugin's `MarkdownRenderer.render`, from swift-markdown's CommonMark reader.
/// Obsidian's own syntax (wikilinks, callouts) stays text here; the runtime turns
/// wikilinks into internal links afterwards. Plugin views receive it, never notes.
public enum CommunityPluginMarkdownRendering {
    /// Markdown longer than this is not rendered for a plugin in one call.
    public static let maximumMarkdownLength = 4 * 1_048_576

    public static func html(for markdown: String) throws -> String {
        guard (markdown as NSString).length <= maximumMarkdownLength else {
            throw GraphiteError.oversized("This Markdown is too long for a plugin to render at once.")
        }
        return HTMLFormatter.format(markdown)
    }
}
