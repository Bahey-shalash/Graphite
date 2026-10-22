import XCTest
@testable import MermaidDiagrams

/// Pele's timeline measurements, with period text 8 points a character and 24 a line, and event text 7 and 21.
final class TimelineLayoutEngineTests: XCTestCase {
    private let accuracy: CGFloat = 0.01

    private func layout(_ source: String) throws -> TimelineLayout {
        TimelineLayoutEngine.layout(try TimelineReading.timeline(source), periodText: UniformWidthTextMeasurer(),
                                    eventText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                    font: DiagramFont(postScriptName: nil, size: 16))
    }

    func testAcrossPeriodsSitInColumnsAboveTheAxisWithTheirEventsBelow() throws {
        let layout = try layout("timeline\n  2002 : LinkedIn\n  2004 : Facebook : Google")
        XCTAssertEqual(layout.periods.map(\.frame), [CGRect(x: 8, y: 8, width: 176, height: 40), CGRect(x: 204, y: 8, width: 176, height: 40)])
        XCTAssertEqual(layout.periods.map(\.dot), [CGPoint(x: 96, y: 68), CGPoint(x: 292, y: 68)])
        XCTAssertEqual(layout.periods[1].events.map(\.frame), [CGRect(x: 204, y: 88, width: 176, height: 37), CGRect(x: 204, y: 133, width: 176, height: 37)])
        XCTAssertEqual(layout.periods[1].connectors.map(\.allPoints), [[CGPoint(x: 292, y: 48), CGPoint(x: 292, y: 88)],
                                                                       [CGPoint(x: 292, y: 125), CGPoint(x: 292, y: 133)]])
        XCTAssertEqual(layout.size, CGSize(width: 2 * 196 - 20 + 12 + 8 + 16, height: 178))
        XCTAssertEqual(layout.periods[0].text.center, CGPoint(x: 96, y: 28))
    }

    func testTheAxisRunsPastTheLastPeriodToItsArrow() throws {
        let layout = try layout("timeline\n  2002 : LinkedIn\n  2004")
        XCTAssertEqual(layout.axis?.allPoints, [CGPoint(x: 8, y: 68), CGPoint(x: 393, y: 68)])
        XCTAssertEqual(layout.axisArrow, DiagramEdgeMark(arrowhead: .arrow, tip: CGPoint(x: 400, y: 68), direction: CGVector(dx: 1, dy: 0)))
        XCTAssertEqual(layout.periods[1].connectors.map(\.allPoints), [[CGPoint(x: 292, y: 48), CGPoint(x: 292, y: 68)]], "Without events, to the axis")
    }

    func testWithoutSectionsPeriodsTakeTheSeriesColorsInTurn() throws {
        let layout = try layout("timeline\n  a\n  b\n  c")
        XCTAssertEqual(layout.periods.map(\.color), [.series(0), .series(1), .series(2)])
        XCTAssertTrue(layout.sections.isEmpty)
    }

    func testASectionHeadsItsPeriodsColumnsInItsColor() throws {
        let layout = try layout("timeline\n  section A\n  a\n  b\n  section B\n  c")
        XCTAssertEqual(layout.sections.map(\.frame), [CGRect(x: 8, y: 8, width: 372, height: 40), CGRect(x: 400, y: 8, width: 176, height: 40)])
        XCTAssertEqual(layout.sections.map(\.sectionIndex), [0, 1])
        XCTAssertEqual(layout.periods.map(\.color), [.series(0), .series(0), .series(1)])
        XCTAssertEqual(layout.periods[0].frame.minY, 8 + 40 + 8)
    }

    func testPeriodsBeforeTheFirstSectionLeadInTheMutedColor() throws {
        let layout = try layout("timeline\n  first\n  section S\n  second")
        XCTAssertEqual(layout.periods.map(\.color), [.muted, .series(0)])
        XCTAssertEqual(layout.periods[0].frame.minX, 8)
        XCTAssertEqual(layout.sections[0].frame.minX, 204)
    }

