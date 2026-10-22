import XCTest
@testable import GraphiteCore

/// The graph's Display settings: node size, link thickness and the zoom from which names show.
final class GraphDisplayOptionsTests: XCTestCase {
    func testTheDefaultsKeepTheGraphsSizesAndShowNotesNamesFromAZoomOf1Point4() {
        let display = GraphDisplayOptions()
        XCTAssertEqual(display.nodeSizeMultiplier, 1)
        XCTAssertEqual(display.linkThicknessMultiplier, 1)
        XCTAssertEqual(display.nameScale(of: .note), 1.4)
        XCTAssertEqual(display.nameScale(of: .tag), 0.7)
    }

    func testNamesShowFromTheChosenZoomAndTagsFromHalfOfIt() {
        let display = GraphDisplayOptions(nameScale: 2)
        XCTAssertFalse(display.showsName(of: .note, atScale: 1.9))
        XCTAssertTrue(display.showsName(of: .note, atScale: 2))
        XCTAssertTrue(display.showsName(of: .attachment, atScale: 2))
        XCTAssertTrue(display.showsName(of: .unresolved, atScale: 2))
        XCTAssertFalse(display.showsName(of: .tag, atScale: 0.9))
        XCTAssertTrue(display.showsName(of: .tag, atScale: 1))
    }

    func testTheSlidersRangesHoldTheDefaults() {
        let display = GraphDisplayOptions()
        XCTAssertTrue(GraphDisplayOptions.nodeSizeMultipliers.contains(display.nodeSizeMultiplier))
        XCTAssertTrue(GraphDisplayOptions.linkThicknessMultipliers.contains(display.linkThicknessMultiplier))
        XCTAssertTrue(GraphDisplayOptions.nameScales.contains(display.nameScale))
    }
}
