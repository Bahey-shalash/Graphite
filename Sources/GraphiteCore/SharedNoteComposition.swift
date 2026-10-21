import Foundation

/// The text a shared item adds to a vault, decided from plain values: the note's name, the
/// new note's text, and what is added at the end of an existing note.
public enum SharedNoteComposition {
    /// The name a note gets when the share sheet's title leaves nothing usable.
    public static let untitledStem = "Untitled"

    /// The title typed in the share sheet as a note's file stem: characters no note name may
    /// contain (`FileNameRules`) become spaces, runs of spaces become one, leading dots go,
    /// and the name is cut at a character to the longest a note name may be.
    public static func noteStem(fromTitle title: String) -> String {
        let refusedCharacters = FileNameRules.forbiddenCharacters.union(FileNameRules.linkBreakingCharacters).union(FileNameRules.controlCharacters)
        let spaced = String(String.UnicodeScalarView(title.unicodeScalars.map { scalar in refusedCharacters.contains(scalar) ? " " : scalar }))
        let collapsed = spaced.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        var stem = String(collapsed.drop { character in character == "." || character == " " })
        let maximumStemBytes = FileNameRules.maximumFileNameBytes - FileNameRules.reservedSuffixBytes
        while stem.utf8.count > maximumStemBytes { stem.removeLast() }
        stem = stem.trimmingCharacters(in: .whitespaces)
        return stem.isEmpty ? untitledStem : stem
    }

    /// The shared text followed by the embeds of its files, one per line, a blank line
    /// between the two; ends with a line break unless it is empty.
    public static func noteText(sharedText: String, embeds: [String]) -> String {
        let parts = [sharedText.trimmingCharacters(in: .whitespacesAndNewlines), embeds.joined(separator: "\n")].filter { part in !part.isEmpty }
        return parts.isEmpty ? "" : parts.joined(separator: "\n\n") + "\n"
    }

    /// What to add at the end of `existingText` so `block` follows it as a paragraph of its
    /// own: a line break when the last line has none, a blank line, then the block, all in
    /// the note's own line ending. An empty note gets the block alone.
    public static func suffixAppending(_ block: String, to existingText: String) -> String {
        guard !block.isEmpty else { return "" }
        let lineEnding = lineEnding(of: existingText)
        let convertedBlock = lineEnding == "\n" ? block : block.replacingOccurrences(of: "\n", with: lineEnding)
        guard !existingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return convertedBlock }
        let trailingLineBreakCount = trailingLineBreaks(in: existingText)
        let missingLineBreaks = max(0, 2 - trailingLineBreakCount)
        return String(repeating: lineEnding, count: missingLineBreaks) + convertedBlock
    }

    /// The note's first line ending: CRLF, a lone CR, or LF, which a note without one gets.
    static func lineEnding(of text: String) -> String {
        let scalars = text.unicodeScalars
        guard let separatorIndex = scalars.firstIndex(where: { scalar in scalar == "\n" || scalar == "\r" }) else { return "\n" }
        guard scalars[separatorIndex] == "\r" else { return "\n" }
        let nextIndex = scalars.index(after: separatorIndex)
        return nextIndex < scalars.endIndex && scalars[nextIndex] == "\n" ? "\r\n" : "\r"
    }

    /// How many line breaks end the text, counting CRLF as one.
    private static func trailingLineBreaks(in text: String) -> Int {
        var count = 0
        var scalars = Substring(text).unicodeScalars
        while let last = scalars.last, last == "\n" || last == "\r" {
            scalars.removeLast()
            if last == "\n", scalars.last == "\r" { scalars.removeLast() }
            count += 1
        }
        return count
    }
}
