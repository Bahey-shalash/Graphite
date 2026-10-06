import XCTest
import GraphiteCore
@testable import GraphiteUI

/// Which lines a moving selection looks at again, and finding the rendered block under a
/// line (P7, P3).
final class UiEditorRevealedLinesTests: XCTestCase {
    private func lineRange(_ number: Int, in source: NSString) -> NSRange {
        var lineStart = 0
        for _ in 0..<number { lineStart = NSMaxRange(source.lineRange(for: NSRange(location: lineStart, length: 0))) }
        return source.lineRange(for: NSRange(location: lineStart, length: 0))
    }

    private let source = (0..<100).map { index in "Line \(index) with **bold**" }.joined(separator: "\n") as NSString

    private func cursor(inLine number: Int) -> RevealedMarkup {
        RevealedMarkup(selection: NSRange(location: lineRange(number, in: source).location + 3, length: 0), in: source)
    }

    private func selection(fromLine firstNumber: Int, throughLine lastNumber: Int) -> RevealedMarkup {
        RevealedMarkup(selection: NSUnionRange(lineRange(firstNumber, in: source), lineRange(lastNumber, in: source)), in: source)
    }

    func testFarJumpLooksOnlyAtBothLines() {
        let lines = RevealedMarkupChange.examinedLines(from: cursor(inLine: 2), to: cursor(inLine: 80), in: source)
        XCTAssertEqual(lines, [lineRange(2, in: source), lineRange(80, in: source)])
    }

    func testMovingUpOneLineLooksAtBothLines() {
        let lines = RevealedMarkupChange.examinedLines(from: cursor(inLine: 5), to: cursor(inLine: 4), in: source)
        XCTAssertEqual(lines, [NSUnionRange(lineRange(4, in: source), lineRange(5, in: source))])
    }

    func testMovingWithinALineLooksAtThatLineOnly() {
        let movedCursor = RevealedMarkup(selection: NSRange(location: lineRange(7, in: source).location + 9, length: 0), in: source)
        XCTAssertEqual(RevealedMarkupChange.examinedLines(from: cursor(inLine: 7), to: movedCursor, in: source), [lineRange(7, in: source)])
        XCTAssertEqual(RevealedMarkupChange.examinedLines(from: movedCursor, to: movedCursor, in: source), [])
    }

    /// A selection that ends where a line starts touches an element starting there, so
    /// that line is looked at with the lines the selection gained.
    func testExtendingASelectionLooksOnlyAtTheLinesAroundTheEndThatMoved() {
        let previousMarkup = selection(fromLine: 10, throughLine: 40)
        let lines = RevealedMarkupChange.examinedLines(from: previousMarkup, to: selection(fromLine: 10, throughLine: 41), in: source)
        XCTAssertEqual(lines, [NSUnionRange(lineRange(41, in: source), lineRange(42, in: source))])

        let shrunkFromTheTop = RevealedMarkupChange.examinedLines(from: previousMarkup, to: selection(fromLine: 12, throughLine: 40), in: source)
        XCTAssertEqual(shrunkFromTheTop, [NSUnionRange(lineRange(10, in: source), lineRange(12, in: source))])
    }

    func testRevealingAndConcealingLookAtTheCursorsLine() {
        let revealed = lineRange(99, in: source)
        XCTAssertEqual(RevealedMarkupChange.examinedLines(from: nil, to: cursor(inLine: 99), in: source), [revealed])
        XCTAssertEqual(RevealedMarkupChange.examinedLines(from: cursor(inLine: 99), to: nil, in: source), [revealed])
        XCTAssertEqual(RevealedMarkupChange.examinedLines(from: nil, to: nil, in: source), [])
    }

    /// Whatever the two selections, every span whose markup starts or stops showing is on
    /// an examined line.
    func testEveryChangeOfShownMarkupIsOnAnExaminedLine() {
        let note = "# Heading with **bold**\n[[Link]] at the start\n- item with ==mark== and `code`\n\nplain\n**bold** end **last**" as NSString
        let spans = MarkdownStyleScanner.spans(in: note, range: NSRange(location: 0, length: note.length))
        var selections: [NSRange] = []
        for location in stride(from: 0, through: note.length, by: 3) {
            for length in [0, 1, 7, 30] where location + length <= note.length { selections.append(NSRange(location: location, length: length)) }
        }
        let markups: [RevealedMarkup?] = [nil] + selections.map { selection in RevealedMarkup(selection: selection, in: note) }
        for previousMarkup in markups {
            for newMarkup in markups {
                let lines = RevealedMarkupChange.examinedLines(from: previousMarkup, to: newMarkup, in: note)
                for span in spans where (previousMarkup?.shows(span) ?? false) != (newMarkup?.shows(span) ?? false) {
                    XCTAssertTrue(lines.contains { examinedLines in NSLocationInRange(span.range.location, examinedLines) },
                                  "\(note.substring(with: span.range)) at \(span.range) from \(String(describing: previousMarkup?.selection)) to \(String(describing: newMarkup?.selection))")
                }
            }
        }
    }

    func testBlockUnderALineIsFoundInSortedBlocks() {
        let blockRanges = [NSRange(location: 0, length: 10), NSRange(location: 20, length: 5), NSRange(location: 25, length: 30)]
        let foundIndices = [0, 9, 10, 19, 20, 24, 25, 54, 55, 1_000].map { location in
            LivePreviewBlockLookup.index(ofElementContaining: location, in: blockRanges) { range in range }
        }
        XCTAssertEqual(foundIndices, [0, 0, nil, nil, 1, 1, 2, 2, nil, nil])
        XCTAssertNil(LivePreviewBlockLookup.index(ofElementContaining: 3, in: [NSRange]()) { range in range })
    }

    /// The lookup answers as a scan through the scanner's blocks would.
    func testLookupMatchesAScanOverScannedBlocks() {
        let note = (0..<40).map { index in
            index % 3 == 0 ? "| a | b |\n| - | - |\n| \(index) | 2 |\n" : "Paragraph \(index)\n\n---\n"
        }.joined(separator: "\n") as NSString
        let blocks = LivePreviewBlockScanner.blocks(in: note)
        XCTAssertGreaterThan(blocks.count, 20)
        for location in 0...note.length {
            let scannedIndex = blocks.firstIndex { block in NSLocationInRange(location, block.range) }
            XCTAssertEqual(LivePreviewBlockLookup.index(ofElementContaining: location, in: blocks) { block in block.range }, scannedIndex, "at \(location)")
        }
    }
}
