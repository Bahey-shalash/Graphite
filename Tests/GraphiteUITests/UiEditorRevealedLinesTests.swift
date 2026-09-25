import XCTest
import GraphiteCore
@testable import GraphiteUI

/// What moving the cursor restyles, and finding the rendered block under a line (P7, P3).
final class UiEditorRevealedLinesTests: XCTestCase {
    private func lineRange(_ number: Int, in source: NSString) -> NSRange {
        var lineStart = 0
        for _ in 0..<number { lineStart = NSMaxRange(source.lineRange(for: NSRange(location: lineStart, length: 0))) }
        return source.lineRange(for: NSRange(location: lineStart, length: 0))
    }

    private let source = (0..<100).map { index in "Line \(index) with **bold**" }.joined(separator: "\n") as NSString

    func testFarJumpRestylesOnlyBothLinesAndTheLinesAfterThem() {
        let ranges = RevealedLinesChange.restyledRanges(from: lineRange(2, in: source), to: lineRange(80, in: source), in: source)
        XCTAssertEqual(ranges, [NSUnionRange(lineRange(2, in: source), lineRange(3, in: source)),
                                NSUnionRange(lineRange(80, in: source), lineRange(81, in: source))])
    }

    /// Markup that starts right after the revealed lines shows, so moving up one line
    /// must conceal the line after the old one again.
    func testMovingUpOneLineRestylesTheLineAfterTheOldOne() {
        let ranges = RevealedLinesChange.restyledRanges(from: lineRange(5, in: source), to: lineRange(4, in: source), in: source)
        XCTAssertEqual(ranges, [NSUnionRange(lineRange(4, in: source), lineRange(6, in: source))])
    }

    func testExtendingASelectionRestylesOnlyTheLinesItGained() {
        let previousRange = NSUnionRange(lineRange(10, in: source), lineRange(40, in: source))
        let newRange = NSUnionRange(lineRange(10, in: source), lineRange(41, in: source))
        let ranges = RevealedLinesChange.restyledRanges(from: previousRange, to: newRange, in: source)
        XCTAssertEqual(ranges, [NSUnionRange(lineRange(41, in: source), lineRange(42, in: source))])

        let shrunkFromTheTop = NSUnionRange(lineRange(12, in: source), lineRange(40, in: source))
        XCTAssertEqual(RevealedLinesChange.restyledRanges(from: previousRange, to: shrunkFromTheTop, in: source),
                       [NSUnionRange(lineRange(10, in: source), lineRange(11, in: source))])
    }

    func testRevealingAndConcealingRestyleOneRange() {
        let revealed = lineRange(99, in: source)
        XCTAssertEqual(RevealedLinesChange.restyledRanges(from: nil, to: revealed, in: source), [revealed])
        XCTAssertEqual(RevealedLinesChange.restyledRanges(from: revealed, to: nil, in: source), [revealed])
        XCTAssertEqual(RevealedLinesChange.restyledRanges(from: nil, to: nil, in: source), [])
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
