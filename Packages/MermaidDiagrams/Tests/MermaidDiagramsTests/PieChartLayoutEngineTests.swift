import XCTest
@testable import MermaidDiagrams

/// Pele's pie measurements, with text of uniform width: 8 points a character for the title and 7 for the
/// percentages and the legend (21-point lines).
final class PieChartLayoutEngineTests: XCTestCase {
    private func laidOut(_ source: String) throws -> PieChartLayout {
        PieChartLayoutEngine.layout(try PieChartReading.pieChart(source), text: UniformWidthTextMeasurer(),
                                    smallText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21), font: UniformWidthLayout.font)
    }

    private let pets = "pie title Pets adopted by volunteers\n    \"Dogs\" : 386\n    \"Cats\" : 85\n    \"Rats\" : 15\n"

    func testThePieSitsLeftWithItsLegendBesideItAndTheTitleAbove() throws {
        let layout = try laidOut(pets)
        // A thin slice's percentage goes outside the rim: the pie takes 28 more points on each side (296 across),
        // then 32 points and the legend (swatch, gap and the widest label: 12 + 8 + 28); the title takes 24 + 16.
        XCTAssertEqual(layout.size, CGSize(width: 392, height: 352))
        XCTAssertEqual(layout.center, CGPoint(x: 156, y: 196))
        XCTAssertEqual(layout.radius, 120)
        XCTAssertEqual(layout.title?.center, CGPoint(x: 196, y: 20))
        XCTAssertEqual(layout.legend.map(\.swatch), [CGRect(x: 336, y: 164, width: 12, height: 12), CGRect(x: 336, y: 190, width: 12, height: 12),
                                                     CGRect(x: 336, y: 216, width: 12, height: 12)])
        XCTAssertEqual(layout.legend.map(\.text.center), [CGPoint(x: 370, y: 170), CGPoint(x: 370, y: 196), CGPoint(x: 370, y: 222)])
        XCTAssertEqual(layout.legend.map(\.text.lines), [["Dogs"], ["Cats"], ["Rats"]])
    }

    func testSlicesRunClockwiseFromTheTopInTheirOrderWithTheirPercentages() throws {
        let layout = try laidOut(pets)
        XCTAssertEqual(layout.slices.map(\.seriesIndex), [0, 1, 2])
        XCTAssertEqual(layout.slices.map(\.percentage.lines), [["79%"], ["17%"], ["3%"]])
        XCTAssertEqual(layout.slices[0].startAngle, 0)
        XCTAssertEqual(layout.slices[1].startAngle, layout.slices[0].endAngle)
        XCTAssertEqual(layout.slices[2].startAngle, layout.slices[1].endAngle)
        XCTAssertEqual(layout.slices[2].endAngle, 2 * .pi, accuracy: 1e-9)
        XCTAssertEqual(layout.slices[0].endAngle, 2 * .pi * 386 / 486, accuracy: 1e-9)
    }

    func testAPercentageSitsInsideItsSliceUnlessTheSliceIsTooThin() throws {
        let layout = try laidOut(pets)
        XCTAssertEqual(layout.slices.map(\.percentagePlacement), [.insideSlice, .insideSlice, .outsideRim])
        for slice in layout.slices {
            let middle = (slice.startAngle + slice.endAngle) / 2
            let distance = slice.percentagePlacement == .insideSlice ? 90.0 : 134.0
            XCTAssertEqual(slice.percentage.center.x, layout.center.x + sin(middle) * distance, accuracy: 1e-9)
            XCTAssertEqual(slice.percentage.center.y, layout.center.y - cos(middle) * distance, accuracy: 1e-9)
        }
    }

    func testThinSlicesKeepTheirPercentagesApartOutsideTheRim() throws {
        let layout = try laidOut("pie\n \"Calcium\" : 2\n \"Potassium\" : 2.4\n \"Magnesium\" : 46\n \"Test\" : 50")
        let outside = layout.slices.filter { slice in slice.percentagePlacement == .outsideRim }.map(\.percentage)
        XCTAssertEqual(outside.count, 2)
        let across = abs(outside[0].center.x - outside[1].center.x) >= (outside[0].size.width + outside[1].size.width) / 2
        let down = abs(outside[0].center.y - outside[1].center.y) >= outside[0].fontSize
        XCTAssertTrue(across || down)
    }

    func testAPercentageThatWouldOverlapAnotherMovesClockwiseAlongTheRim() throws {
        let layout = try laidOut("pie\n \"a\" : 1.2\n \"b\" : 1.2\n \"c\" : 97.6")
        let first = layout.slices[0]
        let second = layout.slices[1]
        XCTAssertEqual([first.percentagePlacement, second.percentagePlacement], [.outsideRim, .outsideRim])
        let unmoved = PieChartSlicePlacement.point(at: (second.startAngle + second.endAngle) / 2, distance: 134, from: layout.center)
        XCTAssertGreaterThan(second.percentage.center.x, unmoved.x, "Moved on, clockwise")
        XCTAssertGreaterThanOrEqual(abs(second.percentage.center.x - first.percentage.center.x), 14 + 2)
        XCTAssertEqual(hypot(second.percentage.center.x - layout.center.x, second.percentage.center.y - layout.center.y), 134, accuracy: 1e-9)
    }

    func testASliceUnderOnePercentIsNotDrawnAndKeepsItsLegendEntry() throws {
        let layout = try laidOut("pie\n \"Big\" : 1000\n \"Tiny\" : 1")
        XCTAssertEqual(layout.slices.map(\.seriesIndex), [0])
        XCTAssertEqual(layout.legend.map(\.seriesIndex), [0, 1])
        XCTAssertLessThan(layout.slices[0].endAngle, 2 * .pi)
        XCTAssertFalse(layout.slices[0].isWholePie)
    }

    func testShowDataPutsEachValueAfterItsLabel() throws {
        let layout = try laidOut("pie showData\n \"A\" : 42.96\n \"B\" : 50\n \"Two<br>lines\" : 7.0")
        XCTAssertEqual(layout.legend.map(\.text.lines), [["A [42.96]"], ["B [50]"], ["Two", "lines [7]"]])
        XCTAssertEqual(PieChartLayoutEngine.writtenValue(0.5), "0.5")
        XCTAssertEqual(PieChartLayoutEngine.writtenValue(386), "386")
    }

    func testOneSliceIsTheWholePieWithItsPercentageBelowTheCenter() throws {
        let layout = try laidOut("pie\n \"Only\" : 5")
        XCTAssertEqual(layout.slices.count, 1)
        XCTAssertTrue(layout.slices[0].isWholePie)
        XCTAssertEqual(layout.slices[0].percentage.lines, ["100%"])
        XCTAssertEqual(layout.slices[0].percentage.center.x, layout.center.x, accuracy: 1e-9)
        XCTAssertEqual(layout.slices[0].percentage.center.y, layout.center.y + 90, accuracy: 1e-9)
    }

    func testAChartWithoutSlicesOrValuesIsTheEmptyPie() throws {
        let empty = try laidOut("pie")
        XCTAssertEqual(empty.size, CGSize(width: 256, height: 256))
        XCTAssertEqual(empty.center, CGPoint(x: 128, y: 128))
        XCTAssertTrue(empty.slices.isEmpty)
        XCTAssertNil(empty.title)
        let zero = try laidOut("pie\n \"Zero\" : 0")
        XCTAssertTrue(zero.slices.isEmpty)
        XCTAssertEqual(zero.legend.count, 1)
    }

    func testATitleWiderThanTheChartWidensThePageAndIsCenteredOnIt() throws {
        let title = String(repeating: "Wide ", count: 20).trimmingCharacters(in: .whitespaces)
        let layout = try laidOut("pie title \(title)\n \"a\" : 1")
        XCTAssertEqual(layout.size.width, CGFloat(title.count * 8 + 16))
        XCTAssertEqual(layout.title?.center.x, layout.size.width / 2)
        XCTAssertEqual(layout.center.x, 8 + 120, "The pie stays at the left")
    }
}
