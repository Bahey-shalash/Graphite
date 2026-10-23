import XCTest
@testable import MermaidDiagrams

/// The legend's entries in rows, with names 7 points a character and 21-point lines.
final class UserJourneyLegendRowsTests: XCTestCase {
    private let measurer = UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21)

    func testEntriesStandSideBySideTwentyPointsApartWhileTheyFit() {
        let rows = UserJourneyLegendRows(actorNames: ["Cat", "Me"], measurer: measurer, rowWidth: 240)
        XCTAssertEqual(rows.entries.map(\.offset), [CGPoint(x: 0, y: 0), CGPoint(x: 16 + 21 + 20, y: 0)])
        XCTAssertEqual(rows.size, CGSize(width: 16 + 21 + 20 + 16 + 14, height: 21))
        XCTAssertEqual(rows.entries.map(\.seriesIndex), [0, 1])
    }

    func testAnEntryThatWouldPassTheRowsWidthStartsARowFourPointsBelow() {
        let rows = UserJourneyLegendRows(actorNames: ["Alexandra", "Bartholomew", "C"], measurer: measurer, rowWidth: 120)
        XCTAssertEqual(rows.entries.map(\.offset), [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 25), CGPoint(x: 0, y: 50)])
        XCTAssertEqual(rows.size.height, 71)
    }

    func testANameWiderThanTheRowIsCutToFitBesideItsDot() {
        let rows = UserJourneyLegendRows(actorNames: [String(repeating: "a", count: 40)], measurer: measurer, rowWidth: 100)
        XCTAssertTrue(rows.entries[0].text.lineWidths.allSatisfy { width in width <= 100 - 16 })
        XCTAssertEqual(rows.entries[0].height, rows.entries[0].text.size.height)
    }
}
