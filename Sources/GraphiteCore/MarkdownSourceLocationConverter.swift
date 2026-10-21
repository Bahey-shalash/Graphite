import Foundation
import Markdown

/// Converts swift-markdown source locations into UTF-16 offsets of the parsed text.
///
/// cmark reports a 1-based line, ending lines at "\n", "\r\n" and a lone "\r", and a
/// 1-based column in UTF-8 bytes. Splitting the text into Characters instead would keep
/// every line of a CRLF note on one line, because "\r\n" is a single Character.
///
/// Block nodes have columns counted from the start of their line. Inline nodes do not.
/// cmark joins a paragraph's lines into one text, keeping each continuation line from a
/// start that depends on its containers (after the indentation of a regular line, but
/// from the last matched container of a lazy one, indentation included). Only the line
/// breaks it parses as breaks, and those inside code spans and HTML, start a new line
/// number; there, columns restart at the kept start of the line, plus the paragraph's
/// first column. A backslash hard break and a break inside a link destination or title
/// leave the line number as it is, and the columns run on across the break.
///
/// So each paragraph's inline positions are replayed in source order: a new line number
/// belongs to the line after the one the positions so far reached, and the node right
/// after a line break, which starts where that line's text starts, calibrates its
/// columns. A column past the end of its line runs on into the following lines. A line
/// with no such node (one continuing a code span or HTML) is taken to be kept from its
/// text, as a regular continuation line is. Lines cmark drops from the start of a
/// paragraph, its link reference definitions, are not modeled; the ranges they misplace
/// are caught by checking the text at each range (see MarkdownSemantics.parse).
struct MarkdownSourceLocationConverter {
    /// A paragraph or heading, and its inline nodes' positions.
    private struct InlineContainer {
        let range: SourceRange
        let quoteDepth: Int
        var positions: [InlinePosition] = []
        /// For each reported line number, the line it is and where its columns start.
        var originByReportedLine: [Int: LineOrigin] = [:]
        /// For each reported line number whose columns run past its line, the following
        /// lines they reach, found once and in order, so a long run of hard breaks stays linear.
        var spillStepsByReportedLine: [Int: [SpillStep]] = [:]

        var firstColumn: Int { range.lowerBound.column }
    }

    private struct InlinePosition {
        let location: SourceLocation
        let columnRule: ColumnRule
        /// The node follows a line break, so it starts where its line's text starts.
        let startsLineText: Bool
    }

    /// How a reported column counts bytes on its line.
    private enum ColumnRule {
        /// From the line's origin, where the paragraph's first column falls.
        case fromOrigin
        /// The end of a code span or HTML tag that spans lines: cmark counts it from the
        /// kept start of its last line, without the paragraph's first column (for code,
        /// swift-markdown then adds the closing backticks).
        case codeEndFromKeptStart, htmlEndFromKeptStart
    }

    private struct LineOrigin {
        let lineIndex: Int
        /// The byte where the paragraph's first column falls on this line.
        let byte: Int
    }

    /// A column whose byte on its origin line would be at least `minimumByte` lands on
    /// `lineIndex`, `shift` bytes further on.
    private struct SpillStep {
        let lineIndex: Int
        let minimumByte: Int
        let shift: Int
    }

    private static let lineFeed = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")

    private let bytes: [UInt8]
    /// UTF-8 offset where each line starts.
    private var lineStarts: [Int] = [0]
    /// UTF-8 offset where each line's text ends, before its line break.
    private var lineContentEnds: [Int] = []
    private var containers: [InlineContainer] = []
    /// The last converted UTF-8 offset and its UTF-16 offset. Ranges arrive in document
    /// order, so walking on from the previous answer keeps a whole parse linear instead of
    /// decoding every line's prefix again for each node on it.
    private var cursorByte = 0
    private var cursorUTF16 = 0

