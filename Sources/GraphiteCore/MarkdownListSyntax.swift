import Foundation

/// List items, task checkboxes and thematic breaks, read one line at a time. A thematic
/// break such as `- - -` is read before a list item, as CommonMark reads it.
public enum MarkdownListSyntax {
    /// A line's list or quote markup: `> ` quote markers, indentation, the bullet or
    /// number, and a task checkbox. Every part is the text exactly as the line has it.
    public struct ListLine: Equatable, Sendable {
        public let quotePrefix: String
        public let indentation: String
        /// `-`, `*`, `+`, or a number with `.` or `)`; empty for a quote line alone.
        public let marker: String
        /// The whitespace after the marker; empty when the marker ends the line, as in a
        /// `-` typed alone.
        public let spacing: String
        /// The character inside `[ ]`, when the item is a task: any one character, as Obsidian
        /// and the Tasks plugin write them (`[>]`, `[!]`, `[?]`), not only `[ ]` and `[x]`.
        public let taskStatus: Character?
        /// The checkbox as written: `[x] `, or `[ ]` when it ends the line; empty when the
        /// item is not a task.
        public let checkbox: String
        /// Everything before the item's text, in UTF-16 units.
        public var prefixLength: Int { (quotePrefix + indentation + marker + spacing + checkbox).utf16.count }
        public var isListItem: Bool { !marker.isEmpty }
        public var orderedNumber: Int? { Int(marker.dropLast()) }
    }

    /// Where the parts of a `ListLine` are in the line, found without copying any of them,
    /// for callers that read every line of a note. Ranges are in the text the line is in.
    struct ListLineRanges {
        let quotePrefix: NSRange
        let indentation: NSRange
        /// Empty (at the end of the quote prefix) for a quote line alone.
        let marker: NSRange
        let spacing: NSRange
        /// The `[x]` of a task, and the space after it when there is one; nil for no task.
        let checkbox: NSRange?
        /// The character inside the checkbox; nil for no task.
        let taskStatus: NSRange?

        var isListItem: Bool { marker.length > 0 }
    }

    // `[0-9]`, not `\d`: ICU's `\d` matches every script's decimal digits, and CommonMark
    // numbers a list only with ASCII digits.
    private static let listLinePattern = MarkdownListSyntaxPattern.listLine.compiled()
    private static let thematicBreakPattern = MarkdownListSyntaxPattern.thematicBreak.compiled()
    private static let hyphen = UInt16(UInt8(ascii: "-"))
    private static let asterisk = UInt16(UInt8(ascii: "*"))
    private static let plus = UInt16(UInt8(ascii: "+"))
    private static let space = UInt16(UInt8(ascii: " "))
    private static let tab = UInt16(UInt8(ascii: "\t"))
    private static let greaterThan = UInt16(UInt8(ascii: ">"))
    private static let zero = UInt16(UInt8(ascii: "0"))
    private static let nine = UInt16(UInt8(ascii: "9"))
    private static let period = UInt16(UInt8(ascii: "."))
    private static let closingParenthesis = UInt16(UInt8(ascii: ")"))

    /// The list or quote markup of `line` (without its line ending), or nil for plain text.
    public static func listLine(_ line: String) -> ListLine? {
        let text = line as NSString
        guard let ranges = listLineRanges(in: text, range: NSRange(location: 0, length: text.length)) else { return nil }
        func part(_ range: NSRange?) -> String { range.map { partRange in text.substring(with: partRange) } ?? "" }
        let quotePrefix = part(ranges.quotePrefix)
        guard ranges.isListItem else {
            return ListLine(quotePrefix: quotePrefix, indentation: "", marker: "", spacing: "", taskStatus: nil, checkbox: "")
        }
        return ListLine(quotePrefix: quotePrefix, indentation: part(ranges.indentation), marker: part(ranges.marker), spacing: part(ranges.spacing),
                        taskStatus: ranges.taskStatus.flatMap { statusRange in part(statusRange).first }, checkbox: part(ranges.checkbox))
    }

    /// Whether `line` is a list item, quoted or not: `listLine(line)?.isListItem` without
    /// copying the line's parts.
    static func isListItem(_ line: String) -> Bool {
        let text = line as NSString
        return listMarker(in: text, range: NSRange(location: 0, length: text.length)) != nil
    }

