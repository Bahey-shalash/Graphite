import XCTest
import SwiftUI
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingGanttChartShapesTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private struct NotDrawnAsAGanttChart: Error {}

    private func ganttChart(_ source: String) throws -> ReadingGanttChart {
        guard case .ganttChart(let chart) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else { throw NotDrawnAsAGanttChart() }
        return chart
    }

    func testTextIsGroupedByTheColorItIsDrawnIn() throws {
        let gantt = try ganttChart("gantt\ntitle Plan\ndateFormat YYYY-MM-DD\nsection Build\nInside : 2014-01-01, 20d\n"
                                   + "A task named at length beside its bar : done, 2014-01-21, 1d")
        XCTAssertEqual(gantt.shapes.backgroundTextLines.map(\.text), ["Inside"])
        XCTAssertEqual(gantt.shapes.foregroundTextLines.map(\.text), ["Build", "Plan"])
        XCTAssertEqual(gantt.shapes.foregroundTextLines.last?.isBold, true)
        XCTAssertEqual(gantt.shapes.mutedTextLines.first?.text, "A task named at length beside its bar")
        XCTAssertEqual(gantt.shapes.mutedTextLines.count, 1 + (gantt.layout.plot?.axisDates.count ?? 0))
    }

    func testTaskShapesKeepAFixedOrderOfColors() throws {
        let gantt = try ganttChart("gantt\ndateFormat YYYY-MM-DD\nA : crit, 2014-01-01, 2d\nB : done, 2014-01-02, 2d\nC : active, 2014-01-03, 2d")
        XCTAssertEqual(gantt.shapes.taskFills.map(\.fill), [.alternateSurface, .faintAccent, .critical])
        XCTAssertEqual(gantt.shapes.taskOutlines.map(\.stroke), [.border, .accent, .critical])
        XCTAssertFalse(gantt.shapes.gridLines.isEmpty)
        XCTAssertTrue(gantt.shapes.sectionBands.isEmpty, "No sections, no bands")
    }

    func testTheChartsColorsSitBetweenThePageAndTheTextWhereThemeLeavesThem() {
        let text = Color(.sRGB, red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255)
        let colors = ReadingDiagramColors(background: Color(.sRGB, red: 1, green: 1, blue: 1), foreground: text)
        func red(_ color: Color) -> CGFloat {
            let resolved = color.resolve(in: EnvironmentValues()).cgColor
            return (resolved.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components?.first ?? 0) * 255
        }
        XCTAssertEqual(red(colors.muted), 0x6E, accuracy: 1.5)
        XCTAssertEqual(red(colors.alternateSurface), 0xE6, accuracy: 1.5)
        XCTAssertEqual(red(colors.critical), 0xE4, accuracy: 1)
    }
}
