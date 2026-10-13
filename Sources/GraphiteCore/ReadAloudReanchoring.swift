import Foundation

/// Finding the place being read again after the text around it was edited: the sentence
/// being spoken, as written, is looked for in the new text near where it was, and reading
/// goes on from there. Matching is by text alone, never by offsets, which an edit before
/// the sentence would move.
public enum ReadAloudReanchoring {
    /// The sentence being read, as written in the source, and where it began.
    public struct Anchor: Equatable, Sendable {
        public let text: String
        public let location: Int
    }

    /// The written sentence that holds `spokenOffset` in the passage, or the passage's whole
    /// written text when its sentence cannot be mapped (an equation, a table row).
    public static func anchor(in source: String, passage: ReadAloudPassage, spokenOffset: Int) -> Anchor? {
        let spoken = passage.text as NSString
        var sentence = NSRange(location: 0, length: spoken.length)
        passage.text.enumerateSubstrings(in: passage.text.startIndex..<passage.text.endIndex, options: [.bySentences, .substringNotRequired]) { _, range, _, stop in
            let candidate = NSRange(range, in: passage.text)
            if candidate.location <= spokenOffset, spokenOffset < NSMaxRange(candidate) || NSMaxRange(candidate) == spoken.length {
                sentence = candidate
                stop = true
            }
        }
        let wholePassage = passage.spans.map(\.sourceRange).reduce(nil as NSRange?) { union, range in union.map { NSUnionRange($0, range) } ?? range }
        guard let written = passage.sourceRange(for: sentence) ?? wholePassage else { return nil }
        let sourceText = source as NSString
        guard NSMaxRange(written) <= sourceText.length else { return nil }
        let text = sourceText.substring(with: written).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let leading = sourceText.substring(with: written).prefix { character in character.isWhitespace || character.isNewline }
        return Anchor(text: text, location: written.location + (String(leading) as NSString).length)
    }

    /// Where the anchored sentence is in the edited text: the occurrence nearest its old
    /// place; failing that, its first or last sixty characters (the sentence itself was
    /// edited at its other end). Nil when none is found.
    public static func location(of anchor: Anchor, in text: String) -> Int? {
        if let range = range(of: anchor.text, near: anchor.location, in: text) { return range.location }
        let characters = Array(anchor.text)
        guard characters.count > 24 else { return nil }
        let head = String(characters.prefix(60))
        if let range = range(of: head, near: anchor.location, in: text) { return range.location }
        let tail = String(characters.suffix(60))
        if let range = range(of: tail, near: anchor.location + (anchor.text as NSString).length - (tail as NSString).length, in: text) {
            // The sentence's start moved by what was added or removed before its tail.
            return max(0, range.location - ((anchor.text as NSString).length - (tail as NSString).length))
        }
        return nil
    }

    /// The occurrence of `needle` in `text` nearest `location`.
    public static func range(of needle: String, near location: Int, in text: String) -> NSRange? {
        guard !needle.isEmpty else { return nil }
        let haystack = text as NSString
        var best: NSRange?
        var searchRange = NSRange(location: 0, length: haystack.length)
        while searchRange.length > 0 {
            let found = haystack.range(of: needle, options: [.literal], range: searchRange)
            guard found.location != NSNotFound else { break }
            if best.map({ abs($0.location - location) > abs(found.location - location) }) ?? true { best = found }
            let next = found.location + 1
            searchRange = NSRange(location: next, length: haystack.length - next)
        }
        return best
    }

    /// The passage that holds a source location, and the offset in its spoken text where
    /// the words from that location begin.
    public static func position(of location: Int, in document: ReadAloudDocument) -> (passageIndex: Int, offset: Int) {
        for (index, passage) in document.passages.enumerated() {
            guard let span = passage.spans.first(where: { span in NSMaxRange(span.sourceRange) > location }) else { continue }
            return (index, span.sourceRange.location >= location ? span.speechRange.location
                : span.isVerbatim ? span.speechRange.location + min(location - span.sourceRange.location, span.speechRange.length) : span.speechRange.location)
        }
        return (max(0, document.passages.count - 1), 0)
    }
}
