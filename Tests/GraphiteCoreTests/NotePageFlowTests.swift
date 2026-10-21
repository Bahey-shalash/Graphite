/**
 * File: NotePageFlowTests.swift
 * -----------------------------
 * Layer: Tests
 * Description: Where NotePageFlow puts a note's blocks on pages: breaks between blocks, headings kept with what
 *              follows, lists and tables divided between items, tall blocks cut only in gaps, pictures scaled.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import XCTest
@testable import GraphiteCore

final class NotePageFlowTests: XCTestCase {
    /// Blocks whose parts have the given heights, drawn with `header` above any run of them,
    /// and whose gaps between lines are at `cuts`.
    private struct Sizes {
        var unitHeights: [[Double]]
        var headers: [Double] = []
        var cuts: [[Double]] = []

        var measurements: NotePageFlow.Measurements {
            NotePageFlow.Measurements(height: { blockIndex, units in
                (headers.indices.contains(blockIndex) ? headers[blockIndex] : 0) + unitHeights[blockIndex][units].reduce(0, +)
            }, cutOffsets: { blockIndex, _ in cuts.indices.contains(blockIndex) ? cuts[blockIndex] : [] })
        }
    }

    private func block(units: Int = 1, heading: Bool = false, picture: Bool = false) -> NotePageFlow.Block {
        NotePageFlow.Block(unitCount: units, spacingBefore: 10, keepsWithNext: heading, scalesToFit: picture)
    }

    func testBlocksThatFitStayOnOnePageWithTheirSpacing() async {
        let sizes = Sizes(unitHeights: [[100], [200], [50]])
        let placements = await NotePageFlow.placements(of: [block(), block(), block()], pageHeight: 500, measurements: sizes.measurements)
        XCTAssertEqual(placements.map(\.pageIndex), [0, 0, 0])
        XCTAssertEqual(placements.map(\.top), [0, 110, 320])
    }

    func testABlockThatDoesNotFitStartsTheNextPageWhole() async {
        let sizes = Sizes(unitHeights: [[300], [250]])
        let placements = await NotePageFlow.placements(of: [block(), block()], pageHeight: 500, measurements: sizes.measurements)
        XCTAssertEqual(placements.map(\.pageIndex), [0, 1])
        XCTAssertEqual(placements[1].top, 0, "No spacing above the first block of a page.")
        XCTAssertEqual(placements[1].sliceTop, 0)
        XCTAssertEqual(placements[1].sliceBottom, 250, "Drawn whole, not cut.")
    }

    func testAHeadingIsNeverLastOnAPage() async {
        let sizes = Sizes(unitHeights: [[400], [40], [100]])
        let placements = await NotePageFlow.placements(of: [block(), block(heading: true), block()], pageHeight: 500, measurements: sizes.measurements)
        XCTAssertEqual(placements.map(\.pageIndex), [0, 1, 1], "The heading fits after the first block, the paragraph does not; both move.")
    }

    func testAHeadingNeedsOnlyTheFirstItemOfADividedBlockOnItsPage() async {
        let sizes = Sizes(unitHeights: [[300], [40], [30, 30, 30, 30, 30, 30]])
        let placements = await NotePageFlow.placements(of: [block(), block(heading: true), block(units: 6)], pageHeight: 500, measurements: sizes.measurements)
        XCTAssertEqual(placements[1].pageIndex, 0, "The heading stays: the list's first items fit under it.")
        XCTAssertEqual(placements[2].pageIndex, 0)
        XCTAssertEqual(placements[2].units, 0..<4, "300 + 10 + 40 + 10 + 4 × 30 = 480.")
        XCTAssertEqual(placements[3].units, 4..<6)
        XCTAssertEqual(placements[3].pageIndex, 1)
    }

    func testHeadingsInARowStayWithTheTextAfterThem() async {
        let sizes = Sizes(unitHeights: [[380], [40], [30], [100]])
        let blocks = [block(), block(heading: true), block(heading: true), block()]
        let placements = await NotePageFlow.placements(of: blocks, pageHeight: 500, measurements: sizes.measurements)
        XCTAssertEqual(placements.map(\.pageIndex), [0, 1, 1, 1])
    }

    func testAListIsDividedBetweenItemsToFillThePage() async {
        let sizes = Sizes(unitHeights: [[300], Array(repeating: 40, count: 10)])
        let placements = await NotePageFlow.placements(of: [block(), block(units: 10)], pageHeight: 500, measurements: sizes.measurements)
        XCTAssertEqual(placements.count, 3)
        XCTAssertEqual(placements[1].units, 0..<4, "300 + 10 + 4 × 40 = 470 fits, a fifth item would not.")
        XCTAssertEqual(placements[1].pageIndex, 0)
        XCTAssertEqual(placements[2].units, 4..<10)
        XCTAssertEqual(placements[2].pageIndex, 1)
        XCTAssertEqual(placements[2].top, 0)
    }

    func testATableRepeatsItsHeaderOnEachPageItSpans() async {
        let sizes = Sizes(unitHeights: [Array(repeating: 50, count: 20)], headers: [30])
        let placements = await NotePageFlow.placements(of: [block(units: 20)], pageHeight: 500, measurements: sizes.measurements)
        XCTAssertEqual(placements.map(\.units), [0..<9, 9..<18, 18..<20], "30 + 9 × 50 = 480 per page.")
        XCTAssertTrue(placements.allSatisfy { placement in placement.height <= 500 })
    }

    func testATextTallerThanAPageIsCutInItsLowestGapThatFits() async {
        let sizes = Sizes(unitHeights: [[1_100]], cuts: [[180, 470, 520, 960, 1_050]])
        let placements = await NotePageFlow.placements(of: [block()], pageHeight: 500, measurements: sizes.measurements)
        XCTAssertEqual(placements.map(\.sliceTop), [0, 470, 960])
        XCTAssertEqual(placements.map(\.sliceBottom), [470, 960, 1_100])
        XCTAssertEqual(placements.map(\.pageIndex), [0, 1, 2])
    }

    func testATallTextAfterOtherBlocksStartsOnAPageOfItsOwn() async {
        let sizes = Sizes(unitHeights: [[100], [900]], cuts: [[], [450, 800]])
        let placements = await NotePageFlow.placements(of: [block(), block()], pageHeight: 500, measurements: sizes.measurements)
        XCTAssertEqual(placements.map(\.pageIndex), [0, 1, 2])
        XCTAssertEqual(placements[1].sliceBottom, 450)
    }

    func testWithoutAGapTheCutFillsThePage() async {
        let sizes = Sizes(unitHeights: [[1_200]])
        let placements = await NotePageFlow.placements(of: [block()], pageHeight: 500, measurements: sizes.measurements)
        XCTAssertEqual(placements.map(\.sliceBottom), [500, 1_000, 1_200])
    }

    func testAPictureTallerThanAPageIsScaledDownOnAPageOfItsOwn() async {
        let sizes = Sizes(unitHeights: [[100], [1_000]])
        let placements = await NotePageFlow.placements(of: [block(), block(picture: true)], pageHeight: 500, measurements: sizes.measurements)
        XCTAssertEqual(placements[1].pageIndex, 1)
        XCTAssertEqual(placements[1].scale, 0.5)
        XCTAssertEqual(placements[1].height, 500)
    }

    func testAPictureThatFitsAPageMovesWholeAndUnscaled() async {
        let sizes = Sizes(unitHeights: [[300], [400]])
        let placements = await NotePageFlow.placements(of: [block(), block(picture: true)], pageHeight: 500, measurements: sizes.measurements)
        XCTAssertEqual(placements[1].pageIndex, 1)
        XCTAssertEqual(placements[1].scale, 1)
    }

    func testAnItemTallerThanAPageIsCutInItsGaps() async {
        let sizes = Sizes(unitHeights: [[100, 800, 100]], cuts: [[300, 450, 700]])
        let placements = await NotePageFlow.placements(of: [block(units: 3)], pageHeight: 500, measurements: sizes.measurements)
        XCTAssertEqual(placements.first?.units, 0..<1)
        XCTAssertTrue(placements.allSatisfy { placement in placement.height <= 500 })
        let secondItemSlices = placements.filter { placement in placement.units == 1..<2 }
        XCTAssertEqual(secondItemSlices.first?.sliceBottom, 450, "Cut in its lowest gap that fits a page.")
        XCTAssertEqual(placements.last?.units, 1..<3, "The rest of the tall item and the item after it fit the last page together.")
        XCTAssertEqual(placements.last?.sliceTop, 450)
    }

    func testNoPageIsEverFilledPastItsHeight() async {
        let sizes = Sizes(unitHeights: [[120], [40], [30, 60, 90, 20, 70], [700], [45], [300]], cuts: [[], [], [], [330, 640], [], []])
        let blocks = [block(), block(heading: true), block(units: 5), block(), block(heading: true), block()]
        let placements = await NotePageFlow.placements(of: blocks, pageHeight: 400, measurements: sizes.measurements)
        for placement in placements { XCTAssertLessThanOrEqual(placement.top + placement.height, 400.0001) }
        let lastOnEachPage = Dictionary(grouping: placements, by: \.pageIndex).values.compactMap { page in
            page.max { first, second in first.top < second.top }
        }
        XCTAssertFalse(lastOnEachPage.contains { placement in blocks[placement.blockIndex].keepsWithNext && placement.blockIndex < blocks.count - 1 })
    }

    func testAPageWithNoHeightPlacesNothing() async {
        let placements = await NotePageFlow.placements(of: [block()], pageHeight: 0, measurements: Sizes(unitHeights: [[10]]).measurements)
        XCTAssertEqual(placements, [])
    }
}
