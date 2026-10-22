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

    func testNamesAreWholeFromTheChosenZoomAndTagsFromHalfOfIt() {
        let display = GraphDisplayOptions(nameScale: 2)
        XCTAssertEqual(display.nameOpacity(of: .note, atScale: 2), 1)
        XCTAssertEqual(display.nameOpacity(of: .attachment, atScale: 5), 1)
        XCTAssertEqual(display.nameOpacity(of: .unresolved, atScale: 2), 1)
        XCTAssertEqual(display.nameOpacity(of: .tag, atScale: 1), 1)
        XCTAssertEqual(display.nameOpacity(of: .note, atScale: 1.4), 0, "Below three quarters of the name zoom, no name.")
        XCTAssertFalse(display.showsName(of: .note, atScale: 1.4))
        XCTAssertFalse(display.showsName(of: .tag, atScale: 0.7))
    }

    func testNamesFadeInAsTheZoomNearsTheNameZoomRatherThanAllAtOnce() {
        let display = GraphDisplayOptions(nameScale: 2)
        let opacities = stride(from: 1.5, through: 2.0, by: 0.1).map { scale in display.nameOpacity(of: .note, atScale: scale) }
        XCTAssertEqual(opacities.first, 0)
        XCTAssertEqual(opacities[1], 0.2, accuracy: 1e-9)
        XCTAssertEqual(opacities[3], 0.6, accuracy: 1e-9)
        XCTAssertEqual(opacities.last ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(opacities, opacities.sorted(), "Zooming in only ever brings a name out more.")
        XCTAssertTrue(display.showsName(of: .note, atScale: 1.6), "A faint name is shown.")
        XCTAssertEqual(display.nameFadeStartScale(of: .tag), 0.75)
    }

    func testTheSlidersRangesHoldTheDefaults() {
        let display = GraphDisplayOptions()
        XCTAssertTrue(GraphDisplayOptions.nodeSizeMultipliers.contains(display.nodeSizeMultiplier))
        XCTAssertTrue(GraphDisplayOptions.linkThicknessMultipliers.contains(display.linkThicknessMultiplier))
        XCTAssertTrue(GraphDisplayOptions.nameScales.contains(display.nameScale))
    }
}
