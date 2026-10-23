import XCTest
import SwiftUI
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingTimelineShapesTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private struct NotDrawnAsATimeline: Error {}

    private func timeline(_ source: String) throws -> ReadingTimeline {
        guard case .timeline(let timeline) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else { throw NotDrawnAsATimeline() }
        return timeline
    }

    func testBoxesAndDotsKeepTheirColorAndTheLinesTheirOwnPaths() throws {
        let timeline = try timeline("timeline\n  early\n  section One\n  2002 : LinkedIn")
        XCTAssertEqual(timeline.shapes.colorGroups.map(\.color), [.series(0), .muted])
        XCTAssertEqual(timeline.shapes.colorGroups[0].eventBoxes.boundingRect, timeline.layout.periods[1].events[0].frame)
        XCTAssertFalse(timeline.shapes.axis.isEmpty)
        XCTAssertFalse(timeline.shapes.axisArrow.isEmpty)
        XCTAssertFalse(timeline.shapes.connectors.isEmpty)
    }

    func testTextOnBoxesIsSectionsInBoldThenPeriodsAndTheTitleComesLast() throws {
        let timeline = try timeline("timeline\n  title History\n  section One\n  2002 : LinkedIn")
        XCTAssertEqual(timeline.shapes.textLinesOnBoxes.map(\.text), ["One", "2002"])
        XCTAssertEqual(timeline.shapes.textLinesOnBoxes.map(\.isBold), [true, false])
        XCTAssertEqual(timeline.shapes.textLines.map(\.text), ["LinkedIn", "History"])
        XCTAssertEqual(timeline.shapes.textLines.first?.font.size, 14, "Events are seven eighths of the text size")
        XCTAssertEqual(timeline.shapes.textLines.last?.isBold, true)
    }

    func testTheMutedColorLiesBetweenTheBorderAndTheText() {
        let colors = ReadingDiagramColors(background: .white, foreground: .black)
        XCTAssertNotEqual(colors.muted, colors.border)
        XCTAssertNotEqual(colors.muted, colors.foreground)
    }
}
