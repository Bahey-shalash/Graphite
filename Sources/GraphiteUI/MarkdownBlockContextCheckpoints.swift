import Foundation
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Remembers the Markdown scanner's block state (fenced code, `$$` math, frontmatter) at
/// line starts of one text storage, so restyling a line far down a long note does not
/// rescan the note from its top on every keystroke and caret move.
///
/// The state at a line depends only on the text before it. An edit therefore keeps every
/// checkpoint before the first changed character; the storage's own edit notification drops
/// the others, so typing, undo, paste, and find-and-replace all invalidate alike.
///
/// It also remembers the spans of the lines asked for last, which a cursor moving along
/// one line asks for at every step, and that a text holds no color marker, as most notes
/// do not, which spares each restyle and cursor move the search for the colors around it.
@MainActor
final class MarkdownBlockContextCheckpoints: NSObject {
    /// UTF-16 units between checkpoints: a lookup rescans at most about this much text.
    private static let checkpointSpacing = 2048
    /// Sorted by `lineStart`. The scanner starts from the top of the note without one.
    private var checkpoints: [MarkdownBlockCheckpoint] = []
    private weak var observedTextStorage: NSTextStorage?
    /// Whether the text may hold a color's opening marker; nil until looked for. Once
    /// true it stays true: a note whose last marker is deleted is searched as before.
    private var mayContainColorMarker: Bool?
    private static let colorOpeningMarkerStart = "~={"
    /// The spans returned last, newest first, by the range asked for. Two are kept: a
    /// cursor jumping between two lines asks for both.
    private var recentSpans: [(range: NSRange, spans: [MarkdownStyleSpan])] = []
    private static let rememberedSpanRangeCount = 2

    /// Spans for every line intersecting `range`, exactly as
    /// `MarkdownStyleScanner.spans(in:range:)` returns them for the storage's text.
    func spans(in textStorage: NSTextStorage, source: NSString, range: NSRange) -> [MarkdownStyleSpan] {
        observe(textStorage)
        if let rememberedIndex = recentSpans.firstIndex(where: { remembered in remembered.range == range }) {
            let remembered = recentSpans.remove(at: rememberedIndex)
            recentSpans.insert(remembered, at: 0)
            return remembered.spans
        }
        let spans = scannedSpans(in: textStorage, source: source, range: range)
        recentSpans.insert((range, spans), at: 0)
        if recentSpans.count > Self.rememberedSpanRangeCount { recentSpans.removeLast() }
        return spans
    }

    private func scannedSpans(in textStorage: NSTextStorage, source: NSString, range: NSRange) -> [MarkdownStyleSpan] {
        let clampedLocation = min(max(range.location, 0), source.length)
        let wholeLines = source.lineRange(for: NSRange(location: clampedLocation, length: min(max(range.length, 0), source.length - clampedLocation)))
        // The scanner also reads the line before the range, to style a setext heading's text.
        let previousLineStart = wholeLines.location > 0 ? source.lineRange(for: NSRange(location: wholeLines.location - 1, length: 0)).location : 0
        let checkpoint = nearestCheckpoint(atOrBefore: previousLineStart, in: textStorage, source: source)
        return MarkdownStyleScanner.spans(in: source, range: range, resumingFrom: checkpoint)
    }

    /// The block context in effect at `lineStart`, which must be the start of a line.
    func blockContext(atLineStart lineStart: Int, in textStorage: NSTextStorage, source: NSString) -> MarkdownBlockContext {
        let checkpoint = nearestCheckpoint(atOrBefore: lineStart, in: textStorage, source: source)
        return MarkdownStyleScanner.blockCheckpoint(atLineStart: lineStart, in: source, resumingFrom: checkpoint).context
    }

    /// Whether the storage's text, given as `source`, may hold a color's opening marker
    /// `~={`. Colors are found between the blank lines around the styled text, which in a
    /// long note without blank lines is the whole note; a note without the marker needs
    /// no such search.
    func mayContainColorMarker(in textStorage: NSTextStorage, source: NSString) -> Bool {
        observe(textStorage)
        if let mayContainColorMarker { return mayContainColorMarker }
        let containsMarker = source.range(of: Self.colorOpeningMarkerStart).location != NSNotFound
        mayContainColorMarker = containsMarker
        return containsMarker
    }

