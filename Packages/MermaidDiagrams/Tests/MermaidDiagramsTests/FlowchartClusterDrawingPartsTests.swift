import XCTest
@testable import MermaidDiagrams

final class FlowchartClusterDrawingPartsTests: XCTestCase {
    private func layout(_ source: String) throws -> FlowchartLayout {
        try UniformWidthLayout.layout(source)
    }

    func testBoxesAreFilledDepthByDepthAndAllOutlined() throws {
        let laidOut = try layout("flowchart TD\nsubgraph outer\nA\nsubgraph inner\nB\nend\nend\nsubgraph beside\nC\nend")
        let parts = FlowchartDrawingParts(layout: laidOut).clusters
        XCTAssertEqual(parts.fillsByDepth.count, 2)
        assertSame(parts.fillsByDepth[0].boundingBoxOfPath, laidOut.clusters[0].frame.union(laidOut.clusters[2].frame))
        assertSame(parts.fillsByDepth[1].boundingBoxOfPath, laidOut.clusters[1].frame)
        assertSame(parts.outlines.boundingBoxOfPath, laidOut.clusters.map(\.frame).reduce(CGRect.null) { bounds, frame in bounds.union(frame) })
    }

    private func assertSame(_ rectangle: CGRect, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        for (value, expectedValue) in [(rectangle.minX, expected.minX), (rectangle.minY, expected.minY), (rectangle.maxX, expected.maxX),
                                       (rectangle.maxY, expected.maxY)] {
            XCTAssertEqual(value, expectedValue, accuracy: 0.01, file: file, line: line)
        }
    }

    func testATitleIsPaintedWithItsBoxUnlessAnEdgeRunsThroughIt() throws {
        let clear = FlowchartDrawingParts(layout: try layout("flowchart TD\nsubgraph S [Title]\nA\nend")).clusters
        XCTAssertEqual(clear.titles.map(\.lines), [["Title"]])
        XCTAssertTrue(clear.crossedTitles.isEmpty)
        XCTAssertTrue(clear.crossedTitlePatchesByDepth.allSatisfy(\.isEmpty))
        let laidOut = try layout("flowchart TD\nX --> A\nsubgraph S [A title as wide as the box]\nA\nend")
        let crossed = FlowchartDrawingParts(layout: laidOut).clusters
        let title = try XCTUnwrap(laidOut.clusters[0].title)
        XCTAssertTrue(crossed.titles.isEmpty)
        XCTAssertEqual(crossed.crossedTitles, [title])
        XCTAssertEqual(crossed.crossedTitlePatchesByDepth[0].boundingBoxOfPath.width, title.frame.width + 5, accuracy: 0.01)
    }

    func testAFlowchartWithoutGroupsHasNoBoxes() throws {
        let parts = FlowchartDrawingParts(layout: try layout("flowchart TD\nA --> B")).clusters
        XCTAssertTrue(parts.fillsByDepth.isEmpty)
        XCTAssertTrue(parts.outlines.isEmpty)
    }
}
