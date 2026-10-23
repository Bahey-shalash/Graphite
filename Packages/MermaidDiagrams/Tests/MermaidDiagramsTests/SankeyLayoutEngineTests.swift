import XCTest
@testable import MermaidDiagrams

/// Sankey diagrams laid out with text of fixed widths: the title 8 points a character, labels half their size.
final class SankeyLayoutEngineTests: XCTestCase {
    private func laidOut(_ source: String) throws -> SankeyLayout {
        let font = DiagramFont(postScriptName: nil, size: 16)
        return try SankeyLayoutEngine.layout(try SankeyReading.diagram(source), titleText: UniformWidthTextMeasurer(), font: font) { size in
            UniformWidthTextMeasurer(characterWidth: size / 2, fontSize: size, lineHeight: (size * 1.5).rounded())
        }
    }

    func testTheChartIsPelesWithThePageAroundIt() throws {
        let layout = try laidOut("sankey\na,b,10")
        XCTAssertEqual(layout.size, CGSize(width: 600 + 16, height: 400 + 16))
        XCTAssertEqual(layout.nodes.map(\.frame), [CGRect(x: 8, y: 8, width: 10, height: 400), CGRect(x: 8 + 590, y: 8, width: 10, height: 400)])
        XCTAssertEqual(layout.nodes.map(\.seriesIndex), [0, 1])
        XCTAssertNil(layout.title)
    }

    func testALabelIsAfterItsBarInTheLeftHalfAndBeforeItInTheRightHalf() throws {
        let layout = try laidOut("sankey\na,b,10")
        let source = layout.labels[0]
        XCTAssertEqual(source.name.lines, ["a"])
        XCTAssertEqual(source.value.lines, ["10"])
        XCTAssertEqual(source.name.frame.minX, layout.nodes[0].frame.maxX + 6, accuracy: 0.001)
        XCTAssertEqual(source.value.frame.minX, source.name.frame.maxX + 7, accuracy: 0.001, "A space between the name and the value")
        XCTAssertEqual(source.name.center.y, layout.nodes[0].frame.midY, accuracy: 0.001)
        let target = layout.labels[1]
        XCTAssertEqual(target.value.frame.maxX, layout.nodes[1].frame.minX - 6, accuracy: 0.001)
        XCTAssertEqual(source.name.fontSize, 14, "Seven eighths of the text size")
    }

    func testValuesAreRoundedToTwoDecimalsAndNamesDecoded() throws {
        let layout = try laidOut("sankey\n#quot;Q#quot;,b,124.729\n#quot;Q#quot;,c,0.001")
        XCTAssertEqual(layout.labels[0].name.lines, ["\"Q\""])
        XCTAssertEqual(layout.labels[0].value.lines, ["124.73"])
        XCTAssertEqual(layout.labels[2].value.lines, ["0"])
    }

    func testTheTitleIsCenteredAboveTheChart() throws {
        let layout = try laidOut("---\ntitle: Energy\n---\nsankey\na,b,10")
        let title = try XCTUnwrap(layout.title)
        XCTAssertEqual(title.center, CGPoint(x: layout.size.width / 2, y: 8 + 12))
        XCTAssertEqual(layout.size.height, 400 + 16 + 24 + 12)
        XCTAssertEqual(layout.nodes[0].frame.minY, 8 + 24 + 12)
    }

    func testBandsRunFromTheSourcesRightSideToTheTargetsLeftSide() throws {
        let layout = try laidOut("sankey\na,b,30\na,c,10\nb,d,30")
        let band = layout.links[0]
        XCTAssertEqual(band.startX, layout.nodes[0].frame.maxX)
        XCTAssertEqual(band.endX, layout.nodes[1].frame.minX)
        XCTAssertEqual(band.sourceSeriesIndex, 0)
        XCTAssertEqual(band.targetSeriesIndex, 1)
        XCTAssertEqual(2 * (layout.links[0].halfThickness + layout.links[1].halfThickness), layout.nodes[0].frame.height, accuracy: 0.001)
        XCTAssertEqual(try laidOut("sankey\na,b,0\na,c,1").links[0].halfThickness, 0.5, "A band without flow is a point thick")
    }

    func testLabelsShrinkWhenAColumnIsCrowded() throws {
        let twenty = "sankey\n" + (0..<20).map { index in "source,t\(index),1" }.joined(separator: "\n")
        XCTAssertEqual(try laidOut(twenty).labels[0].name.fontSize, 11, "400 points for 20 nodes of 1.8 lines")
        let forty = "sankey\n" + (0..<40).map { index in "source,t\(index),1" }.joined(separator: "\n")
        XCTAssertEqual(try laidOut(forty).labels[0].name.fontSize, 10, "Never below five eighths of the text size")
    }

    func testCircularLinksAreNotLaidOut() {
        XCTAssertThrowsError(try laidOut("sankey\na,b,1\nb,a,1")) { error in XCTAssertEqual(error as? SankeyLayoutError, .circularLinks) }
    }

    func testALabelThatWouldRunIntoAnotherMovesALineUpWhereItIsFree() {
        let nodes = [SankeyPlacement.Node(layer: 0, value: 1, x: 0, y: 150, height: 100), SankeyPlacement.Node(layer: 1, value: 1, x: 100, y: 195, height: 10)]
        let placement = SankeyLabelPlacement(nodes: nodes, widths: [100, 50], fontSize: 14, chartSize: (600, 400), nodeWidth: 10)
        XCTAssertEqual(placement.labels[0].middle, 200 - 21, "A line up, clear of the other label and of its bar")
        XCTAssertTrue(placement.labels[0].isAfter)
        XCTAssertEqual(placement.labels[1].middle, 200)
    }
}
