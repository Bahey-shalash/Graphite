import XCTest
@testable import MermaidDiagrams

/// XY charts laid out with text of fixed widths: the title 8 points a character, the axes and legend 7, point labels 6.
final class XYChartLayoutEngineTests: XCTestCase {
    private let text = XYChartText(titleText: UniformWidthTextMeasurer(), smallText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                   tinyText: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 12, lineHeight: 18))

    private func laidOut(_ source: String) throws -> XYChartLayout {
        try XYChartLayoutEngine.layout(try XYChartReading.chart(source), text: text, font: DiagramFont(postScriptName: nil, size: 16))
    }

    /// The labels left of the plot, from the bottom up, or from the top down in a horizontal chart.
    private func leftLabels(_ layout: XYChartLayout) -> [String] {
        layout.axisLabels.filter { label in label.center.x < layout.plotFrame.minX }.map { label in label.lines.joined(separator: " ") }
    }

    private func bottomLabels(_ layout: XYChartLayout) -> [String] {
        layout.axisLabels.filter { label in label.center.y > layout.plotFrame.maxY }.map { label in label.lines.joined(separator: " ") }
    }

    func testThePageIsPelesAndTheTitleIsCenteredAboveThePlot() throws {
        let layout = try laidOut("xychart\ntitle \"Sales\"\nx-axis [a, b]\nbar [1, 2]")
        XCTAssertEqual(layout.size, CGSize(width: 700, height: 500))
        let title = try XCTUnwrap(layout.title)
        XCTAssertEqual(title.center, CGPoint(x: 350, y: 8 + 12))
        XCTAssertEqual(layout.plotFrame.minY, 8 + 24 + 12 + 10.5, "The title, its gap, and half a line for the top mark's label")
    }

    func testValuesTakenFromTheDataStartAtZeroForBarsAndGrowToWholeSteps() throws {
        let layout = try laidOut("xychart\nbar [3, 7]")
        XCTAssertEqual(leftLabels(layout), ["0", "1", "2", "3", "4", "5", "6", "7"])
        XCTAssertEqual(layout.gridLines.count, 8)
        XCTAssertEqual(layout.gridLines.first?.start.y ?? 0, layout.plotFrame.maxY, accuracy: 0.001)
        XCTAssertEqual(layout.gridLines.last?.start.y ?? 0, layout.plotFrame.minY, accuracy: 0.001)
        XCTAssertEqual(leftLabels(try laidOut("xychart\nline [3, 7]")), ["3", "3.5", "4", "4.5", "5", "5.5", "6", "6.5", "7"],
                       "A line's range is its values', in steps of a half")
    }

    func testAWrittenRangeIsKeptAndMarkedAtRoundNumbersInsideIt() throws {
        XCTAssertEqual(leftLabels(try laidOut("xychart\ny-axis 0 --> 100\nbar [3, 7]")), ["0", "20", "40", "60", "80", "100"])
        let revenue = try laidOut("xychart\ny-axis \"Revenue\" 4000 --> 11000\nbar [5000, 11000]")
        XCTAssertEqual(leftLabels(revenue), ["4000", "5000", "6000", "7000", "8000", "9000", "10000", "11000"])
        let bar = try XCTUnwrap(revenue.bars.first)
        XCTAssertEqual(bar.frame.maxY, revenue.plotFrame.maxY, accuracy: 0.001, "A bar stands on the axis' nearer end when zero is below it")
        XCTAssertEqual(bar.frame.height, revenue.plotFrame.height / 7, accuracy: 0.001)
    }

    func testASlotsBarsStandSideBySideInSevenTenthsOfIt() throws {
        let layout = try laidOut("xychart\nx-axis [a, b]\ny-axis 0 --> 10\nbar [5, 10]\nbar [10, 5]")
        let slotWidth = layout.plotFrame.width / 2
        let thickness = slotWidth * 0.7 / 2
        let gap = min(2, thickness * 0.2)
        let firstSlot = layout.bars.filter { bar in bar.frame.midX < layout.plotFrame.minX + slotWidth }
        XCTAssertEqual(firstSlot.map(\.seriesIndex), [0, 1])
        XCTAssertEqual(firstSlot[0].frame.width, thickness - gap, accuracy: 0.001)
        XCTAssertEqual((firstSlot[0].frame.minX + firstSlot[1].frame.maxX) / 2, layout.plotFrame.minX + slotWidth / 2, accuracy: 0.001)
        XCTAssertEqual(firstSlot[1].frame.minY, layout.plotFrame.minY, accuracy: 0.001, "The value 10 is the range's top")
        XCTAssertEqual(firstSlot[0].frame.height, layout.plotFrame.height / 2, accuracy: 0.001)
    }

    func testBarsBelowZeroHangFromALineAtZero() throws {
        let layout = try laidOut("xychart\nx-axis [a, b]\ny-axis -10 --> 10\nbar [-5, 5]")
        let zeroY = layout.plotFrame.midY
        XCTAssertEqual(layout.bars[0].frame.minY, zeroY, accuracy: 0.001)
        XCTAssertEqual(layout.bars[1].frame.maxY, zeroY, accuracy: 0.001)
        XCTAssertTrue(layout.axisLines.contains { line in
            abs(line.start.y - zeroY) < 0.001 && line.start.x == layout.plotFrame.minX && line.end.x == layout.plotFrame.maxX
        }, "The line bars stand on")
    }

    func testALineIsCutWhereItLeavesTheRangeAndWhereAValueIsNotDrawn() throws {
        let layout = try laidOut("xychart\nx-axis [a, b, c]\ny-axis 0 --> 10\nline [5, 15, 5]")
        let line = try XCTUnwrap(layout.lines.first)
        XCTAssertEqual(line.runs.count, 2)
        XCTAssertEqual(line.runs[0].count, 2)
        XCTAssertEqual(line.runs[0][1].y, layout.plotFrame.minY, accuracy: 0.001, "The run ends on the plot's top")
        XCTAssertEqual(line.runs[1][0].y, layout.plotFrame.minY, accuracy: 0.001)
        XCTAssertEqual(line.dots.count, 2, "No dot for the value outside")
        let overflowing = try laidOut("xychart\nline [1, 2, \(String(repeating: "9", count: 400)), 3, 4]").lines[0]
        XCTAssertEqual(overflowing.runs.map(\.count), [2, 2], "An infinite value is not drawn and breaks the line")
    }

    func testALinesPointsOnARangeRunFromEndToEnd() throws {
        let layout = try laidOut("xychart\nline [1, 2, 3]")
        let points = try XCTUnwrap(layout.lines.first?.runs.first)
        XCTAssertEqual(points.first?.x ?? 0, layout.plotFrame.minX, accuracy: 0.001)
        XCTAssertEqual(points.last?.x ?? 0, layout.plotFrame.maxX, accuracy: 0.001)
        XCTAssertEqual(bottomLabels(layout).first, "1")
    }

    func testAHorizontalChartPutsCategoriesDownTheLeftAndBarsAcross() throws {
        let layout = try laidOut("xychart horizontal\nx-axis \"Fruit\" [apple, pear]\ny-axis \"Count\" 0 --> 10\nbar [5, 10]")
        XCTAssertEqual(leftLabels(layout), ["apple", "pear"], "From the top down")
        XCTAssertEqual(bottomLabels(layout).first, "0")
        XCTAssertEqual(layout.bars[0].frame.minX, layout.plotFrame.minX, accuracy: 0.001)
        XCTAssertEqual(layout.bars[1].frame.maxX, layout.plotFrame.maxX, accuracy: 0.001)
        XCTAssertLessThan(layout.bars[0].frame.midY, layout.bars[1].frame.midY)
        XCTAssertEqual(layout.leftAxisTitle?.lines, ["Fruit"])
        XCTAssertEqual(layout.bottomAxisTitle?.lines, ["Count"])
        XCTAssertTrue(layout.gridLines.allSatisfy { line in line.start.x == line.end.x }, "The grid runs down the plot")
    }

    func testTheLeftTitleIsAtThePagesEdgeAndTheBottomTitleUnderTheLabels() throws {
        let layout = try laidOut("xychart\nx-axis \"Month\" [jan, feb]\ny-axis \"Revenue\" 0 --> 10\nbar [1, 2]")
        let left = try XCTUnwrap(layout.leftAxisTitle)
        XCTAssertEqual(left.center.x, 8 + 21 / 2, "Turned, its height is across")
        XCTAssertEqual(left.center.y, layout.plotFrame.midY, accuracy: 0.001)
        let bottom = try XCTUnwrap(layout.bottomAxisTitle)
        XCTAssertEqual(bottom.center.y, 500 - 8 - 21 / 2)
        XCTAssertEqual(layout.plotFrame.maxY, 500 - 8 - 21 - 4 - 21 - 4 - 4)
    }

    func testPointLabelsGoAboveTheirDotsWithinThePlot() throws {
        let layout = try laidOut("xychart\nx-axis [a, b, c, d, e, f, g, h, i, j]\ny-axis 0 --> 10\n"
                                 + "line [5 \"Launch\", 1, 1, 1, 1, 1, 1, 1, 1, 10 \"A rather long label\"]")
        XCTAssertEqual(layout.pointLabels.map(\.lines), [["Launch"], ["A rather long label"]])
        let dot = layout.lines[0].dots[0]
        XCTAssertEqual(layout.pointLabels[0].center, CGPoint(x: dot.x, y: dot.y - 6 - 9))
        XCTAssertEqual(layout.pointLabels[1].frame.maxX, layout.plotFrame.maxX, accuracy: 0.001, "Kept inside the plot")
        XCTAssertEqual(layout.plotFrame.minY, 8 + 18 + 4, "Room for a line of point labels over the plot")
        let sideways = try laidOut("xychart horizontal\nx-axis [a, b]\ny-axis 0 --> 10\nline [5 \"Launch\", 10]")
        let sidewaysDot = sideways.lines[0].dots[0]
        XCTAssertEqual(sideways.pointLabels[0].frame.minX, sidewaysDot.x + 10, accuracy: 0.001)
    }

    func testTheLegendListsTitledSeriesRightOfThePlot() throws {
        let layout = try laidOut("xychart\nx-axis [a, b]\nbar \"Sales\" [1, 2]\nline [2, 3]\nline \"Trend\" [1, 3]")
        XCTAssertEqual(layout.legend.map(\.seriesIndex), [0, 2])
        XCTAssertEqual(layout.legend.map(\.kind), [.bar, .line])
        XCTAssertEqual(layout.legend[0].swatch.minX, layout.plotFrame.maxX + 24)
        XCTAssertEqual(layout.legend[1].swatch.midY - layout.legend[0].swatch.midY, 21 + 6, "A row is 26 points, or its title's height and 6")
        XCTAssertEqual((layout.legend[0].swatch.midY + layout.legend[1].swatch.midY) / 2, layout.plotFrame.midY, accuracy: 0.001)
        XCTAssertEqual(layout.legend[0].text.frame.minX, layout.legend[0].swatch.maxX + 8, accuracy: 0.001)
        let legendSpace: CGFloat = 5 * 7 + 12 + 8 + 24
        XCTAssertEqual(layout.plotFrame.maxX, 700 - 8 - legendSpace, accuracy: 0.001, "The widest title, the swatch, their gap, the legend's gap")
    }

    func testWithoutALegendThePlotLeavesRoomForTheLastLabel() throws {
        let layout = try laidOut("xychart\nx-axis 0 --> 1000\nline [1, 2]")
        let lastLabel = try XCTUnwrap(layout.axisLabels.last)
        XCTAssertEqual(lastLabel.frame.maxX, layout.plotFrame.maxX + lastLabel.size.width / 2, accuracy: 0.001)
        XCTAssertLessThanOrEqual(lastLabel.frame.maxX, 700 - 8 + 0.001)
    }

    func testCategoriesThatWouldRunIntoEachOtherAreThinnedOut() throws {
        let categories = (1...60).map { number in "category\(number)" }.joined(separator: ", ")
        let layout = try laidOut("xychart\nx-axis [\(categories)]\nbar [1]")
        let labels = bottomLabels(layout)
        XCTAssertLessThan(labels.count, 60)
        XCTAssertEqual(labels.first, "category1")
        let numbers = labels.map { label in Int(label.dropFirst("category".count)) ?? 0 }
        let gaps = zip(numbers.dropFirst(), numbers).map { next, number in next - number }
        XCTAssertEqual(Set(gaps).count, 1, "Every so many categories")
    }

    func testDotsAreLeftOutWhenPlacesAreCloserThanTwelvePoints() throws {
        let values = (1...100).map(String.init).joined(separator: ", ")
        XCTAssertTrue(try laidOut("xychart\nline [\(values)]").lines[0].dots.isEmpty)
        XCTAssertEqual(try laidOut("xychart\nline [1, 2, 3]").lines[0].dots.count, 3)
    }

    func testAChartWithoutSeriesIsNotLaidOut() {
        XCTAssertThrowsError(try laidOut("xychart\ntitle \"Empty\"\nx-axis [a, b]")) { error in
            XCTAssertEqual(error as? XYChartLayoutError, .noSeries)
        }
    }
}