    init(_ text: String) {
        bytes = Array(text.utf8)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            guard byte == Self.lineFeed || byte == Self.carriageReturn else {
                index += 1
                continue
            }
            lineContentEnds.append(index)
            let isCRLF = byte == Self.carriageReturn && index + 1 < bytes.count && bytes[index + 1] == Self.lineFeed
            index += isCRLF ? 2 : 1
            lineStarts.append(index)
        }
        lineContentEnds.append(bytes.count)
    }

    /// Starts collecting the inline positions of a paragraph or heading; returns its index.
    mutating func addInlineContainer(_ block: any Markup) -> Int? {
        guard let range = block.range else { return nil }
        var quoteDepth = 0
        var ancestor = block.parent
        while let current = ancestor {
            if current is BlockQuote { quoteDepth += 1 }
            ancestor = current.parent
        }
        containers.append(InlineContainer(range: range, quoteDepth: quoteDepth))
        return containers.count - 1
    }

    mutating func recordInlineRange(_ range: SourceRange, of role: SourceRangeRole?, startsLineText: Bool, inContainer containerIndex: Int) {
        containers[containerIndex].positions.append(InlinePosition(location: range.lowerBound, columnRule: .fromOrigin, startsLineText: startsLineText))
        containers[containerIndex].positions.append(InlinePosition(location: range.upperBound, columnRule: Self.endColumnRule(of: range, role: role), startsLineText: false))
    }

    private static func endColumnRule(of range: SourceRange, role: SourceRangeRole?) -> ColumnRule {
        guard range.upperBound.line > range.lowerBound.line else { return .fromOrigin }
        switch role {
        case .inlineCode: return .codeEndFromKeptStart
        case .inlineHTML: return .htmlEndFromKeptStart
        default: return .fromOrigin
        }
    }

    /// Replays every paragraph's positions in source order to find its lines' origins.
    mutating func resolveInlineLines() {
        for containerIndex in containers.indices {
            let firstColumn = containers[containerIndex].firstColumn
            let quoteDepth = containers[containerIndex].quoteDepth
            var reportedLine = containers[containerIndex].range.lowerBound.line
            let firstLineIndex = clampedLineIndex(reportedLine)
            containers[containerIndex].originByReportedLine[reportedLine] = LineOrigin(lineIndex: firstLineIndex, byte: lineStarts[firstLineIndex] + firstColumn - 1)
            var lastLineIndex = firstLineIndex
            let orderedPositions = containers[containerIndex].positions.sorted { first, second in
                (first.location.line, first.location.column, first.startsLineText ? 0 : 1) < (second.location.line, second.location.column, second.startsLineText ? 0 : 1)
            }
            containers[containerIndex].positions = []
            for position in orderedPositions {
                if position.location.line > reportedLine {
                    let lineIndex = min(lastLineIndex + position.location.line - reportedLine, lineStarts.count - 1)
                    let textStart = textStart(lineIndex: lineIndex, quoteDepth: quoteDepth)
                    let originByte = position.startsLineText ? textStart - (position.location.column - firstColumn) : textStart
                    reportedLine = position.location.line
                    containers[containerIndex].originByReportedLine[reportedLine] = LineOrigin(lineIndex: lineIndex, byte: originByte)
                }
                lastLineIndex = max(lastLineIndex, byteAndLineIndex(of: position, inContainer: containerIndex).lineIndex)
            }
        }
    }

    /// `containerIndex` is the paragraph or heading holding an inline node, or nil for a
    /// block, or for inline nodes such as table cells whose columns count from the line start.
    mutating func utf16Range(of range: SourceRange, role: SourceRangeRole?, containerIndex: Int?) -> NSRange {
        let startByte: Int, endByte: Int
        if let containerIndex {
            startByte = byteAndLineIndex(of: InlinePosition(location: range.lowerBound, columnRule: .fromOrigin, startsLineText: false), inContainer: containerIndex).byte
            endByte = byteAndLineIndex(of: InlinePosition(location: range.upperBound, columnRule: Self.endColumnRule(of: range, role: role), startsLineText: false), inContainer: containerIndex).byte
        } else {
            startByte = absoluteByte(of: range.lowerBound)
            endByte = absoluteByte(of: range.upperBound)
        }
        let start = utf16Offset(ofByte: startByte)
        let end = utf16Offset(ofByte: max(startByte, endByte))
        return NSRange(location: start, length: end - start)
    }

    /// The whole lines of a paragraph or heading.
    mutating func utf16Range(ofContainer containerIndex: Int) -> NSRange {
        let range = containers[containerIndex].range
        let startByte = lineStarts[clampedLineIndex(range.lowerBound.line)]
        let endByte = lineContentEnds[clampedLineIndex(range.upperBound.line)]
        let start = utf16Offset(ofByte: startByte)
        return NSRange(location: start, length: utf16Offset(ofByte: endByte) - start)
    }

    private func clampedLineIndex(_ line: Int) -> Int {
        min(max(line - 1, 0), lineStarts.count - 1)
    }

    private func absoluteByte(of location: SourceLocation) -> Int {
        let lineIndex = clampedLineIndex(location.line)
        return lineStarts[lineIndex] + min(max(location.column - 1, 0), lineContentEnds[lineIndex] - lineStarts[lineIndex])
    }

    private mutating func byteAndLineIndex(of position: InlinePosition, inContainer containerIndex: Int) -> (byte: Int, lineIndex: Int) {
        let firstColumn = containers[containerIndex].firstColumn
        let quoteDepth = containers[containerIndex].quoteDepth
        let reportedLine = position.location.line
        let origin = containers[containerIndex].originByReportedLine[reportedLine]
            ?? LineOrigin(lineIndex: clampedLineIndex(reportedLine), byte: textStart(lineIndex: clampedLineIndex(reportedLine), quoteDepth: quoteDepth))
        let byte = switch position.columnRule {
        case .fromOrigin: origin.byte + position.location.column - firstColumn
        case .codeEndFromKeptStart: origin.byte + position.location.column - 1
        case .htmlEndFromKeptStart: origin.byte + position.location.column
        }
        guard byte > lineContentEnds[origin.lineIndex], origin.lineIndex + 1 < lineStarts.count else {
            return (clampedByte(byte, lineIndex: origin.lineIndex), origin.lineIndex)
        }
        // Past its line's break, a column runs on into the next line's kept text. cmark
        // keeps every line break, "\r\n" included, as one byte.
        var steps = containers[containerIndex].spillStepsByReportedLine.removeValue(forKey: reportedLine) ?? [SpillStep(lineIndex: origin.lineIndex, minimumByte: .min, shift: 0)]
        while let lastStep = steps.last, lastStep.lineIndex + 1 < lineStarts.count, byte + lastStep.shift > lineContentEnds[lastStep.lineIndex] {
            let nextLineIndex = lastStep.lineIndex + 1
            let shift = lastStep.shift + textStart(lineIndex: nextLineIndex, quoteDepth: quoteDepth) - lineContentEnds[lastStep.lineIndex] - 1
            steps.append(SpillStep(lineIndex: nextLineIndex, minimumByte: lineContentEnds[lastStep.lineIndex] - lastStep.shift + 1, shift: shift))
        }
        // The last step whose minimum byte `byte` reaches.
        var lowerIndex = 0, upperIndex = steps.count
        while lowerIndex < upperIndex {
            let middleIndex = (lowerIndex + upperIndex) / 2
            if steps[middleIndex].minimumByte <= byte { lowerIndex = middleIndex + 1 } else { upperIndex = middleIndex }
        }
        let step = steps[max(lowerIndex - 1, 0)]
        containers[containerIndex].spillStepsByReportedLine[reportedLine] = steps
        return (clampedByte(byte + step.shift, lineIndex: step.lineIndex), step.lineIndex)
    }

    private func clampedByte(_ byte: Int, lineIndex: Int) -> Int {
        min(max(byte, lineStarts[lineIndex]), lineContentEnds[lineIndex])
    }

    /// Where a continuation line's text starts: after up to `quoteDepth` quote markers (a
    /// lazy continuation line may omit them) and the spaces and tabs around them.
    private func textStart(lineIndex: Int, quoteDepth: Int) -> Int {
        var position = lineStarts[lineIndex]
        var remainingQuoteMarkers = quoteDepth
        while position < lineContentEnds[lineIndex] {
            let byte = bytes[position]
            if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") {
                position += 1
            } else if byte == UInt8(ascii: ">") && remainingQuoteMarkers > 0 {
                remainingQuoteMarkers -= 1
                position += 1
            } else {
                break
            }
        }
        return position
    }

    /// Counts UTF-16 units by lead bytes: every scalar has one lead byte, and scalars of
    /// four UTF-8 bytes need a surrogate pair.
    private mutating func utf16Offset(ofByte targetByte: Int) -> Int {
        while cursorByte < targetByte {
            cursorUTF16 += Self.utf16Length(startingWith: bytes[cursorByte])
            cursorByte += 1
        }
        while cursorByte > targetByte {
            cursorByte -= 1
            cursorUTF16 -= Self.utf16Length(startingWith: bytes[cursorByte])
        }
        return cursorUTF16
    }

    private static func utf16Length(startingWith byte: UInt8) -> Int {
        if byte & 0b1100_0000 == 0b1000_0000 { return 0 }
        return byte >= 0b1111_0000 ? 2 : 1
    }
}
