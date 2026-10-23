import XCTest
@testable import MermaidDiagrams

final class GanttRendererTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    /// Colors told apart in every channel: a blue page, black text, a red accent, a green critical color, a yellow
    /// second surface, a gray surface and a magenta border.
    private let palette = DiagramPalette(background: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), foreground: CGColor(gray: 0, alpha: 1),
                                         line: CGColor(gray: 0, alpha: 1), surface: CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1),
                                         border: CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1), accent: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
                                         critical: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1), muted: CGColor(gray: 0.4, alpha: 1),
                                         alternateSurface: CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1))

    /// Laid out in UTC on 2014-01-08 12:00.
    private func laidOut(_ source: String) throws -> GanttLayout {
        try GanttLayoutEngine.layout(try GanttChartReading.ganttChart(source), typography: typography, now: Date(timeIntervalSince1970: 1_389_182_400),
                                     timeZone: try XCTUnwrap(TimeZone(identifier: "UTC")), limits: .standard)
    }

    private func drawn(_ layout: GanttLayout) throws -> DiagramBitmap {
        let bitmap = try XCTUnwrap(DiagramBitmap(size: layout.size))
        GanttRenderer.draw(layout, in: bitmap.context, palette: palette)
        return bitmap
    }

    private struct TaskWithoutShape: Error {}

    private func frame(of task: GanttLayoutTask) throws -> CGRect {
        switch task.shape {
        case .bar(let frame), .milestone(let frame): return frame
        case .unscheduled: throw TaskWithoutShape()
        }
    }

    private let tasks = """
    gantt
        dateFormat YYYY-MM-DD
        Planned work : 2014-01-01, 4d
        Critical work : crit, 2014-01-02, 4d
        Finished work : done, 2014-01-03, 4d
        Ongoing work : active, 2014-01-04, 4d
        Launch : milestone, 2014-01-09, 0d
    """

    func testEachTaskIsFilledAndOutlinedInItsColors() throws {
        let layout = try laidOut(tasks)
        let plot = try XCTUnwrap(layout.plot)
        let bitmap = try drawn(layout)
        func colorInside(_ index: Int) throws -> [Int] {
            let frame = try frame(of: plot.tasks[index])
            return bitmap.color(at: CGPoint(x: frame.minX + 4, y: frame.minY + 3))
        }
        XCTAssertEqual(try colorInside(0), [0xFF, 0, 0], "The accent")
        XCTAssertEqual(try colorInside(1), [0, 0xFF, 0], "Critical")
        XCTAssertEqual(try colorInside(2), [0xFF, 0xFF, 0], "Done: the second surface")
        let active = try colorInside(3)
        XCTAssertEqual(active[0], 0xFF, "A quarter of the accent on the white bitmap")
        XCTAssertEqual(active[1], 0xBF, accuracy: 2)
        let finished = try frame(of: plot.tasks[2])
        let outline = bitmap.color(at: CGPoint(x: finished.midX, y: finished.minY))
        XCTAssertTrue(outline[2] > 0x60 && outline[0] > 0xC0, "Done: the border's outline on the second surface, \(outline)")
        let milestone = try frame(of: plot.tasks[4])
        XCTAssertEqual(bitmap.color(at: CGPoint(x: milestone.midX, y: milestone.midY)), [0xFF, 0, 0])
        XCTAssertEqual(bitmap.color(at: CGPoint(x: milestone.minX + 1, y: milestone.minY + 1)), [0xFF, 0xFF, 0xFF], "A diamond leaves its corners")
    }

    func testTextInsideAPlannedBarIsInThePagesColor() throws {
        let layout = try laidOut("gantt\n    dateFormat YYYY-MM-DD\n    Planned work : 2014-01-01, 10d\n    Other : 2014-01-11, 1d")
        let task = try XCTUnwrap(layout.plot?.tasks.first)
        XCTAssertEqual(task.labelColor, .background)
        let bitmap = try drawn(layout)
        var hasPageColoredText = false
        for x in Int(task.label.frame.minX)..<Int(task.label.frame.maxX) {
            for y in Int(task.label.frame.minY)..<Int(task.label.frame.maxY) where bitmap.color(at: CGPoint(x: x, y: y)) == [0, 0, 0xFF] {
                hasPageColoredText = true
            }
        }
        XCTAssertTrue(hasPageColoredText)
    }

    func testTheGridIsDottedTodaysLineIsInTheAccentAndExcludedDaysAreShaded() throws {
        let layout = try laidOut("gantt\n    dateFormat YYYY-MM-DD\n    excludes weekends\n    Work : 2014-01-01, 14d")
        let plot = try XCTUnwrap(layout.plot)
        let bitmap = try drawn(layout)
        let gridLine = try XCTUnwrap(plot.gridLineOffsets.first { offset in abs(offset - (plot.todayOffset ?? 0)) > 4 })
        let rowGap = (Int(plot.frame.minY)..<Int(plot.frame.minY) + 3)
        let strip = rowGap.flatMap { y in (-1...1).map { dx in bitmap.color(at: CGPoint(x: gridLine + CGFloat(dx), y: CGFloat(y))) } }
        XCTAssertTrue(strip.contains { color in color[1] < 0xD0 && color[0] > 0xC0 && color[2] > 0xC0 }, "A dot of the border: \(strip)")
        XCTAssertTrue(strip.contains { color in color == [0xFF, 0xFF, 0xFF] || color == [0xFF, 0xFF, 0] }, "A gap")
        let today = try XCTUnwrap(plot.todayOffset)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: today, y: plot.frame.maxY - 2)), [0xFF, 0, 0])
        let weekend = try XCTUnwrap(plot.excludedDays.first)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: weekend.minX + 3, y: weekend.maxY - 2)), [0xFF, 0xFF, 0], "The second surface")
        XCTAssertEqual(bitmap.color(at: CGPoint(x: weekend.minX - 6, y: weekend.maxY - 2)), [0xFF, 0xFF, 0xFF], "Nothing beside it")
    }

    func testSectionsAlternateTheirBandsAndTheAxisIsDrawnInTheBorder() throws {
        let layout = try laidOut("gantt\n    dateFormat YYYY-MM-DD\n    section One\n    A : 2014-01-01, 2d\n    section Two\n    B : 2014-01-03, 2d")
        let plot = try XCTUnwrap(layout.plot)
        let bitmap = try drawn(layout)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: 2, y: plot.frame.minY + 2)), [0x80, 0x80, 0x80], "The first section's band")
        XCTAssertEqual(bitmap.color(at: CGPoint(x: 2, y: plot.frame.maxY - 2)), [0xFF, 0xFF, 0xFF], "The second has none")
        let axis = bitmap.color(at: CGPoint(x: plot.frame.midX + 1, y: plot.frame.maxY))
        XCTAssertTrue(axis[0] > 0xC0 && axis[1] < 0xD0 && axis[2] > 0xC0, "The border: \(axis)")
    }
}
