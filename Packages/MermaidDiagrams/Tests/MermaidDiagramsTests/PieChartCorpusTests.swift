import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Mermaid's pie chart documentation examples and the benchmark's generated pies, all read and laid out.
final class PieChartCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsDrawn() throws {
        let examples = try PieChartCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 2)
        for example in examples {
            let layout = PieChartLayoutEngine.layout(try PieChartReading.pieChart(example), typography: typography)
            XCTAssertEqual(layout.slices.count, layout.legend.count, example)
            XCTAssertGreaterThan(layout.size.width, 2 * layout.radius)
        }
    }

    func testTheGeneratedPiesAreDrawnWithEverySliceInTheLegend() throws {
        for sliceCount in [8, 100] {
            let chart = try PieChartReading.pieChart(PieChartCorpus.pie(sliceCount: sliceCount))
            XCTAssertEqual(chart.slices.count, sliceCount)
            XCTAssertTrue(chart.slices.allSatisfy { slice in slice.value >= 1 && slice.value < 100 })
            let layout = PieChartLayoutEngine.layout(chart, typography: typography)
            XCTAssertEqual(layout.legend.count, sliceCount)
            XCTAssertFalse(layout.slices.isEmpty)
        }
        let eight = PieChartLayoutEngine.layout(try PieChartReading.pieChart(PieChartCorpus.pie(sliceCount: 8)), typography: typography)
        XCTAssertEqual(eight.slices.last?.endAngle ?? 0, 2 * .pi, accuracy: 1e-9)
    }
}
