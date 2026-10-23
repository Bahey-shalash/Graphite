import XCTest
@testable import MermaidDiagrams

/// The quadrant chart laid out with Pele's measurements, with text of fixed widths (`QuadrantChartReading.uniformLayout`):
/// quadrants 8 points a character at 16 (24-point lines), axes 7 at 14 (21), points 6 at 12 (18), the title 8 at 16.
final class QuadrantChartLayoutEngineTests: XCTestCase {
    private func layout(_ source: String) throws -> QuadrantChartLayout {
        try QuadrantChartReading.uniformLayout(source)
    }

    private func plot(_ layout: QuadrantChartLayout) -> CGRect {
        layout.quadrants.map(\.frame).reduce(layout.quadrants[0].frame) { union, frame in union.union(frame) }
    }

    func testThePageIsFiveHundredPointsAndTheQuadrantsGoAnticlockwiseFromTheTopRight() throws {
        let layout = try layout("quadrantChart\n quadrant-1 q1\n quadrant-2 q2\n quadrant-3 q3\n quadrant-4 q4")
        XCTAssertEqual(layout.size, CGSize(width: 500, height: 500))
        let origins = layout.quadrants.map(\.frame.origin)
        XCTAssertGreaterThan(origins[0].x, origins[1].x)
        XCTAssertEqual(origins[0].y, origins[1].y)
        XCTAssertEqual(origins[2].x, origins[1].x)
        XCTAssertGreaterThan(origins[2].y, origins[1].y)
        XCTAssertEqual(origins[3], CGPoint(x: origins[0].x, y: origins[2].y))
        XCTAssertEqual(layout.quadrants[0].frame.minX - layout.quadrants[1].frame.maxX, 4)
        XCTAssertEqual(plot(layout), CGRect(x: 8, y: 8, width: 484, height: 484), "Without title or axes the plot fills the page inside its padding")
    }

    func testPointsSitAtTheirCoordinatesXToTheRightAndYUpwards() throws {
        let layout = try layout("quadrantChart\n A: [0, 0]\n B: [1, 1]\n C: [0.5, 0.5]")
        let plot = plot(layout)
        XCTAssertEqual(layout.points.map(\.center), [CGPoint(x: plot.minX, y: plot.maxY), CGPoint(x: plot.maxX, y: plot.minY),
                                                     CGPoint(x: plot.midX, y: plot.midY)])
    }

    func testTheTitleAndTheAxesTakeTheirRoomBesideThePlot() throws {
        let layout = try layout("quadrantChart\n title Reach\n x-axis Low Reach --> High Reach\n y-axis Low --> High\n A: [0.5, 0.5]")
        let title = try XCTUnwrap(layout.title)
        XCTAssertEqual(title.center, CGPoint(x: 250, y: (24 + 10) / 2))
        XCTAssertEqual(plot(layout), CGRect(x: 8 + 21 + 5, y: 8 + 24 + 10, width: 484 - 26, height: 500 - 16 - 34 - 26))
    }

    func testTheXAxisTextsMoveBelowTheChartOnceThereArePoints() throws {
        let without = try layout("quadrantChart\n x-axis Left --> Right")
        XCTAssertLessThan(without.axisLabels[0].text.center.y, 100)
        XCTAssertEqual(plot(without).minY - without.axisLabels[0].text.frame.maxY, 5)
        let with = try layout("quadrantChart\n x-axis Left --> Right\n A: [0.5, 0.5]")
        XCTAssertGreaterThan(with.axisLabels[0].text.center.y, 400)
        XCTAssertEqual(with.axisLabels[0].text.frame.minY - plot(with).maxY, 5)
    }

    func testEachAxisTextSitsInTheMiddleOfItsHalfAndTheYAxisIsTurned() throws {
        let layout = try layout("quadrantChart\n x-axis Left --> Right\n y-axis Down --> Up")
        let plot = plot(layout)
        XCTAssertEqual(layout.axisLabels.map(\.text.center.x).prefix(2), [plot.minX + plot.width / 4, plot.minX + plot.width * 3 / 4])
        XCTAssertEqual(layout.axisLabels.map(\.text.center.y).suffix(2), [plot.minY + plot.height * 3 / 4, plot.minY + plot.height / 4])
        XCTAssertEqual(layout.axisLabels.map(\.isTurned), [false, false, true, true])
        XCTAssertEqual(layout.axisLabels[2].text.center.x, plot.minX - 5 - 21 / 2)
        let lowOnly = try self.layout("quadrantChart\n x-axis Alone\n y-axis Below")
        let lowPlot = self.plot(lowOnly)
        XCTAssertEqual(lowOnly.axisLabels[0].text.frame.minX, lowPlot.minX, "From the left edge without a high end")
        XCTAssertEqual(lowOnly.axisLabels[1].text.center.y, lowPlot.maxY - lowOnly.axisLabels[1].text.size.width / 2, "From the bottom")
    }

