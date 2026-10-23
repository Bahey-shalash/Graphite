import XCTest
import GraphiteCore
import GraphiteIndex
import MermaidDiagrams
@testable import GraphiteUI
import GraphiteTestSupport

/// A ```mermaid block holding a quadrant chart: read and laid out with the note's other blocks, off the main actor, in
/// the note's text size; one that cannot be read keeps its source and says why.
final class ReadingQuadrantChartTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
    private struct NotDrawnAsAQuadrantChart: Error {}

    private func chart(_ source: String) throws -> ReadingQuadrantChart {
        guard case .quadrantChart(let chart) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            throw NotDrawnAsAQuadrantChart()
        }
        return chart
    }

    func testAQuadrantChartIsLaidOutInTheNotesTextSize() throws {
        let chart = try chart("quadrantChart\n  quadrant-1 Plan\n  quadrant-3 Delegate\n  Campaign A: [0.3, 0.6]\n  Off the chart: [0x5, 1]\n  Corner: [1, 0]")
        XCTAssertEqual(chart.layout.font.size, 17)
        XCTAssertEqual(chart.layout.points.count, 2)
        XCTAssertEqual(chart.summaries, ["Plan", "Delegate", "Campaign A (0.3, 0.6)", "Corner (1, 0)"])
    }

    func testAccessibilityTextComesFromTheChart() throws {
        let titled = try chart("quadrantChart\n  title Priorities\n  accDescr: Four boxes\n  quadrant-1 Plan")
        XCTAssertEqual(titled.title, "Priorities")
        XCTAssertEqual(titled.description, "Four boxes")
        XCTAssertEqual(try chart("quadrantChart\n  accTitle: Named\n  title Shown").title, "Named")
    }

    func testAQuadrantChartThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "quadrantChart\n  A: [0.1, 0.1] color: red"
        guard case .unreadable(let shownSource, let failure) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .invalidPointStyleValue(name: "color", value: "red"))))
    }

    func testTheQuadrantChartsProblemsAreExplainedApartFromTheOthers() {
        let problems: [MermaidSyntaxProblem] = [.unexpectedText("C"), .expectedTaskScore, .expectedSliceValue, .expectedPointCoordinates,
                                                .expectedAxisOrQuadrantText, .expectedPointStyle, .unsupportedPointStyle(name: "fill"),
                                                .invalidPointStyleValue(name: "radius", value: "big")]
        XCTAssertEqual(Set(problems.map(\.explanation)).count, problems.count)
    }

    func testTheReadingViewBuildsAQuadrantChartBlockBetweenTheTextAroundIt() async throws {
        let vault = try TemporaryVault.make(prefix: "QuadrantChartVault", for: self).root
        defer { try? FileManager.default.removeItem(at: vault) } // Best-effort removal of a temporary folder.
        let index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
        let blocks = try await ReadingViewBuilder().build(source: "Before\n\n```mermaid\nquadrantChart\n  x-axis Low --> High\n```\n\nAfter",
                                                           note: try VaultPath("Note.md"), root: vault, index: index,
                                                           configuration: ReadingConfiguration()).blocks
        XCTAssertEqual(blocks.count, 3)
        guard case .diagram(_, .quadrantChart(let chart)) = blocks[1] else { return XCTFail("The quadrant chart is drawn") }
        XCTAssertEqual(chart.layout.axisLabels.count, 2)
    }
}
