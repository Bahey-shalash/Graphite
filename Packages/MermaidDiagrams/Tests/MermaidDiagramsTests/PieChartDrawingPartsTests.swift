import XCTest
@testable import MermaidDiagrams

final class PieChartDrawingPartsTests: XCTestCase {
    private func parts(_ source: String) throws -> (PieChartLayout, PieChartDrawingParts) {
        let layout = PieChartLayoutEngine.layout(try PieChartReading.pieChart(source), text: UniformWidthTextMeasurer(),
                                                 smallText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                                 font: UniformWidthLayout.font)
        return (layout, PieChartDrawingParts(layout: layout))
    }

    func testEachSeriesColorFillsItsSlicesAndSwatchesAndTheNinthComesRound() throws {
        let (layout, parts) = try parts("pie\n" + (1...9).map { number in "\"\(number)\" : 1" }.joined(separator: "\n"))
        XCTAssertEqual(parts.seriesFills.count, 8)
        XCTAssertTrue(parts.seriesFills[0].boundingBoxOfPath.contains(layout.legend[8].swatch), "The ninth swatch is in the first color")
        XCTAssertTrue(parts.seriesFills[0].contains(PieChartSlicePlacement.point(at: 2 * .pi * 8.5 / 9, distance: 60, from: layout.center)),
                      "So is the ninth slice")
        XCTAssertTrue(parts.seriesFills[1].contains(PieChartSlicePlacement.point(at: 2 * .pi * 1.5 / 9, distance: 60, from: layout.center)))
        XCTAssertTrue(parts.emptyPieOutline.isEmpty)
    }

    func testAFewSlicesUseAsManyColors() throws {
        let (_, parts) = try parts("pie\n\"a\" : 1\n\"b\" : 2")
        XCTAssertEqual(parts.seriesFills.count, 2)
    }

    func testTheEdgesOutlineTheWholePie() throws {
        let (layout, parts) = try parts("pie\n\"a\" : 1\n\"b\" : 2\n\"c\" : 3")
        let pieFrame = CGRect(x: layout.center.x - layout.radius, y: layout.center.y - layout.radius, width: 2 * layout.radius, height: 2 * layout.radius)
        XCTAssertEqual(parts.sliceEdges.boundingBoxOfPath.insetBy(dx: -0.001, dy: -0.001).contains(pieFrame), true)
        XCTAssertEqual(parts.insidePercentages.count + parts.outsidePercentages.count, 3)
        XCTAssertEqual(parts.legendTexts.count, 3)
    }

    func testAWholePieIsACircleWithoutALineToItsCenter() throws {
        let (layout, parts) = try parts("pie\n\"only\" : 1")
        let wedge = PieChartDrawingParts.wedge(layout.slices[0], center: layout.center, radius: layout.radius)
        XCTAssertTrue(wedge.contains(CGPoint(x: layout.center.x, y: layout.center.y - 100)))
        XCTAssertEqual(parts.sliceEdges.boundingBoxOfPath.width, 2 * layout.radius, accuracy: 0.001)
        var segmentCount = 0
        wedge.applyWithBlock { element in if element.pointee.type == .addLineToPoint { segmentCount += 1 } }
        XCTAssertEqual(segmentCount, 0)
    }

    func testAnEmptyChartHasOnlyTheCircleAndItsLegend() throws {
        let (_, parts) = try parts("pie title Nothing yet\n\"zero\" : 0")
        XCTAssertFalse(parts.emptyPieOutline.isEmpty)
        XCTAssertTrue(parts.sliceEdges.isEmpty)
        XCTAssertEqual(parts.seriesFills.count, 1, "The swatch")
        XCTAssertEqual(parts.title?.lines, ["Nothing yet"])
    }
}