    func testQuadrantTextsAreInTheMiddleThenAtTheTopOnceThereArePoints() throws {
        let without = try layout("quadrantChart\n quadrant-1 Plan")
        XCTAssertEqual(without.quadrants[0].text?.center, CGPoint(x: without.quadrants[0].frame.midX, y: without.quadrants[0].frame.midY))
        let with = try layout("quadrantChart\n quadrant-1 Plan\n A: [0.1, 0.1]")
        XCTAssertEqual(with.quadrants[0].text?.frame.minY, with.quadrants[0].frame.minY + 5)
        XCTAssertNil(with.quadrants[1].text)
    }

    func testPointStylesApplyTheirOwnOverTheirClasss() throws {
        let layout = try layout("""
        quadrantChart
          A: [0.1, 0.1] radius: 12
          B:::c1: [0.2, 0.2] color: #ff3300, radius: 10
          C:::c2: [0.3, 0.3]
          D: [0.4, 0.4] color: 00f, stroke-width: 3px
          E: [0.5, 0.5] stroke-color: #00ff00
          classDef c1 color: #109060
          classDef c2 color: #908342, radius : 9, stroke-color: #310085, stroke-width: 10px
        """)
        XCTAssertEqual(layout.points.map(\.radius), [12, 10, 9, 5, 5])
        XCTAssertEqual(layout.points.map(\.fill), [.firstSeries, .written(QuadrantChartColor(red: 0xFF, green: 0x33, blue: 0)),
                                                   .written(QuadrantChartColor(red: 0x90, green: 0x83, blue: 0x42)),
                                                   .written(QuadrantChartColor(red: 0, green: 0, blue: 0xFF)), .firstSeries])
        let violet = QuadrantChartColor(red: 0x31, green: 0, blue: 0x85)
        XCTAssertEqual(layout.points.map(\.stroke),
                       [nil, nil, QuadrantChartStroke(paint: .written(violet), width: 10), QuadrantChartStroke(paint: .firstSeries, width: 3), nil],
                       "A stroke color without a width does not show, as in Mermaid")
    }

    func testAPointWhoseCoordinateIsNoNumberFromZeroToOneIsLeftOut() throws {
        let layout = try layout("quadrantChart\n A: [0x5, 0.5]\n B: [0,5, 0.5]\n C: [0.5, 0.5]")
        XCTAssertEqual(layout.points.map(\.text.lines), [["C"]])
    }

    func testPointTextsStayInsideThePlotAndApart() throws {
        let layout = try layout("quadrantChart\n One: [0.5, 0]\n Two: [0.5, 0.02]\n Three: [1, 1]\n Four: [0, 0.5]")
        let plot = plot(layout)
        let boxes = layout.points.map { point in Self.clearedBox(point.text) }
        for box in boxes { XCTAssertTrue(plot.contains(box), "\(box) in \(plot)") }
        for (index, box) in boxes.enumerated() {
            for other in boxes[(index + 1)...] { XCTAssertFalse(box.intersects(other), "\(box) and \(other)") }
        }
    }

    func testATextGoesBelowItsPointWhenThatIsFreeAndAboveWhenItIsNot() throws {
        let layout = try layout("quadrantChart\n Free: [0.25, 0.75]\n Low: [0.75, 0.01]")
        let free = layout.points[0]
        XCTAssertEqual(free.text.center.x, free.center.x)
        XCTAssertEqual(free.text.center.y, free.center.y + 5 + 5 + 12 * 0.6, accuracy: 0.001, "The radius, the padding and half a line below")
        let low = layout.points[1]
        XCTAssertEqual(low.text.center.y, low.center.y - 5 - 5 - 12 * 0.6, accuracy: 0.001, "Above, with no room below")
    }

    func testTheDocumentationsExampleKeepsTheTextsOffEachOtherAndTheQuadrantsTexts() throws {
        let layout = try layout(QuadrantChartReading.reachAndEngagement)
        XCTAssertEqual(layout.points.count, 6)
        let quadrantTexts = layout.quadrants.compactMap(\.text?.frame)
        let pointBoxes = layout.points.map { point in Self.clearedBox(point.text) }
        for (index, box) in pointBoxes.enumerated() {
            for other in pointBoxes[(index + 1)...] + quadrantTexts { XCTAssertFalse(box.intersects(other), "\(box) and \(other)") }
        }
    }

    func testAboveThreeHundredPointsTextsAreNotKeptApart() throws {
        let source = "quadrantChart\n" + (0..<301).map { index in "  P\(index): [0.5, 0.5]" }.joined(separator: "\n")
        let layout = try layout(source)
        XCTAssertEqual(Set(layout.points.map(\.text.center.y)).count, 1, "Each text below its point")
    }

    /// The box a point's text keeps clear: its width, and 0.6 of its font size above and below its middle line.
    private static func clearedBox(_ text: DiagramTextBlock) -> CGRect {
        let halfHeight = text.fontSize * 0.6 + (text.size.height - text.lineHeight) / 2
        return CGRect(x: text.center.x - text.size.width / 2, y: text.center.y - halfHeight, width: text.size.width, height: 2 * halfHeight)
    }
}
