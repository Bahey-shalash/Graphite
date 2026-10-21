import Foundation

/// Where a table starts, read from its first two lines: a header row with a pipe over a
/// delimiter row, as GitHub-flavored Markdown and Obsidian read tables, outer pipes optional.
enum MarkdownTableSyntax {
    private static let pipe = UInt16(UInt8(ascii: "|"))
    private static let hyphen = UInt16(UInt8(ascii: "-"))
    /// The characters a delimiter row is written with.
    private static let delimiterRowUnits = Set("|-: \t".utf16)

    /// A table's first two lines: a header row with a pipe, over a delimiter row. Without
    /// a leading pipe, the delimiter row needs one too, so text over a `---` rule is no table.
    static func startsTable(header trimmedHeader: String, delimiter: String) -> Bool {
        guard isDelimiterRow(delimiter) else { return false }
        if trimmedHeader.hasPrefix("|") { return true }
        return trimmedHeader.contains("|") && delimiter.contains("|")
    }

    /// `startsTable` for lines read as UTF-16 code units, each without its indentation and
    /// trailing spaces, for a caller that holds the table's units.
    static func startsTable<HeaderUnits: Collection<UInt16>, DelimiterUnits: Collection<UInt16>>(
        trimmedHeaderUnits: HeaderUnits, trimmedDelimiterUnits: DelimiterUnits) -> Bool {
        guard isDelimiterRow(trimmedUnits: trimmedDelimiterUnits) else { return false }
        if trimmedHeaderUnits.first == pipe { return true }
        return trimmedHeaderUnits.contains(pipe) && trimmedDelimiterUnits.contains(pipe)
    }

    /// A delimiter row has only pipes, dashes, colons and spaces, with a dash among them.
    static func isDelimiterRow(_ line: String) -> Bool {
        isDelimiterRow(trimmedUnits: line.trimmingCharacters(in: .whitespaces).utf16)
    }

    /// `isDelimiterRow` for a line read as UTF-16 code units, without its indentation and
    /// trailing spaces.
    static func isDelimiterRow<Units: Collection<UInt16>>(trimmedUnits: Units) -> Bool {
        trimmedUnits.contains(hyphen) && trimmedUnits.allSatisfy { unit in delimiterRowUnits.contains(unit) }
    }
}
