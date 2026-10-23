import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Mermaid's XY chart documentation examples, all read and laid out, and the benchmark's generated charts.
final class XYChartCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsDrawn() throws {
        let examples = try XYChartCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 8)
        for example in examples {
            let chart = try XYChartReading.chart(example)
            let layout = try XYChartLayoutEngine.layout(chart, typography: typography)
            XCTAssertNotNil(layout.title, example)
            XCTAssertEqual(layout.bars.isEmpty && layout.lines.isEmpty, false, example)
            XCTAssertEqual(layout.lines.count, chart.series.filter { series in series.kind == .line }.count)
            XCTAssertTrue(layout.bars.allSatisfy { bar in layout.plotFrame.insetBy(dx: -0.001, dy: -0.001).contains(bar.frame) }, example)
        }
    }

    func testTheGeneratedChartsAreDrawnWithEveryBar() throws {
        for (categoryCount, seriesCount) in [(12, 2), (100, 4)] {
            let chart = try XYChartReading.chart(XYChartCorpus.generated(categoryCount: categoryCount, seriesCount: seriesCount))
            XCTAssertEqual(chart.series.count, seriesCount)
            XCTAssertTrue(chart.series.allSatisfy { series in series.values.count == categoryCount })
            let layout = try XYChartLayoutEngine.layout(chart, typography: typography)
            XCTAssertEqual(layout.bars.count, categoryCount * ((seriesCount + 1) / 2), "One bar series in two")
            XCTAssertEqual(layout.legend.count, seriesCount)
        }
    }
}