    func testASectionWithoutPeriodsTakesOneColumn() throws {
        let layout = try layout("timeline\n  section Empty\n  section Full\n  a")
        XCTAssertEqual(layout.sections.map(\.frame.width), [176, 176])
        XCTAssertEqual(layout.periods[0].frame.minX, 204)
    }

    func testAWideWordWidensTheColumnsUpTo216PointsAndIsCutPastThat() throws {
        let widened = try layout("timeline\n  " + String(repeating: "w", count: 20))
        XCTAssertEqual(widened.periods[0].frame.width, 160 + 24)
        XCTAssertEqual(widened.periods[0].text.lines.count, 1)
        let cut = try layout("timeline\n  " + String(repeating: "w", count: 34))
        XCTAssertEqual(cut.periods[0].frame.width, 216 + 24)
        XCTAssertEqual(cut.periods[0].text.lines.map(\.count), [27, 7])
    }

    func testDownPeriodsSitInAColumnLeftOfTheAxisWithTheirEventsBeside() throws {
        let layout = try layout("timeline TD\n  2002 : LinkedIn : More\n  2004")
        XCTAssertEqual(layout.direction, .topToBottom)
        XCTAssertEqual(layout.periods[0].frame, CGRect(x: 8, y: 8, width: 176, height: 40))
        XCTAssertEqual(layout.periods[0].dot, CGPoint(x: 204, y: 28))
        XCTAssertEqual(layout.periods[0].events.map(\.frame), [CGRect(x: 232, y: 9.5, width: 288, height: 37), CGRect(x: 232, y: 54.5, width: 288, height: 37)])
        XCTAssertEqual(layout.periods[0].connectors.map(\.allPoints), [
            [CGPoint(x: 184, y: 28), CGPoint(x: 204, y: 28)], [CGPoint(x: 218, y: 28), CGPoint(x: 232, y: 28)],
            [CGPoint(x: 218, y: 73), CGPoint(x: 232, y: 73)], [CGPoint(x: 204, y: 28), CGPoint(x: 218, y: 28), CGPoint(x: 218, y: 73)],
        ])
        XCTAssertEqual(layout.periods[1].frame.minY, 91.5 + 20)
        XCTAssertEqual(layout.axisArrow?.tip, CGPoint(x: 204, y: 151.5 + 12 + 8))
        XCTAssertEqual(layout.size, CGSize(width: 512 + 16, height: 180))
    }

    func testDownASectionHeadsTheWholeWidth() throws {
        let layout = try layout("timeline TD\n  section S\n  a : event")
        XCTAssertEqual(layout.sections[0].frame, CGRect(x: 8, y: 8, width: 512, height: 40))
        XCTAssertEqual(layout.periods[0].frame.minY, 8 + 40 + 8 + 4)
    }

    func testTheTitleWrapsAt320PointsAboveTheBodyWhichIsCenteredUnderIt() throws {
        var diagram = try TimelineReading.timeline("timeline\n  a")
        diagram.title = String(repeating: "T", count: 60)
        let layout = TimelineLayoutEngine.layout(diagram, periodText: UniformWidthTextMeasurer(), eventText: UniformWidthTextMeasurer(),
                                                 font: DiagramFont(postScriptName: nil, size: 16))
        let title = try XCTUnwrap(layout.title)
        XCTAssertEqual(title.lines.map(\.count), [40, 20])
        XCTAssertEqual(layout.size.width, 320 + 16)
        XCTAssertEqual(title.center, CGPoint(x: 168, y: 8 + 24))
        XCTAssertEqual(layout.periods[0].frame.minY - title.frame.maxY, 16, accuracy: accuracy)
        XCTAssertEqual(layout.periods[0].frame.minX, 8 + (320 - 196) / 2, accuracy: accuracy)
    }

    func testAnEmptyTimelineIsOnlyItsPadding() throws {
        let layout = try layout("timeline")
        XCTAssertEqual(layout.size, CGSize(width: 16, height: 16))
        XCTAssertNil(layout.axis)
        XCTAssertTrue(layout.periods.isEmpty)
    }
}
