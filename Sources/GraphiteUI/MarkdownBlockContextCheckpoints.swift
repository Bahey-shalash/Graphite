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
@MainActor
final class MarkdownBlockContextCheckpoints: NSObject {
    /// UTF-16 units between checkpoints: a lookup rescans at most about this much text.
    private static let checkpointSpacing = 2048
    /// Sorted by `lineStart`. The scanner starts from the top of the note without one.
    private var checkpoints: [MarkdownBlockCheckpoint] = []
    private weak var observedTextStorage: NSTextStorage?

    /// Spans for every line intersecting `range`, exactly as
    /// `MarkdownStyleScanner.spans(in:range:)` returns them for the storage's text.
    func spans(in textStorage: NSTextStorage, source: NSString, range: NSRange) -> [MarkdownStyleSpan] {
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
        observedTextStorage = textStorage
        // A selector observer is removed by NotificationCenter when this object goes away.
        NotificationCenter.default.addObserver(self, selector: #selector(discardCheckpointsAfterEdit(_:)),
                                               name: NSTextStorage.didProcessEditingNotification, object: textStorage)
    }

    /// Posted from `processEditing`, while `editedRange` still describes the whole edit.
    @objc private func discardCheckpointsAfterEdit(_ notification: Notification) {
        guard let textStorage = notification.object as? NSTextStorage, textStorage.editedMask.contains(.editedCharacters) else { return }
        let firstChangedLocation = textStorage.editedRange.location == NSNotFound ? 0 : textStorage.editedRange.location
        // A checkpoint before the change keeps its context, and it stays a line start
        // because the characters on both sides of it are unchanged.
        checkpoints.removeAll { checkpoint in checkpoint.lineStart >= firstChangedLocation }
    }
}
