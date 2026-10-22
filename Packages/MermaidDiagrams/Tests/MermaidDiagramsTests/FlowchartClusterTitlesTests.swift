import XCTest
@testable import MermaidDiagrams

final class FlowchartClusterTitlesTests: XCTestCase {
    /// "Title": 40 points wide and 24 high.
    private let title = DiagramTextBlock(label: DiagramLabel("Title"), measurer: UniformWidthTextMeasurer(), maximumWidth: 200)
    private let frame = CGRect(x: 0, y: 0, width: 200, height: 100)

    /// Edges entering the box's top at each of `crossings`.
    private func edges(enteringAt crossings: [CGFloat]) -> [[CGPoint]] {
        crossings.map { crossing in [CGPoint(x: crossing, y: -40), CGPoint(x: crossing, y: 0), CGPoint(x: crossing, y: 60)] }
    }

    func testATitleSitsAtTheLeftOfTheTopBand() {
        let placed = FlowchartClusterTitles.placed(title, in: frame, edgePoints: [])
        XCTAssertEqual(placed.title.center, CGPoint(x: 20 - 6 + 20, y: 8 + 12))
        XCTAssertFalse(placed.isCrossed)
    }

    func testATitleMovesToTheMiddleThenTheRightToKeepClearOfEdgesCrossingTheTop() {
        XCTAssertEqual(FlowchartClusterTitles.placed(title, in: frame, edgePoints: edges(enteringAt: [34])).title.center.x, 100)
        let right = FlowchartClusterTitles.placed(title, in: frame, edgePoints: edges(enteringAt: [34, 100]))
        XCTAssertEqual(right.title.center.x, 200 - 20 + 6 - 20)
        XCTAssertFalse(right.isCrossed)
    }

    func testATitleNoPlaceKeepsClearOfIsCrossedAndStaysAtTheLeft() {
        let placed = FlowchartClusterTitles.placed(title, in: frame, edgePoints: edges(enteringAt: [34, 100, 166]))
        XCTAssertEqual(placed.title.center.x, 34)
        XCTAssertTrue(placed.isCrossed)
    }

    func testOnlyPointsOnTheTopWithinTheBoxCount() {
        let elsewhere = [[CGPoint(x: 34, y: 30), CGPoint(x: -10, y: 0), CGPoint(x: 230, y: 0)]]
        let placed = FlowchartClusterTitles.placed(title, in: frame, edgePoints: elsewhere)
        XCTAssertEqual(placed.title.center.x, 34)
        XCTAssertFalse(placed.isCrossed)
    }
}
