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
        let value = try XCTUnwrap(source.value)
        XCTAssertEqual(value.lines, ["10"])
        XCTAssertEqual(source.name.frame.minX, layout.nodes[0].frame.maxX + 6, accuracy: 0.001)
        XCTAssertEqual(value.frame.minX, source.name.frame.maxX + 7, accuracy: 0.001, "A space between the name and the value")
        XCTAssertEqual(source.name.center.y, layout.nodes[0].frame.midY, accuracy: 0.001)
        let target = layout.labels[1]
        XCTAssertEqual(try XCTUnwrap(target.value).frame.maxX, layout.nodes[1].frame.minX - 6, accuracy: 0.001)
        XCTAssertEqual(source.name.fontSize, 14, "Seven eighths of the text size")
    }

    func testValuesAreRoundedToTwoDecimalsAndNamesDecoded() throws {
        let layout = try laidOut("sankey\n#quot;Q#quot;,b,124.729\n#quot;Q#quot;,c,0.001")
        XCTAssertEqual(layout.labels[0].name.lines, ["\"Q\""])
        XCTAssertEqual(layout.labels[0].value?.lines, ["124.73"])
        XCTAssertEqual(layout.labels[2].value?.lines, ["0"])
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

    func testTheFrontMattersOptionsShapeTheChart() throws {
        let options = "---\nconfig:\n  sankey:\n    showValues: false\n    width: 300\n    height: 200\n    nodeWidth: 15\n    nodePadding: 20\n---\n"
        let layout = try laidOut(options + "sankey\na,b,1\na,c,1")
        XCTAssertTrue(layout.labels.allSatisfy { label in label.value == nil }, "showValues: false")
        XCTAssertEqual(layout.nodes[0].frame.width, 15)
        XCTAssertEqual(layout.nodes[1].frame.minX - layout.nodes[0].frame.minX, 300 - 15)
        XCTAssertEqual(layout.nodes[2].frame.minY - layout.nodes[1].frame.maxY, 20, accuracy: 0.001, "No room added for values")
        XCTAssertEqual(layout.nodes[0].frame.height, 200 - 20, accuracy: 0.001, "The fuller column holds two nodes and a gap")
        let prefixed = try laidOut("---\nconfig:\n  sankey:\n    prefix: \"$\"\n    suffix: \" TWh\"\n---\nsankey\na,b,1.5")
        XCTAssertEqual(prefixed.labels[0].value?.lines, ["$1.5 TWh"])
    }

    func testOptionsNotDrawnYetKeepTheDiagramFromBeingLaidOut() throws {
        for option in ["labelStyle: outlined", "linkColor: source", "nodeColors:\n      a: \"#4e79a7\""] {
            let source = "---\nconfig:\n  sankey:\n    \(option)\n---\nsankey\na,b,1"
            XCTAssertThrowsError(try laidOut(source), option) { error in XCTAssertEqual(error as? SankeyLayoutError, .optionsNotDrawn) }
        }
        XCTAssertNoThrow(try laidOut("---\nconfig:\n  sankey:\n    linkColor: gradient\n---\nsankey\na,b,1"), "The gradient is drawn")
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
