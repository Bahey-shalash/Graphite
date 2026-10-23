import XCTest
@testable import MermaidDiagrams

final class TimelineDrawingPartsTests: XCTestCase {
    private func parts(_ source: String) throws -> TimelineDrawingParts {
        let layout = TimelineLayoutEngine.layout(try TimelineReading.timeline(source), periodText: UniformWidthTextMeasurer(),
                                                 eventText: UniformWidthTextMeasurer(), font: DiagramFont(postScriptName: nil, size: 16))
        return TimelineDrawingParts(layout: layout)
    }

    func testBoxesAndDotsAreGroupedByColorTheSeriesTakenAgainAfterTheEighth() throws {
        let parts = try parts("timeline\n" + (0..<10).map { year in "  \(2000 + year) : event" }.joined(separator: "\n"))
        XCTAssertEqual(parts.colorGroups.map(\.color), (0..<8).map(TimelineColor.series))
        XCTAssertFalse(parts.colorGroups[0].eventBoxes.isEmpty)
        XCTAssertEqual(parts.periodTexts.count, 10)
        XCTAssertEqual(parts.eventTexts.count, 10)
    }

    func testSectionsShareTheirPeriodsColorAndLeadingPeriodsAreMuted() throws {
        let parts = try parts("timeline\n  early\n  section One\n  later\n  section Two")
        XCTAssertEqual(parts.colorGroups.map(\.color), [.series(0), .series(1), .muted])
        XCTAssertEqual(parts.sectionTexts.count, 2)
        XCTAssertTrue(parts.colorGroups[1].dots.isEmpty, "A section without periods has a box and no dot")
    }

    func testTheAxisItsArrowAndTheConnectorsAreTheirOwnParts() throws {
        let parts = try parts("timeline\n  2002 : one : two")
        XCTAssertFalse(parts.axis.isEmpty)
        XCTAssertFalse(parts.axisArrow.isEmpty)
        XCTAssertFalse(parts.connectors.isEmpty)
        let empty = try self.parts("timeline")
        XCTAssertTrue(empty.axis.isEmpty && empty.axisArrow.isEmpty && empty.connectors.isEmpty && empty.colorGroups.isEmpty)
    }
}