    /// The marker of the list item that the part `range` of `line` is, or nil when it is no
    /// list item: the answer `listLineRanges(in:range:)` gives for `marker`, read by hand
    /// instead of by its pattern, because colors and the block walk ask it for every line.
    /// `MarkdownListSyntaxTests` holds the two to the same answers.
    static func listMarker(in line: NSString, range: NSRange) -> NSRange? {
        let end = NSMaxRange(range)
        func isSpaceOrTab(_ unit: UInt16) -> Bool { unit == space || unit == tab }
        var position = range.location
        // `(?:[ \t]*>[ \t]?)*`: quote markers, each after any spaces or tabs.
        while true {
            var afterSpaces = position
            while afterSpaces < end, isSpaceOrTab(line.character(at: afterSpaces)) { afterSpaces += 1 }
            guard afterSpaces < end, line.character(at: afterSpaces) == greaterThan else { break }
            position = afterSpaces + 1
            if position < end, isSpaceOrTab(line.character(at: position)) { position += 1 }
        }
        let afterQuotePrefix = position
        while position < end, isSpaceOrTab(line.character(at: position)) { position += 1 }
        guard position < end else { return nil }
        // `[-*+]` or one to nine ASCII digits and `.` or `)`.
        let markerStart = position
        let first = line.character(at: position)
        if first == hyphen || first == asterisk || first == plus {
            position += 1
        } else {
            while position < end, position - markerStart < 10, line.character(at: position) >= zero, line.character(at: position) <= nine { position += 1 }
            let digitCount = position - markerStart
            guard digitCount >= 1, digitCount <= 9, position < end,
                  line.character(at: position) == period || line.character(at: position) == closingParenthesis else { return nil }
            position += 1
        }
        let marker = NSRange(location: markerStart, length: position - markerStart)
        // `([ \t]+|$)`: whitespace after the marker, or the end of the line.
        guard position == end || isSpaceOrTab(line.character(at: position)) else { return nil }
        var afterSpacing = position
        while afterSpacing < end, isSpaceOrTab(line.character(at: afterSpacing)) { afterSpacing += 1 }
        if marker.length == 1, first == hyphen || first == asterisk, afterSpacing > position, afterSpacing < end, line.character(at: afterSpacing) == first,
           isThematicBreak(in: line, range: NSRange(location: afterQuotePrefix, length: end - afterQuotePrefix)) {
            return nil
        }
        return marker
    }

    /// `listLine` for the part `range` of `line`, which holds no line ending: the ranges of
    /// its parts, or nil for plain text.
    static func listLineRanges(in line: NSString, range: NSRange) -> ListLineRanges? {
        guard let match = listLinePattern.firstMatch(in: line as String, range: range) else { return nil }
        func group(_ index: Int) -> NSRange? {
            let groupRange = match.range(at: index)
            return groupRange.location == NSNotFound ? nil : groupRange
        }
        let quotePrefix = group(1) ?? NSRange(location: range.location, length: 0)
        let afterQuotePrefix = NSMaxRange(quotePrefix)
        let noMarker = ListLineRanges(quotePrefix: quotePrefix, indentation: NSRange(location: afterQuotePrefix, length: 0),
                                      marker: NSRange(location: afterQuotePrefix, length: 0), spacing: NSRange(location: afterQuotePrefix, length: 0),
                                      checkbox: nil, taskStatus: nil)
        guard let marker = group(3), marker.length > 0, let indentation = group(2) else {
            return quotePrefix.length > 0 ? noMarker : nil
        }
        // Only a `-` or `*` followed by the same character can start a thematic break, so the
        // second pattern runs for those lines alone.
        let markerCharacter = line.character(at: marker.location)
        if let spacing = group(4), marker.length == 1, markerCharacter == hyphen || markerCharacter == asterisk,
           NSMaxRange(spacing) < NSMaxRange(range), line.character(at: NSMaxRange(spacing)) == markerCharacter,
           isThematicBreak(in: line, range: NSRange(location: afterQuotePrefix, length: NSMaxRange(range) - afterQuotePrefix)) {
            return quotePrefix.length > 0 ? noMarker : nil
        }
        let spacing = group(4) ?? NSRange(location: NSMaxRange(marker), length: 0)
        let taskStatus = group(6)
        let checkbox = taskStatus.flatMap { _ in group(5) }.map { boxRange in
            NSRange(location: boxRange.location, length: (group(7).map(NSMaxRange) ?? NSMaxRange(boxRange)) - boxRange.location)
        }
        return ListLineRanges(quotePrefix: quotePrefix, indentation: indentation, marker: marker, spacing: spacing, checkbox: checkbox, taskStatus: taskStatus)
    }

    /// Whether `line` (without its line ending or quote markers) is a thematic break such as
    /// `- - -`, `***` or `___`: three or more of one of those characters, spaces or tabs
    /// between and after them, and at most three spaces before them.
    public static func isThematicBreak(_ line: String) -> Bool {
        thematicBreakPattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    /// `isThematicBreak` for the part `range` of `line`, without copying it.
    static func isThematicBreak(in line: NSString, range: NSRange) -> Bool {
        thematicBreakPattern.firstMatch(in: line as String, range: range) != nil
    }
}

/// The constant patterns of `MarkdownListSyntax`; `StaticPatternTests` compiles every case.
enum MarkdownListSyntaxPattern: String, StaticPatternSet {
    case listLine = #"^((?:[ \t]*>[ \t]?)*)([ \t]*)(?:([-*+]|[0-9]{1,9}[.)])([ \t]+|$)(?:(\[(.)\])( |$))?)?"#
    case thematicBreak = #"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#
}
