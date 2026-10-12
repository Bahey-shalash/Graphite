import Foundation

/// The text a downloaded voice is given for a passage, and the way back to the passage.
///
/// Graphite's pronunciation layer spells acronyms out letter by letter ("V H D L") because
/// the system voice reads a written acronym as a word. Autoregressive codec models (Qwen3-TTS,
/// Chatterbox, Dia) do the opposite: a run of single letters makes them loop, mumble or invent
/// speech (Qwen3-TTS 0.6B looped "R-D-F-R-D-F" for 30 seconds on the owner's term list), while
/// they say "VHDL" or "FPGA" well as written. For those voices every letter-by-letter
/// respelling is put back to the written acronym; respellings that are words ("see moss" for
/// CMOS) are kept. Ranges the voice reports come back to the passage through `passageRange`.
public struct ReadAloudVoiceText: Equatable, Sendable {
    /// What the voice reads.
    public let text: String
    /// The passage as written: every respelling put back to the written word ("CMOS" for
    /// "see moss"), which is how speech recognition writes what it hears. Rendered audio is
    /// checked against it.
    public let writtenText: String
    /// Each changed stretch: its range in the passage's text and in `text`.
    private let changes: [(passageRange: NSRange, voiceRange: NSRange)]

    public static func == (first: ReadAloudVoiceText, second: ReadAloudVoiceText) -> Bool {
        first.text == second.text && first.writtenText == second.writtenText && first.changes.elementsEqual(second.changes) { left, right in
            left.passageRange == right.passageRange && left.voiceRange == right.voiceRange
        }
    }

    /// The passage's own text, unchanged.
    public init(passageText: String) {
        text = passageText
        writtenText = passageText
        changes = []
    }

    /// The passage with spelled-out acronyms written as acronyms again when
    /// `writesAcronymsAsWritten`, otherwise unchanged.
    public init(passage: ReadAloudPassage, writesAcronymsAsWritten: Bool) {
        let speech = passage.text as NSString
        writtenText = Self.writtenText(of: passage)
        guard writesAcronymsAsWritten else {
            text = passage.text
            changes = []
            return
        }
        var result = ""
        var changes: [(passageRange: NSRange, voiceRange: NSRange)] = []
        var cursor = 0
        var voiceLength = 0
        for span in passage.spans.sorted(by: { first, second in first.speechRange.location < second.speechRange.location }) {
            guard !span.isVerbatim, let written = span.writtenText, span.speechRange.location >= cursor,
                  NSMaxRange(span.speechRange) <= speech.length,
                  Self.isSpelledAcronym(speech.substring(with: span.speechRange), written: written) else { continue }
            let before = speech.substring(with: NSRange(location: cursor, length: span.speechRange.location - cursor))
            result += before
            voiceLength += (before as NSString).length
            let writtenLength = (written as NSString).length
            changes.append((span.speechRange, NSRange(location: voiceLength, length: writtenLength)))
            result += written
            voiceLength += writtenLength
            cursor = NSMaxRange(span.speechRange)
        }
        result += speech.substring(from: cursor)
        text = result
        self.changes = changes
    }

    /// The passage with each respelled stretch replaced by what is written there; stretches
    /// written as nothing (punctuation said aloud) keep their speech.
    static func writtenText(of passage: ReadAloudPassage) -> String {
        let speech = passage.text as NSString
        var result = ""
        var cursor = 0
        for span in passage.spans.sorted(by: { first, second in first.speechRange.location < second.speechRange.location }) {
            guard !span.isVerbatim, let written = span.writtenText, !written.isEmpty, span.speechRange.location >= cursor,
                  NSMaxRange(span.speechRange) <= speech.length else { continue }
            result += speech.substring(with: NSRange(location: cursor, length: span.speechRange.location - cursor)) + written
            cursor = NSMaxRange(span.speechRange)
        }
        return result + speech.substring(from: cursor)
    }

    /// "V H D L" or "G P U's" said for an acronym written "VHDL" or "GPUs".
    static func isSpelledAcronym(_ speech: String, written: String) -> Bool {
        let letters = speech.hasSuffix("'s") ? String(speech.dropLast(2)) : speech
        let parts = letters.split(separator: " ")
        guard parts.count >= 2, parts.allSatisfy({ part in part.count == 1 && (part.first?.isLetter == true || part.first?.isNumber == true) }) else { return false }
        return !written.isEmpty && written.count <= 12 && written.allSatisfy { character in character.isLetter || character.isNumber }
    }

    /// The passage range for a range of `text`: a word inside a changed stretch maps to the
    /// whole respelling, the rest shifts by the length differences before it.
    public func passageRange(forVoiceRange range: NSRange) -> NSRange {
        var shift = 0
        for change in changes {
            if NSMaxRange(range) <= change.voiceRange.location { break }
            if NSIntersectionRange(range, change.voiceRange).length > 0 || range.location == change.voiceRange.location {
                return change.passageRange
            }
            shift += change.passageRange.length - change.voiceRange.length
        }
        return NSRange(location: range.location + shift, length: range.length)
    }

    /// Where a passage offset falls in `text`, for starting playback in the middle of a passage.
    public func voiceOffset(forPassageOffset offset: Int) -> Int {
        var shift = 0
        for change in changes {
            if offset < change.passageRange.location { break }
            if offset < NSMaxRange(change.passageRange) { return change.voiceRange.location }
            shift += change.voiceRange.length - change.passageRange.length
        }
        return max(0, offset + shift)
    }
}
