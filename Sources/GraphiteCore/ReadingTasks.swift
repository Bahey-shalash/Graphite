import Foundation

/// Where the characters of a text made by replacing ranges of another text were in that
/// text. Reading view removes comments and footnote definitions before it splits a note
/// into blocks, and still has to say where a task of a block is in the note.
public struct ReplacedTextOffsets: Sendable {
    private struct Replacement: Sendable {
        let originalRange: NSRange
        /// Where the text put in place of the range starts in the result.
        let resultStart: Int
        let replacementLength: Int
    }

    private let replacements: [Replacement]

    /// - Parameter replacements: Ranges of the original text that do not overlap, in any
    ///   order, each with the UTF-16 length of the text put in its place.
    public init(replacements: [(range: NSRange, replacementLength: Int)]) {
        var removedLength = 0
        self.replacements = replacements.sorted { first, second in first.range.location < second.range.location }.map { replacement in
            defer { removedLength += replacement.range.length - replacement.replacementLength }
            return Replacement(originalRange: replacement.range, resultStart: replacement.range.location - removedLength,
                               replacementLength: replacement.replacementLength)
        }
    }

    /// The offset in the original text of the character at `offset` of the result. The first
    /// character of a replacement is where the replaced range started; its later characters
    /// were not in the original text, so they have no offset.
    public func originalOffset(of offset: Int) -> Int? {
        // The last replacement that starts at or before the offset; several start at the
        // same place when ranges next to each other were removed.
        var lowerBound = 0
        var upperBound = replacements.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if replacements[middle].resultStart <= offset { lowerBound = middle + 1 } else { upperBound = middle }
        }
        guard lowerBound > 0 else { return offset }
        let replacement = replacements[lowerBound - 1]
        let replacementEnd = replacement.resultStart + replacement.replacementLength
        if offset < replacementEnd { return offset == replacement.resultStart ? replacement.originalRange.location : nil }
        return NSMaxRange(replacement.originalRange) + offset - replacementEnd
    }
}

/// Tasks as reading view draws them: a list item, in a quote or callout too, whose text
/// starts with one status character in brackets. A tap on a task's checkbox changes that
/// one character of the note.
public enum ReadingTasks {
    /// Where a task is in its note.
    public struct Location: Hashable, Sendable {
        /// UTF-16 offset of the status character, the one between the brackets.
        public let statusOffset: Int
        /// A checksum of the task's line without its status character. A tap made while
        /// reading view still shows an older text must not change another line.
        public let lineChecksum: UInt32

        public init(statusOffset: Int, lineChecksum: UInt32) {
            self.statusOffset = statusOffset; self.lineChecksum = lineChecksum
        }
    }

    /// A task in text prepared for reading: its status, and its place in the note when a
    /// tap on its checkbox can change the note.
    public struct MarkedTask: Hashable, Sendable {
        public let status: Unicode.Scalar
        public let location: Location?
        /// Any status other than a space is shown checked, as in Obsidian.
        public var isChecked: Bool { status != " " }
        /// The checkbox as it is written in a note.
        public var sourceText: String { "[" + String(Character(status)) + "]" }

        public init(status: Unicode.Scalar, location: Location?) {
            self.status = status; self.location = location
        }
    }

    /// Group 1 is the quote markers, indentation and list marker before the checkbox, and
    /// group 2 the status character. Any single character is a status, as in Obsidian.
    static let pattern = try? NSRegularExpression(pattern: "^(\\s*(?:>\\s*)*(?:[-*+]|\\d+[.)])\\s+)\\[([^\\]\\n])\\](?=\\s|$)")

    private static let lineFeed = UInt16(UInt8(ascii: "\n"))
    private static let carriageReturn = UInt16(UInt8(ascii: "\r"))
    private static let openingBracket = UInt16(UInt8(ascii: "["))
    private static let closingBracket = UInt16(UInt8(ascii: "]"))
    private static let asciiDigits: ClosedRange<UInt32> = 0x30...0x39

    /// The task written in `text` from `lineStart` to the end of that line, when its status
    /// is `status`. `lineStart` is the start of a line, or the place after the quote markers
    /// of a callout, whose body reading view splits into blocks of its own.
    public static func location(ofTaskStartingAt lineStart: Int, status: Unicode.Scalar, in text: String) -> Location? {
        let source = text as NSString
        guard let pattern, lineStart >= 0, lineStart <= source.length else { return nil }
        let line = lineContentRange(containing: lineStart, in: source)
        let searchRange = NSRange(location: lineStart, length: NSMaxRange(line) - lineStart)
        guard let match = pattern.firstMatch(in: text, options: .anchored, range: searchRange) else { return nil }
        let statusRange = match.range(at: 2)
        guard source.substring(with: statusRange).unicodeScalars.elementsEqual([status]) else { return nil }
        return Location(statusOffset: statusRange.location, lineChecksum: checksum(ofLine: line, withoutStatusAt: statusRange, in: source))
    }

    /// The edit a tap on a task's checkbox makes, as in Obsidian: a space becomes `x`, and
    /// any other status becomes a space. Only the status character changes. Nil when the
    /// text no longer has the task at `location`, as after an edit reading view has not
    /// drawn yet.
    /// - Parameter selection: The selection before the edit, which the edit keeps.
    public static func togglingEdit(at location: Location, in text: String, selection: NSRange) -> MarkdownTextEdit? {
        let source = text as NSString
        guard let statusRange = statusRange(at: location.statusOffset, in: source) else { return nil }
        let line = lineContentRange(containing: statusRange.location, in: source)
        guard checksum(ofLine: line, withoutStatusAt: statusRange, in: source) == location.lineChecksum else { return nil }
        let replacement = source.substring(with: statusRange) == " " ? "x" : " "
        // A status outside the Basic Multilingual Plane, such as an emoji, is two UTF-16
        // units wide, so the text after it moves.
        let removedLength = statusRange.length - replacement.utf16.count
        func moved(_ offset: Int) -> Int {
            if offset >= NSMaxRange(statusRange) { return offset - removedLength }
            return min(offset, statusRange.location + replacement.utf16.count)
        }
        let selectionStart = moved(selection.location)
        let selectionAfter = NSRange(location: selectionStart, length: max(moved(NSMaxRange(selection)) - selectionStart, 0))
        return MarkdownTextEdit(range: statusRange, replacement: replacement, selectionAfter: selectionAfter)
    }