    /// The last checkpoint at or before `lineStart`, walking forward from the nearest one
    /// kept and leaving new ones behind for the next lookup; nil when `lineStart` is near
    /// enough to the top of the note.
    private func nearestCheckpoint(atOrBefore lineStart: Int, in textStorage: NSTextStorage, source: NSString) -> MarkdownBlockCheckpoint? {
        observe(textStorage)
        var checkpointIndex = indexOfLastCheckpoint(atOrBefore: lineStart)
        var checkpoint = checkpointIndex.map { index in checkpoints[index] }
        while lineStart - (checkpoint?.lineStart ?? 0) > Self.checkpointSpacing {
            let walkStart = checkpoint?.lineStart ?? 0
            let lineAfterWalkStart = NSMaxRange(source.lineRange(for: NSRange(location: walkStart, length: 0)))
            let nextLineStart = max(source.lineRange(for: NSRange(location: walkStart + Self.checkpointSpacing, length: 0)).location, lineAfterWalkStart)
            guard nextLineStart < lineStart else { break }
            let nextCheckpoint = MarkdownStyleScanner.blockCheckpoint(atLineStart: nextLineStart, in: source, resumingFrom: checkpoint)
            let insertionIndex = checkpointIndex.map { index in index + 1 } ?? 0
            checkpoints.insert(nextCheckpoint, at: insertionIndex)
            checkpointIndex = insertionIndex
            checkpoint = nextCheckpoint
        }
        return checkpoint
    }

    private func indexOfLastCheckpoint(atOrBefore location: Int) -> Int? {
        var lowerBound = 0
        var upperBound = checkpoints.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if checkpoints[middle].lineStart <= location { lowerBound = middle + 1 } else { upperBound = middle }
        }
        return lowerBound == 0 ? nil : lowerBound - 1
    }

    private func observe(_ textStorage: NSTextStorage) {
        guard observedTextStorage !== textStorage else { return }
        if let observedTextStorage {
            NotificationCenter.default.removeObserver(self, name: NSTextStorage.didProcessEditingNotification, object: observedTextStorage)
        }
        checkpoints.removeAll()
        recentSpans.removeAll()
        mayContainColorMarker = nil
        observedTextStorage = textStorage
        // A selector observer is removed by NotificationCenter when this object goes away.
        NotificationCenter.default.addObserver(self, selector: #selector(discardWhatAnEditInvalidates(_:)),
                                               name: NSTextStorage.didProcessEditingNotification, object: textStorage)
    }

    /// Posted from `processEditing`, while `editedRange` still describes the whole edit.
    @objc private func discardWhatAnEditInvalidates(_ notification: Notification) {
        guard let textStorage = notification.object as? NSTextStorage, textStorage.editedMask.contains(.editedCharacters) else { return }
        recentSpans.removeAll()
        let editedRange = textStorage.editedRange
        let firstChangedLocation = editedRange.location == NSNotFound ? 0 : editedRange.location
        // A checkpoint before the change keeps its context, and it stays a line start
        // because the characters on both sides of it are unchanged.
        checkpoints.removeAll { checkpoint in checkpoint.lineStart >= firstChangedLocation }
        guard mayContainColorMarker == false else { return }
        guard editedRange.location != NSNotFound else {
            mayContainColorMarker = nil
            return
        }
        // A marker can only have appeared in the new text or across one of its ends,
        // where a deletion can join `~=` to `{`.
        let text = textStorage.mutableString
        let markerLength = (Self.colorOpeningMarkerStart as NSString).length
        let searchStart = max(0, editedRange.location - (markerLength - 1))
        let searchEnd = min(text.length, NSMaxRange(editedRange) + (markerLength - 1))
        if text.range(of: Self.colorOpeningMarkerStart, options: [], range: NSRange(location: searchStart, length: searchEnd - searchStart)).location != NSNotFound {
            mayContainColorMarker = true
        }
    }
}
