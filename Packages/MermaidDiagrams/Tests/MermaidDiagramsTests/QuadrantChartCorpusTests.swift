import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Mermaid's quadrant chart documentation examples, all read and laid out, and the benchmark's generated charts.
final class QuadrantChartCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsDrawn() throws {
        let examples = try QuadrantChartCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 3)
        let layouts = try examples.map { example in QuadrantChartLayoutEngine.layout(try QuadrantChartReading.quadrantChart(example), typography: typography) }
        XCTAssertEqual(layouts.map(\.points.count), [6, 0, 6])
        XCTAssertEqual(layouts.map { layout in layout.quadrants.compactMap(\.text).count }, [4, 4, 4])
        XCTAssertEqual(layouts.map(\.axisLabels.count), [4, 4, 4])
    }

    func testTheGeneratedChartsKeepEveryTextInsideThePlot() throws {
        for pointCount in [20, 300, 1_000] {
            let chart = try QuadrantChartReading.quadrantChart(QuadrantChartCorpus.generated(pointCount: pointCount))
            XCTAssertEqual(chart.points.count, pointCount)
            let layout = QuadrantChartLayoutEngine.layout(chart, typography: typography)
            XCTAssertEqual(layout.points.count, pointCount)
            let plot = layout.quadrants.map(\.frame).reduce(layout.quadrants[0].frame) { union, frame in union.union(frame) }
            for point in layout.points { XCTAssertTrue(plot.insetBy(dx: -0.001, dy: -0.001).contains(point.text.center), "\(point.text.center)") }
        }
    }
}
