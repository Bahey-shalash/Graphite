import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Mermaid's Gantt documentation examples and the benchmark's generated charts, all read, scheduled and laid out on
/// the benchmark's moment, so that none crashes and each that is not drawn says why.
final class GanttChartCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func layout(_ source: String) throws -> GanttLayout {
        try GanttLayoutEngine.layout(try GanttChartReading.ganttChart(source), typography: typography, now: GanttChartCorpus.now,
                                     timeZone: GanttChartCorpus.timeZone, limits: .standard)
    }

    func testEveryDocumentationExampleIsDrawnOrRefusedForAReason() throws {
        let examples = try GanttChartCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 11)
        var drawnCount = 0
        var refusals: [GanttLayoutError] = []
        for example in examples {
            do {
                let layout = try layout(example)
                XCTAssertGreaterThan(layout.size.width, 0)
                drawnCount += 1
            } catch let error as GanttLayoutError {
                refusals.append(error)
            }
        }
        XCTAssertEqual(drawnCount, 9)
        XCTAssertEqual(refusals, [.statementNotDrawn(.verticalMarker), .statementNotDrawn(.verticalMarker)])
    }

    func testTheGeneratedChartsScheduleEveryTask() throws {
        for taskCount in [20, 200] {
            let plot = try XCTUnwrap(try layout(GanttChartCorpus.chart(taskCount: taskCount)).plot)
            XCTAssertEqual(plot.tasks.count, taskCount)
            XCTAssertFalse(plot.tasks.contains { task in task.shape == .unscheduled })
            XCTAssertEqual(plot.sectionNames.count, taskCount / 10)
        }
    }
}
