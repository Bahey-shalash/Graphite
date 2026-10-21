/**
 * File: MarkdownSectionUnits.swift
 * --------------------------------
 * Layer: Core
 * Description: A Markdown section that is one list, table or code block, divided into its items, rows or lines, and
 *              the Markdown of any run of them, so a printed page can end between two of them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import Foundation
import Markdown

/// One list, table or code block divided into the parts a page may end between. Each run
/// of parts is Markdown of its own that draws as that run of the whole: a table's runs
/// repeat its header, a code block's its fences, and an ordered list's runs go on with
/// its numbers.
public struct MarkdownSectionUnits: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case listItems, tableRows, codeLines
    }

    public let kind: Kind
    private let lines: [String]
    /// Lines every run repeats before its parts: a table's header and delimiter row, a
    /// code block's opening fence.
    private let leadingLines: Range<Int>
    /// Lines every run repeats after its parts: a code block's closing fence.
    private let trailingLines: Range<Int>
    private let unitLines: [Range<Int>]
    /// The number of an ordered list's first item; nil for anything else.
    private let orderedListStart: Int?

    private static let orderedListMarkerPattern = MarkdownSectionUnitsPattern.orderedListMarker.compiled()

    public var unitCount: Int { unitLines.count }

    /// The section's parts, or nil when it is not one list, table or code block of at
    /// least two parts.
    public static func units(of markdown: String) -> MarkdownSectionUnits? {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.count > 1, let document = BoundedMarkdownParser.document(parsing: markdown), document.childCount == 1,
              let child = document.child(at: 0) else { return nil }
        let units: MarkdownSectionUnits?
        switch child {
        case let list as ListItemContainer:
            units = listUnits(list, lines: lines)
        case let table as Table:
            units = tableUnits(table, lines: lines)
        case is CodeBlock:
            units = codeUnits(lines: lines)
        default:
            units = nil
        }
        guard let units, units.unitCount > 1 else { return nil }
        return units
    }

    /// The Markdown that draws the parts in `units`, with what every run repeats.
    public func markdown(forUnits units: Range<Int>) -> String {
        let clampedUnits = units.clamped(to: unitLines.indices)
        guard let firstUnit = clampedUnits.first, let lastUnit = clampedUnits.last else { return "" }
        var runLines = Array(lines[leadingLines])
        var partLines = Array(lines[unitLines[firstUnit].lowerBound..<unitLines[lastUnit].upperBound])
        if let orderedListStart, firstUnit > 0, let firstLine = partLines.first {
            partLines[0] = Self.renumbered(firstLine, to: orderedListStart + firstUnit)
        }
        runLines += partLines
        runLines += lines[trailingLines]
        return runLines.joined(separator: "\n")
    }

    private static func listUnits(_ list: ListItemContainer, lines: [String]) -> MarkdownSectionUnits? {
        let itemStartLines = Array(list.listItems.compactMap { item in item.range.map { range in range.lowerBound.line - 1 } })
        guard itemStartLines.count == Array(list.listItems).count, let firstLine = itemStartLines.first,
              itemStartLines.allSatisfy({ line in lines.indices.contains(line) }) else { return nil }
        let unitLines = zip(itemStartLines, itemStartLines.dropFirst() + [lines.count]).map { start, end in start..<end }
        guard unitLines.allSatisfy({ range in !range.isEmpty }) else { return nil }
        let start = (list as? OrderedList).map { orderedList in Int(orderedList.startIndex) }
        return MarkdownSectionUnits(kind: .listItems, lines: lines, leadingLines: 0..<firstLine, trailingLines: lines.count..<lines.count,
                                    unitLines: unitLines, orderedListStart: start)
    }

    private static func tableUnits(_ table: Table, lines: [String]) -> MarkdownSectionUnits? {
        let rowLines = Array(table.body.rows.compactMap { row in row.range.map { range in range.lowerBound.line - 1 } })
        guard rowLines.count == table.body.childCount, let firstRowLine = rowLines.first,
              rowLines.allSatisfy({ line in lines.indices.contains(line) }) else { return nil }
        let unitLines = zip(rowLines, rowLines.dropFirst() + [lines.count]).map { start, end in start..<end }
        return MarkdownSectionUnits(kind: .tableRows, lines: lines, leadingLines: 0..<firstRowLine, trailingLines: lines.count..<lines.count,
                                    unitLines: unitLines, orderedListStart: nil)
    }

    private static func codeUnits(lines: [String]) -> MarkdownSectionUnits? {
        guard let (fence, _) = MarkdownFenceSyntax.opening(lines[0].trimmingCharacters(in: .whitespaces)) else {
            // Indented code: every run of its lines is indented code too.
            return MarkdownSectionUnits(kind: .codeLines, lines: lines, leadingLines: 0..<0, trailingLines: lines.count..<lines.count,
                                        unitLines: lines.indices.map { line in line..<(line + 1) }, orderedListStart: nil)
        }
        let lastLine = lines.count - 1
        let hasClosingFence = lastLine > 0 && MarkdownFenceSyntax.closes(fence, lines[lastLine].trimmingCharacters(in: .whitespaces))
        let codeEnd = hasClosingFence ? lastLine : lines.count
        guard codeEnd > 1 else { return nil }
        return MarkdownSectionUnits(kind: .codeLines, lines: lines, leadingLines: 0..<1, trailingLines: codeEnd..<lines.count,
                                    unitLines: (1..<codeEnd).map { line in line..<(line + 1) }, orderedListStart: nil)
    }

    /// An ordered list item's line with its number replaced, so a run that starts inside the
    /// list counts on from where the run before it ended.
    private static func renumbered(_ line: String, to number: Int) -> String {
        let fullRange = NSRange(location: 0, length: (line as NSString).length)
        guard let match = orderedListMarkerPattern.firstMatch(in: line, range: fullRange) else { return line }
        return (line as NSString).replacingCharacters(in: match.range(at: 2), with: String(number))
    }
}

/// The constant patterns of `MarkdownSectionUnits`; `StaticPatternTests` compiles every case.
enum MarkdownSectionUnitsPattern: String, StaticPatternSet {
    /// An ordered list item's indent, number and delimiter.
    case orderedListMarker = #"^([ \t]*)([0-9]{1,9})([.)])"#
}