    /// The status character at `offset` when brackets enclose it: one character, which is
    /// two UTF-16 units for a character outside the Basic Multilingual Plane.
    private static func statusRange(at offset: Int, in source: NSString) -> NSRange? {
        guard offset > 0, offset < source.length, source.character(at: offset - 1) == openingBracket else { return nil }
        let isSurrogatePair = UTF16.isLeadSurrogate(source.character(at: offset)) && offset + 1 < source.length
            && UTF16.isTrailSurrogate(source.character(at: offset + 1))
        let statusRange = NSRange(location: offset, length: isSurrogatePair ? 2 : 1)
        guard NSMaxRange(statusRange) < source.length, source.character(at: NSMaxRange(statusRange)) == closingBracket,
              source.character(at: offset) != lineFeed, source.character(at: offset) != closingBracket else { return nil }
        return statusRange
    }

    /// The line around `offset` without its line ending. Lines end at a line feed, as they
    /// do where reading view splits a note into lines.
    private static func lineContentRange(containing offset: Int, in source: NSString) -> NSRange {
        var lineStart = offset
        while lineStart > 0, source.character(at: lineStart - 1) != lineFeed { lineStart -= 1 }
        var lineEnd = offset
        while lineEnd < source.length, source.character(at: lineEnd) != lineFeed { lineEnd += 1 }
        if lineEnd > lineStart, source.character(at: lineEnd - 1) == carriageReturn { lineEnd -= 1 }
        return NSRange(location: lineStart, length: lineEnd - lineStart)
    }

    /// FNV-1a over the line's UTF-16 units, the status character left out, so ticking a
    /// task does not change its line's checksum.
    private static func checksum(ofLine line: NSRange, withoutStatusAt statusRange: NSRange, in source: NSString) -> UInt32 {
        var checksum: UInt32 = 2_166_136_261
        for offset in line.location..<NSMaxRange(line) where !NSLocationInRange(offset, statusRange) {
            let codeUnit = source.character(at: offset)
            for byte in [UInt8(codeUnit & 0xFF), UInt8(codeUnit >> 8)] {
                checksum = (checksum ^ UInt32(byte)) &* 16_777_619
            }
        }
        return checksum
    }

    // MARK: Tasks in text prepared for reading

    /// What stands for a task's brackets in text prepared for reading: the marker, the
    /// status character's code point and, when the task has a place in the note, the marker
    /// again before each of its status offset and its line checksum. Only markers and
    /// digits, which Markdown leaves as they are.
    static func markedText(for task: MarkedTask) -> String {
        let marker = String(task.isChecked ? ObsidianInlineMarkup.checkedTaskMarker : ObsidianInlineMarkup.uncheckedTaskMarker)
        var text = marker + String(task.status.value)
        if let location = task.location { text += marker + String(location.statusOffset) + marker + String(location.lineChecksum) }
        return text
    }

    /// The task marked at `start` of `scalars`, and where its marked text ends; nil when
    /// no task is marked there.
    public static func markedTask<Scalars: Collection>(at start: Scalars.Index, in scalars: Scalars) -> (task: MarkedTask, end: Scalars.Index)?
    where Scalars.Element == Unicode.Scalar {
        guard start < scalars.endIndex, isTaskMarker(scalars[start]) else { return nil }
        let marker = scalars[start]
        var position = scalars.index(after: start)
        /// The number written in ASCII digits at `position`, which moves past them; nil
        /// without a digit there, or for a number too large to be one written here.
        func number() -> UInt64? {
            var number: UInt64?
            while position < scalars.endIndex, asciiDigits.contains(scalars[position].value) {
                let (product, productOverflowed) = (number ?? 0).multipliedReportingOverflow(by: 10)
                let (sum, sumOverflowed) = product.addingReportingOverflow(UInt64(scalars[position].value - asciiDigits.lowerBound))
                guard !productOverflowed, !sumOverflowed else { return nil }
                number = sum
                position = scalars.index(after: position)
            }
            return number
        }
        guard let statusValue = number(), let statusCodePoint = UInt32(exactly: statusValue), let status = Unicode.Scalar(statusCodePoint) else { return nil }
        let statusEnd = position
        guard position < scalars.endIndex, scalars[position] == marker else { return (MarkedTask(status: status, location: nil), statusEnd) }
        position = scalars.index(after: position)
        guard let statusOffset = number().flatMap(Int.init(exactly:)), position < scalars.endIndex, scalars[position] == marker else {
            return (MarkedTask(status: status, location: nil), statusEnd)
        }
        position = scalars.index(after: position)
        guard let lineChecksum = number().flatMap(UInt32.init(exactly:)) else { return (MarkedTask(status: status, location: nil), statusEnd) }
        return (MarkedTask(status: status, location: Location(statusOffset: statusOffset, lineChecksum: lineChecksum)), position)
    }

    public static func isTaskMarker(_ scalar: Unicode.Scalar) -> Bool {
        ObsidianInlineMarkup.uncheckedTaskMarker.unicodeScalars.first == scalar || ObsidianInlineMarkup.checkedTaskMarker.unicodeScalars.first == scalar
    }
}
