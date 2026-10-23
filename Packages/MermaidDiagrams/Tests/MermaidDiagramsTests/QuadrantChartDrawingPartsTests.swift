import XCTest
@testable import MermaidDiagrams

/// A laid-out quadrant chart grouped by how it is painted.
final class QuadrantChartDrawingPartsTests: XCTestCase {
    private func parts(_ source: String) throws -> (QuadrantChartLayout, QuadrantChartDrawingParts) {
        let layout = try QuadrantChartReading.uniformLayout(source)
        return (layout, QuadrantChartDrawingParts(layout: layout))
    }

    func testTheQuadrantsAxesAndTextsHaveTheirParts() throws {
        let (layout, parts) = try parts(QuadrantChartReading.reachAndEngagement)
        let plot = layout.quadrants.map(\.frame).reduce(layout.quadrants[0].frame) { union, frame in union.union(frame) }
        XCTAssertEqual(parts.quadrants.boundingBoxOfPath.minX, plot.minX, accuracy: 0.001)
        XCTAssertEqual(parts.quadrants.boundingBoxOfPath.maxY, plot.maxY, accuracy: 0.001)
        XCTAssertEqual(parts.quadrantTexts.map(\.lines), [["We should expand"], ["Need to promote"], ["Re-evaluate"], ["May be improved"]])
        XCTAssertEqual(parts.axisTexts.map(\.lines), [["Low Reach"], ["High Reach"]])
        XCTAssertEqual(parts.turnedAxisTexts.map(\.lines), [["Low Engagement"], ["High Engagement"]])
        XCTAssertEqual(parts.pointTexts.count, 6)
        XCTAssertEqual(parts.title?.lines, ["Reach and engagement of campaigns"])
    }

    func testPointsPaintedAlikeShareAGroupAndTheLastWrittenComesFirst() throws {
        let (layout, parts) = try parts("quadrantChart\n A: [0.1, 0.1]\n B: [0.2, 0.2]\n C: [0.3, 0.3] color: #ff0000\n D: [0.4, 0.4]")
        XCTAssertEqual(parts.pointGroups.map(\.fill), [.firstSeries, .written(QuadrantChartColor(red: 255, green: 0, blue: 0)), .firstSeries])
        XCTAssertEqual(parts.pointGroups[0].circles.boundingBoxOfPath.midX, layout.points[3].center.x, accuracy: 0.001, "D, written last, is under the rest")
        XCTAssertEqual(parts.pointGroups[2].circles.boundingBoxOfPath.minX, layout.points[0].center.x - 5, accuracy: 0.001)
        XCTAssertEqual(parts.pointGroups[2].circles.boundingBoxOfPath.maxX, layout.points[1].center.x + 5, accuracy: 0.001)
    }

    func testAPointWithAnOutlineHasAGroupOfItsOwn() throws {
        let (_, parts) = try parts("quadrantChart\n A: [0.1, 0.1] stroke-width: 2px\n B: [0.2, 0.2] stroke-width: 2px")
        XCTAssertEqual(parts.pointGroups.count, 2)
        XCTAssertEqual(parts.pointGroups.map(\.stroke), Array(repeating: QuadrantChartStroke(paint: .firstSeries, width: 2), count: 2))
    }

    func testAChartWithoutPointsHasNoPointGroups() throws {
        XCTAssertTrue(try parts("quadrantChart\n quadrant-1 Plan").1.pointGroups.isEmpty)
    }
}
